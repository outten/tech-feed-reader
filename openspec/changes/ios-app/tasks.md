## 1. Backend: token auth for native clients

- [x] 1.1 Add `api_tokens` migration (`user_id`, `token`, `created_at`, `last_used_at`) under `db/migrations-postgres/`
- [x] 1.2 Add token generation/lookup helpers alongside `app/auth.rb` (does not touch existing cookie session logic)
- [x] 1.3 Extend `/api/auth/login/verify` and `/api/auth/register/verify` to include a bearer token in the JSON response when the request signals a native client, leaving browser/cookie behavior unchanged
- [x] 1.4 Add `DELETE /api/v1/session` to revoke (delete) the presented token
- [x] 1.5 Add a bearer-token auth check (helper/before-filter) for all `/api/v1/*` routes, returning 401 when missing/invalid

## 2. Backend: mobile JSON API

- [x] 2.1 Extract shared feed/article/read-state query logic out of the existing HTML routes into helpers usable by both HTML and JSON routes — `ArticlesStore`/`FeedsStore`/`ReadStateStore` were already plain shared modules, so the new `/api/v1/*` routes call them directly; no extraction needed
- [x] 2.2 Add `GET /api/v1/feeds`
- [x] 2.3 Add `GET /api/v1/articles` (feed_id filter; page/offset pagination — matches the existing `/articles` convention rather than introducing a new cursor scheme)
- [x] 2.4 Add `GET /api/v1/articles/:uid`
- [x] 2.5 Add `POST /api/v1/subscriptions` + `DELETE /api/v1/subscriptions/:id` (subscribe/unsubscribe — mirrors the existing `/api/feeds` + `DELETE /api/feeds/:id` pair)
- [x] 2.6 Add `POST /api/v1/read_state` (read/bookmarked/archived)
- [x] 2.7 Write request specs covering the scenarios in `specs/mobile-api/spec.md` — `spec/mobile_api_spec.rb`, 13 examples, full suite (1759 examples) still green

## 3. Backend: associated domains

- [ ] 3.1 Confirm production domain and Apple Team ID / Bundle ID to use
- [ ] 3.2 Add Caddy route serving `apple-app-site-association` with the `webcredentials` entry
- [ ] 3.3 Verify the AASA file is reachable at `/.well-known/apple-app-site-association` and `/apple-app-site-association` in production

## 4. iOS project scaffolding

- [ ] 4.1 Create `ios/TechFeedReader.xcodeproj` (SwiftUI app, iPhone + iPad, `TARGETED_DEVICE_FAMILY = "1,2"`)
- [ ] 4.2 Add Associated Domains entitlement pointing at the production domain
- [ ] 4.3 Set up Debug/Release configs with a switchable API base URL (localhost for Debug/Simulator, production for Release)
- [ ] 4.4 Add an `NSAppTransportSecurity` exception scoped to Debug builds for local HTTP testing on a physical device

## 5. iOS: auth

- [ ] 5.1 Implement sign-up flow using `ASAuthorizationPlatformPublicKeyCredentialProvider` against `/api/auth/register/options` + `/register/verify`
- [ ] 5.2 Implement login flow against `/api/auth/login/options` + `/login/verify`
- [ ] 5.3 Implement recovery-code login (mirrors `/api/auth/recovery`) as the local-dev-friendly fallback
- [ ] 5.4 Store the issued bearer token in the Keychain; attach `Authorization: Bearer` to all `/api/v1/*` requests
- [ ] 5.5 Implement sign-out (calls `DELETE /api/v1/session`, clears the Keychain entry)

## 6. iOS: feed/article UI

- [ ] 6.1 Feed list view (iPhone: navigation stack; iPad: `NavigationSplitView` sidebar)
- [ ] 6.2 Article list view for a selected feed, paginated
- [ ] 6.3 Article detail view (rendered content)
- [ ] 6.4 Mark read/bookmark/archive actions wired to `POST /api/v1/read_state`
- [ ] 6.5 Subscribe/unsubscribe UI wired to `POST /api/v1/subscriptions`

## 7. Local dev + verification

- [ ] 7.1 Document the local-dev flow (run `make run`/`make serve`, point iOS Simulator at `http://localhost:4567`, log in via recovery code) in `ios/README.md`
- [ ] 7.2 Manually verify sign-up, login, feed list, article read, and sign-out end-to-end in the Simulator against the local server
- [ ] 7.3 Manually verify the same flows on a physical iPad in full-screen (not scaled iPhone layout)

## 8. Docs

- [ ] 8.1 Update `SPEC.md` to remove/revise the "Mobile-native app — responsive web only" non-goal
- [ ] 8.2 Add a `STUFF.md` entry for this change per existing changelog convention
