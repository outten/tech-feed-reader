## 1. Prerequisite

- [ ] 1.1 Obtain and record the Apple Developer Team ID from the user (blocks every task below — `apple-app-site-association`'s `apps` entry and `ios/project.yml`'s `bundleIdPrefix` both need it).

## 2. Backend: apple-app-site-association

- [ ] 2.1 Add `APPLE_TEAM_ID` to `.env.example` (placeholder comment, matching `WEBAUTHN_RP_ID`'s style) and the real value to the production `.env`.
- [ ] 2.2 Add `GET /.well-known/apple-app-site-association` to `app/main.rb`, returning `{"webcredentials": {"apps": ["<APPLE_TEAM_ID>.com.techfeedreader.ios"]}}` as `application/json`.
- [ ] 2.3 Add `/.well-known/apple-app-site-association` to `Auth::PUBLIC_PATHS` in `app/auth.rb`.
- [ ] 2.4 Request spec: 200, correct content-type, correct JSON shape, no auth required.
- [ ] 2.5 Run the full RSpec suite (`make test` / file:line targeted, never `-e`); restart the dev server before any manual check.
- [ ] 2.6 Deploy via `make release-patch` (ask for explicit go-ahead first, per the standing deploy gate) and verify the live route with `curl -i https://feeder.tmoneystuff.com/.well-known/apple-app-site-association` plus Apple's App Search API validation tool, **before** starting section 3 — an iOS build with the entitlement but a broken/unreachable AASA file fails Associated Domains silently.

## 3. iOS: Associated Domains entitlement

- [ ] 3.1 Replace `bundleIdPrefix: com.techfeedreader` with the real Team ID in `ios/project.yml`.
- [ ] 3.2 Add a `TechFeedReader.entitlements` file and wire `com.apple.developer.associated-domains: [webcredentials:feeder.tmoneystuff.com]` into the target's `entitlements` in `ios/project.yml`.
- [ ] 3.3 `xcodegen generate`; confirm the regenerated project builds (Debug, both Simulators) with the entitlement present (Signing & Capabilities tab, or `codesign -d --entitlements :- <built .app>`).

## 4. iOS: native passkey registration (sign-up)

- [ ] 4.1 Add an `ASAuthorizationControllerDelegate`-to-async bridge (a small reusable helper — needed by both registration and login below).
- [ ] 4.2 `AuthViewModel.register(username:displayName:)`: call `POST /api/auth/register/options`, build an `ASAuthorizationPlatformPublicKeyCredentialProvider` registration request from the returned challenge, run it, base64url-encode the resulting attestation into the shape `register/verify` expects, POST with `native: true`.
- [ ] 4.3 New sign-up view: username/display-name entry → native passkey sheet → on success, show the returned one-time recovery codes (same "shown once" treatment as the web flow) → sign in.
- [ ] 4.4 Remove the `SFSafariViewController` sign-up hand-off from `SignInView`'s "New here? Sign up" action, pointing it at the new native flow instead. Leave `SafariView.swift`/`AppConfig.signUpURL` in place (unrelated dead code is out of scope to delete — flag if confirmed unused elsewhere).
- [ ] 4.5 Test the cancel path explicitly: dismiss the system passkey creation sheet mid-ceremony and confirm the app returns to a retryable state, not a crash or hang.

## 5. iOS: native passkey login

- [ ] 5.1 `AuthViewModel.logInWithPasskey()`: call `POST /api/auth/login/options`, build a discoverable-credential `ASAuthorizationPlatformPublicKeyCredentialProvider` assertion request (no username), run it, base64url-encode the assertion into the shape `login/verify` expects, POST with `native: true`.
- [ ] 5.2 `SignInView`: add a "Sign in with Passkey" button as the primary action; move the existing recovery-code field behind a "Use a recovery code instead" disclosure (kept, not removed).
- [ ] 5.3 Test the cancel path: dismiss the system passkey picker without selecting a credential, confirm a clean return to the sign-in screen.

## 6. Verification

- [ ] 6.1 Manual end-to-end check against production (Associated Domains can't be tested against `localhost`): sign up natively on iOS, confirm the account + passkey appear correctly (e.g. via `/account/passkeys` on web or the app's own Account screen).
- [ ] 6.2 Manual check: log in on iOS with a passkey that was originally created via the **web** app (proves the shared-relying-party goal — the actual point of this change).
- [ ] 6.3 Confirm recovery-code login still works unchanged (regression check for the fallback path).
- [ ] 6.4 Confirm local dev (`http://localhost:4567`) is unaffected — recovery-code login remains the dev-loop path, matching Phase 1.
- [ ] 6.5 Install + screenshot both target Simulators (iPhone 17, iPad Pro 11" M5) for a visual sanity check of the new sign-up/sign-in screens; pause for explicit manual-verification approval before committing, per the standing UI-change rule.

## 7. Wrap-up

- [ ] 7.1 Update `STUFF.md` #115's native-iOS-app entry: Phase 2 shipped, remove the "deferred" language.
- [ ] 7.2 `openspec archive` this change once all tasks are complete and verified.
