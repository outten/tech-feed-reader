## Context

Tech Feed Reader today is a single Sinatra app (`app/main.rb`) serving server-rendered ERB/Turbo views over cookie sessions. Authentication is **passkey-only** (WebAuthn via `app/auth.rb`) — there is no username/password or email to fall back on. There is no general JSON API: the only JSON endpoints are the WebAuthn ceremony routes (`/api/auth/register/options`, `/register/verify`, `/login/options`, `/login/verify`, `/api/auth/recovery`) and an admin API gated by Basic Auth. `SPEC.md` currently documents "Mobile-native app" as a non-goal; this change reverses that.

The iOS app must let a user log in / sign up and see the *same* account data (feeds, subscriptions, articles, read state) as the web app, run locally against the existing dev server (`make run` → `http://localhost:4567`), and live in its own directory so it never touches the Sinatra app's files.

## Goals / Non-Goals

**Goals:**
- Native SwiftUI app for iPhone and iPad (iPad uses the full screen, not an iPhone-compatibility letterbox), buildable in Xcode.
- Login and sign-up on iOS using the same passkey-based accounts as the web app — a passkey created on web works on iOS and vice versa.
- A versioned JSON API (`/api/v1/...`) for feeds, subscriptions, articles, and read-state, additive to the existing HTML routes.
- Local development loop: run the iOS app in the Simulator against `make run`'s local server.
- Everything iOS-specific lives under a new top-level `ios/` directory.

**Non-Goals:**
- Android or any other non-Apple platform.
- Push notifications, background article refresh, or offline sync beyond what the web app already does — can be a later change.
- Any password/email-based login — the app stays passkey-only, matching the web app.
- Changing existing web session/cookie behavior or existing HTML routes.

## Decisions

### 1. Auth: reuse existing WebAuthn ceremonies, add native passkey UI + token issuance
The iOS app calls the **same** `/api/auth/register/*` and `/api/auth/login/*` endpoints already used by the web app (they already speak JSON in/out) — no new ceremony endpoints. On the client, it uses `ASAuthorizationPlatformPublicKeyCredentialProvider` (native platform passkey UI) instead of a browser WebAuthn call.

This requires **Associated Domains** (`webcredentials:<prod-domain>`) so iOS treats the app and the website as the same credential relying party — this is what makes "the same passkey works on web and iOS" true (passkeys sync via iCloud Keychain, scoped to the associated domain). This means:
- The production domain must serve an `apple-app-site-association` file (new Caddy route) declaring the app's Team ID + Bundle ID.
- The iOS app needs the Associated Domains entitlement pointing at that same domain.

On successful login/register verify, `sign_in!` currently sets a cookie session. Additively, when the request carries a new `native=1` flag (or `Accept: application/json` + a custom header), the response **also** includes an opaque bearer token (new `api_tokens` table: `user_id`, `token`, `created_at`, `last_used_at`). Cookie-based behavior for browser clients is unchanged. The iOS app stores this token in the Keychain and sends `Authorization: Bearer <token>` on all `/api/v1/*` calls.
- **Alternative considered**: wrap the existing web login flow in a `WKWebView` inside the app. Rejected — it works but doesn't give native passkey UI/UX and contradicts "native app built with Xcode" intent; kept as a fallback idea if native passkey work proves too costly.

### 2. New `/api/v1` JSON API, sharing logic with existing HTML routes
Add read/write JSON endpoints backed by the same models the HTML routes already use (`feeds`, `user_feed_subscriptions`, `articles`, `read_state`):
- `GET /api/v1/feeds` — subscribed feeds
- `GET /api/v1/articles` — paginated articles (`feed_id`, cursor params)
- `GET /api/v1/articles/:uid` — single article
- `POST /api/v1/subscriptions` — subscribe/unsubscribe
- `POST /api/v1/read_state` — mark read/bookmarked/archived
- `POST /api/v1/session` (or reuse login/verify as above) and `DELETE /api/v1/session` — sign out, deletes the token row

All are token-authenticated (`Authorization: Bearer`), returning 401 like the existing `/api/ticker` pattern. Query logic is extracted into shared helpers rather than duplicated between the ERB routes and the JSON routes.

### 3. `ios/` directory layout
A single Xcode project at `ios/TechFeedReader.xcodeproj` with one app target supporting iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), SwiftUI lifecycle. iPad uses `NavigationSplitView` (sidebar of feeds + article list/detail) so it fills the full screen natively rather than presenting a scaled iPhone layout. No files outside `ios/` are touched by the app itself; the only cross-cutting pieces are the new backend API and the AASA file.

### 4. Local dev story
- Simulator: builds point at `http://localhost:4567` (a Debug-only base URL), works directly since Simulator shares the Mac's network stack.
- Physical device: base URL becomes the dev Mac's LAN IP; requires an `NSAppTransportSecurity` exception scoped to Debug builds only (plain HTTP, dev-only) since ATS blocks non-HTTPS by default.
- Passkey ceremony against a non-production RP: Apple supports "Associated Domains Development Mode" (device/simulator setting) to test passkey flows without hosting a real AASA file. As a simpler fallback, the existing recovery-code login (`/api/auth/recovery`) works over the JSON API unchanged and is the practical way to log in locally without wrestling with associated-domains dev mode.

## Risks / Trade-offs

- **Associated Domains complexity for local testing** → mitigated by recovery-code fallback for day-to-day local dev; full passkey ceremony verified against a staging/production-like domain before release.
- **New API surface could drift from existing HTML routes' business logic** → mitigated by extracting shared helpers instead of duplicating query logic (Decision 2).
- **Long-lived bearer tokens are a new attack surface** → mitigated by a sign-out endpoint that deletes the token row, and Keychain-only storage on device (never UserDefaults/plist).
- **App Store review** — passkey/WebAuthn login is not the "third-party social login" Apple's Sign-in-with-Apple requirement (guideline 4.8) targets, but this should be verified before submission (see Open Questions).

## Migration Plan

Additive only — no existing data or behavior changes.
1. Add `api_tokens` table via a new migration in `db/migrations-postgres/`.
2. Ship `/api/v1/*` endpoints + native-token issuance on the existing web deploy pipeline (`make release-patch`), unflagged — no impact on browser clients.
3. Serve the `apple-app-site-association` file from production (Caddy).
4. Develop the iOS app against local/staging, then TestFlight, then App Store — independent of the web release cadence.
Rollback: the new endpoints and table can be removed/ignored without affecting the web app; no reverse migration needed for a pre-release rollback.

## Open Questions

- Minimum iOS version to target (assumed iOS 17+ for the platform-passkey APIs used — confirm before setting the Xcode deployment target).
- Production domain to use for Associated Domains / AASA (needed to configure entitlements and Caddy).
- Is push notification support wanted in a later phase? (Assumed out of scope for this change.)
- Who holds the Apple Developer account / Team ID for signing and eventual App Store submission?
