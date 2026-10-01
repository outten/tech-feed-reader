## Why

The iOS app has been passkey-login-shaped since Phase 1 but can't actually do native passkey ceremonies: Associated Domains (which makes iOS treat the app and `feeder.tmoneystuff.com` as the same WebAuthn relying party) was deferred for lack of a production domain and Apple Developer Team ID. Both are now available. Today, sign-up hands off to an in-app Safari sheet pointed at the web `/sign-up` flow, and login only works via a one-time recovery code — a real passkey never gets created or used natively, and a user who already has a passkey from the web can't use it to sign into the app. This change closes that gap: native `ASAuthorizationPlatformPublicKeyCredentialProvider` registration and login, sharing the same iCloud-Keychain-synced passkey as the web app.

## What Changes

- Add a `GET /.well-known/apple-app-site-association` route (Sinatra, exempted from the auth before-filter like the other `/api/auth/*` ceremony routes) declaring the app's Team ID + bundle ID for the `webcredentials` service — required before iOS will associate the app with the domain at all.
- Add the Associated Domains entitlement (`webcredentials:feeder.tmoneystuff.com`) to the iOS app target, replacing the `com.techfeedreader` bundle-id-prefix placeholder in `ios/project.yml` with the real Team ID.
- Replace the iOS sign-up flow's `SFSafariViewController` hand-off with a native registration ceremony: call the existing `POST /api/auth/register/options` / `register/verify` endpoints (already native-token-aware via `native: true`), using `ASAuthorizationPlatformPublicKeyCredentialProvider` for the on-device passkey creation UI instead of the browser.
- Add native login via passkey as the primary iOS sign-in path (`ASAuthorizationController` with a platform passkey request), calling the existing `POST /api/auth/login/options` / `login/verify` endpoints. Recovery-code login is kept as a fallback option on the same screen, not removed — it remains the only path for a device that hasn't synced the passkey via iCloud Keychain yet, and the practical way to log in against a local dev server (associated domains need a real HTTPS domain; `localhost` can't serve an AASA file).
- **No web-facing behavior changes.** `app/auth.rb`'s WebAuthn config, the ceremony endpoints' verification logic, and cookie-session behavior for browser clients are all unchanged — this only adds a new, auth-exempt static-response route and changes what the iOS client calls.

## Capabilities

### New Capabilities
- `mobile-native-passkey-auth`: native passkey registration and login on iOS via Associated Domains + `ASAuthorizationPlatformPublicKeyCredentialProvider`, sharing credentials with the web app's existing WebAuthn relying party.

### Modified Capabilities
- `mobile-account`: sign-up and login no longer require the Safari-sheet hand-off or recovery-code-only login as the primary path — native passkey ceremonies become the default, with recovery-code login retained as an explicit fallback. (Check `openspec/specs/mobile-account/spec.md` during design/specs for the exact requirement text this touches.)

## Impact

- **Backend**: `app/main.rb` (new AASA route + its auth-exemption), `app/auth.rb` (add the new path to `PUBLIC_PATHS`/prefixes). No changes to `WebauthnCredentialsStore`, `RecoveryCodesStore`, `ApiTokensStore`, or the ceremony verification logic itself.
- **iOS**: `ios/project.yml` (Associated Domains entitlement, real Team ID), a new Associated Domains capability in the generated Xcode project, `ios/TechFeedReader/Auth/AuthViewModel.swift` + `SignInView.swift` (native ceremony calls replacing/supplementing the Safari-sheet + recovery-only flow), a new sign-up view, and `APIClient.swift` (wiring the existing `/api/auth/register/*` and `/login/*` JSON endpoints, already used by the web app, into native calls).
- **Infrastructure**: none beyond the new route — Caddy already reverse-proxies everything to the app, so no Caddyfile change is needed to serve the AASA file.
- **Local dev**: unaffected. Associated Domains requires a real HTTPS production domain; local development against `http://localhost:4567` keeps using recovery-code login, exactly as Phase 1 set up.
