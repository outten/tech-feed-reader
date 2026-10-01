## Context

The web app is already passkey-only in production, authenticating against `WEBAUTHN_RP_ID=feeder.tmoneystuff.com` / `WEBAUTHN_ORIGIN=https://feeder.tmoneystuff.com` (`app/auth.rb`, `app/main.rb`'s `WebAuthn.configure` block). The ceremony endpoints (`/api/auth/register/options`, `register/verify`, `login/options`, `login/verify`) already speak plain JSON and already special-case a `native: true` body field to also mint and return a bearer token (`ApiTokensStore.issue!`) alongside the existing cookie-session sign-in — that's exactly how the Phase 1 recovery-code flow (`/api/auth/recovery`) gets iOS a token today. So the backend ceremony logic itself needs **no changes**: what's missing is purely (a) the trust link between the iOS app and the domain (Associated Domains + an AASA file), and (b) the iOS-side native ceremony code that was stubbed out with a Safari-sheet hand-off and recovery-code-only login in Phase 1.

Phase 1's `ios/project.yml` already has `bundleIdPrefix: com.techfeedreader` flagged with a literal `PLACEHOLDER — replace once a real Team ID / bundle id is chosen (Phase 2)` comment, and the deferred design section in the archived `ios-app` design doc (`openspec/changes/archive/2026-09-18-ios-app/design.md`, "Phase 2") already scoped this exact pair of tasks. This design fills in the concrete how.

**Known values** (previously the blocker): production domain is `feeder.tmoneystuff.com`; Apple Developer Team ID is still **pending** — the user is retrieving it from developer.apple.com → Membership. Every reference below uses `<TEAM_ID>` as a placeholder substituted during `tasks.md` execution, not during this design/spec pass.

## Goals / Non-Goals

**Goals:**
- A passkey created via the iOS app (or the web app) works to log into either, because both share one WebAuthn relying party (`feeder.tmoneystuff.com`) once Associated Domains links them.
- Native sign-up (passkey registration) and native login (passkey assertion) via `ASAuthorizationPlatformPublicKeyCredentialProvider`, replacing the Safari-sheet sign-up hand-off as the primary path.
- Recovery-code login keeps working unchanged — still needed for local dev (no AASA over `http://localhost`) and as a fallback (new device before iCloud Keychain sync, lost/unenrolled passkey).

**Non-Goals:**
- No backend WebAuthn ceremony/verification logic changes — `credential.verify(...)` behaves identically regardless of whether the assertion came from a browser or `ASAuthorizationController`, since Associated Domains makes the clientDataJSON origin identical (`https://feeder.tmoneystuff.com`) either way.
- No change to web-app session/cookie behavior.
- No "add a second passkey from the app" management UI beyond what registration naturally gives (that's `/account`'s existing passkey list — Phase 10 shipped list/revoke; *adding* one from the app is this change's registration ceremony, used for sign-up, and reusable later for "add another passkey" if wanted, but that settings-screen entry point is not itself in scope here).
- No change to recovery-code minting/display (Phase 1/10 already handle that).

## Decisions

### 1. AASA file: a new Sinatra route, not a static file
`GET /.well-known/apple-app-site-association` returns:
```json
{
  "webcredentials": { "apps": ["<TEAM_ID>.com.techfeedreader.ios"] }
}
```
Served from `app/main.rb` as a regular route (`content_type :json`, no `.json` extension in the path — Apple's spec requires the extensionless path), added to `Auth::PUBLIC_PATHS` (exact match, like `/health`) rather than `PUBLIC_PREFIXES` since it's a single fixed path. **Why a route over a static file in `public/`:** `<TEAM_ID>` needs to come from an env var (`APPLE_TEAM_ID`), and Sinatra's `:public` static-file serving can't do env substitution — a tiny route is simpler than a build-time templating step for one file. Caddy already reverse-proxies everything to the app container, so no Caddyfile change is needed; Apple's CDN fetches this over HTTPS like any other client.

**Alternative considered**: template the file into the Docker image at build time from the `APPLE_TEAM_ID` build arg. Rejected — adds a build-time env dependency for a value that can just as easily be an app-boot-time `ENV.fetch`, and a route is trivially testable in the existing RSpec suite (a static file templated at image-build time isn't exercised by `bundle exec rspec` at all).

### 2. iOS: Associated Domains entitlement + real Team ID replace the `project.yml` placeholder
`ios/project.yml` gains:
```yaml
options:
  bundleIdPrefix: <TEAM_ID>  # was: com.techfeedreader (placeholder)
targets:
  TechFeedReader:
    entitlements:
      path: TechFeedReader/TechFeedReader.entitlements
      properties:
        com.apple.developer.associated-domains:
          - webcredentials:feeder.tmoneystuff.com
```
XcodeGen generates the entitlements file reference from `project.yml`; the actual `.entitlements` plist is a new small file under `ios/TechFeedReader/`. **Why `bundleIdPrefix` instead of hardcoding the full bundle ID**: `project.yml` already composes `PRODUCT_BUNDLE_IDENTIFIER` from the prefix (see Debug/Release configs — `com.techfeedreader.ios`), so changing just the prefix is the minimal, already-established knob; the bundle ID's `.ios` suffix is unaffected.

### 3. Native ceremonies: `AuthenticationServices`, not a new networking layer
`AuthViewModel` gains `register(username:displayName:)` and `logInWithPasskey()`, both using `ASAuthorizationController` with an `ASAuthorizationPlatformPublicKeyCredentialProvider` request (`createCredentialRegistrationRequest`/`createCredentialAssertionRequest`), delegate callbacks bridged to `async/await` via a small `CheckedContinuation` wrapper (the standard pattern for `ASAuthorizationControllerDelegate`, which is callback-based). The resulting attestation/assertion object's raw bytes are base64url-encoded into the same JSON shape `WebAuthn::Credential.from_create`/`.from_get` already expect (mirroring exactly what the web app's `webauthn-json` JS library sends today) and POSTed to the existing `/api/auth/register/options` → `register/verify` and `login/options` → `login/verify` endpoint pairs with `native: true`, reusing `APIClient`'s existing request plumbing.

**Why reuse the existing endpoints rather than new `/api/v1/auth/*` ones**: the whole point of Associated Domains is that native and web ceremonies are indistinguishable to the server — same relying party, same verification code path. Standing up parallel endpoints would be duplicated logic with no benefit.

**Alternative considered**: a third-party Swift WebAuthn client wrapper library. Rejected — `AuthenticationServices` is the first-party, zero-dependency Apple framework for exactly this, and the existing `webauthn` gem server-side already speaks the standard format; no translation library is needed on either side.

### 4. Sign-up flow: native registration replaces the Safari sheet; recovery codes still shown once
After a successful native registration ceremony, `register/verify`'s response (unchanged shape: `{ok, recovery_codes, username, api_token}`) still carries the one-time recovery codes — the new native sign-up screen displays them exactly as the web `/sign-up` flow's final step does today, since that "show once, never again" behavior is a product decision independent of transport. `SafariView`/`AppConfig.signUpURL` (the Phase 1 hand-off) stop being used for sign-up; `SafariView` itself isn't deleted since nothing else in this change needs it removed (leaving unrelated dead code per the project's surgical-changes convention — flagged here rather than silently deleted).

### 5. Sign-in screen: passkey first, recovery code as a disclosed fallback
`SignInView` leads with a "Sign in with Passkey" button (triggers `logInWithPasskey()` immediately — no username needed, since `ASAuthorizationPlatformPublicKeyCredentialProvider`'s discoverable-credential request lets the platform picker show every passkey, matching `login/options`' existing behavior of not requiring a username either, already built for exactly this "don't make the user type a username" reason). The existing recovery-code field moves behind a "Use a recovery code instead" disclosure, not removed.

## Risks / Trade-offs

- **[Risk] Apple Team ID still unknown at proposal time** → Mitigation: `tasks.md`'s first task is explicitly "obtain and record `APPLE_TEAM_ID`," gating every subsequent task; this proposal/design/specs pass can be fully reviewed and the plan agreed on before that value is needed.
- **[Risk] AASA file must be reachable with no redirects and correct content-type before Apple will trust it; a misconfigured route silently breaks Associated Domains with no iOS-side error message pointing at the cause** → Mitigation: a request spec asserts status 200, `content_type` is `application/json` (no charset-less edge cases), and the exact JSON shape; manual verification step in tasks.md using `curl -I` against the deployed AASA URL plus Apple's own `App Search API` validation tool before relying on it from the app.
- **[Risk] Changing `bundleIdPrefix` changes the app's bundle identifier, which can orphan the existing TestFlight/local-signing identity if the app was ever distributed under the placeholder ID** → Mitigation: this app has only ever run in Simulators under the placeholder so far (no TestFlight/App Store distribution exists yet per STUFF.md #115), so there's no real device/App Store identity to orphan; flagged here so it isn't silently assumed safe if that's changed since.
- **[Risk] `ASAuthorizationControllerDelegate`'s callback-to-async bridging has a well-known pitfall (the continuation can be resumed twice, or never, if the delegate's cancel/error paths aren't all wired) → crashes or hangs** → Mitigation: tasks.md includes an explicit task to test the cancel path (user dismisses the system passkey sheet) in addition to the success/failure paths, not just the happy path.
- **[Trade-off] Recovery-code login remains as a second, permanently-maintained auth path on iOS** rather than being removed now that native passkey works. Accepted because local dev has no alternative (no AASA over `http://localhost`), and it's the only account-recovery path if a user's passkey is unavailable — removing it would regress Phase 1 capability for no benefit.

## Migration Plan

1. Backend: add the AASA route + `PUBLIC_PATHS` entry, `APPLE_TEAM_ID` env var (dev `.env.example` gets a placeholder comment like `WEBAUTHN_RP_ID`'s). Deploy via the normal `make release-patch` pipeline — additive, no migration, no risk to existing routes.
2. Verify the AASA file is live and correct in production (`curl`, Apple's validator) **before** shipping any iOS build that declares the Associated Domains entitlement — an iOS build with the entitlement but no valid AASA file fails Associated Domains silently (falls back to failing the native ceremony with a generic error), so sequencing backend-then-iOS matters.
3. iOS: entitlement + native ceremony code, tested against the now-live production AASA (Associated Domains can't be tested against `localhost`, so this phase's manual verification necessarily targets production, unlike every prior phase's Simulator-against-local-dev loop — call this out explicitly when applying, since it's a departure from the established dev loop).
4. No rollback concern server-side (purely additive route). iOS-side, if native ceremonies prove broken post-review, the old Safari-sheet sign-up + recovery-only login remain intact as a revert target since this change doesn't delete them.

## Open Questions

- Apple Developer Team ID — outstanding, blocks `tasks.md` execution (not the propose/design/specs pass).
- Whether to also surface a "Sign in with Passkey" option on first app launch as the *only* button (hiding recovery code until tapped) vs. showing both with equal visual weight — leaning toward passkey-first per Decision 5, but worth confirming against the user's preference during apply if the UX reads as too hidden.
