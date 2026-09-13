**Scope note (added during apply):** Associated Domains setup was deferred (see group 3 and design.md "Phase scoping") pending production domain + Apple Team ID. Groups 3 and part of 5 are Phase 2. This pass's iOS auth uses recovery-code login + browser-handoff sign-up instead of native passkeys — `specs/ios-app/spec.md`'s sign-up/login requirements are met via that mechanism for now, with native passkey UI to follow in Phase 2.

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

## 3. Backend: associated domains — DEFERRED to Phase 2 (see design.md)

User doesn't have production domain / Apple Team ID handy yet. Revisit when available.

- [ ] 3.1 Confirm production domain and Apple Team ID / Bundle ID to use
- [ ] 3.2 Add Caddy route serving `apple-app-site-association` with the `webcredentials` entry
- [ ] 3.3 Verify the AASA file is reachable at `/.well-known/apple-app-site-association` and `/apple-app-site-association` in production

## 4. iOS project scaffolding

- [x] 4.1 Create `ios/TechFeedReader.xcodeproj` (SwiftUI app, iPhone + iPad, `TARGETED_DEVICE_FAMILY = "1,2"`) — generated via XcodeGen from `ios/project.yml` (not hand-committed pbxproj; regenerate with `xcodegen generate`, see `ios/README.md`). Builds succeed for both `iPhone 17` and `iPad Pro 11-inch (M5)` simulator destinations.
- [ ] 4.2 ~~Add Associated Domains entitlement~~ — DEFERRED to Phase 2 (needs prod domain + Team ID)
- [x] 4.3 Set up Debug/Release configs with a switchable API base URL (localhost for Debug/Simulator, production for Release) — `xcconfig/Debug.xcconfig` / `Release.xcconfig`
- [x] 4.4 Add an `NSAppTransportSecurity` exception scoped to Debug builds for local HTTP testing on a physical device — `NSAllowsLocalNetworking` in `Info-Debug.plist` only (covers loopback, `.local`, and literal LAN IPs — Release's Info.plist omits it)

## 5. iOS: auth (Phase 1 scope — recovery-code login + browser-handoff sign-up)

- [x] 5.1 Sign-up: open the production `/sign-up` page in an in-app `SFSafariViewController`; no native code changes to the web flow. User completes passkey sign-up there (seeing their recovery codes), dismisses the sheet, and logs in natively (5.3). — `Auth/SafariSignUpView.swift`
- [ ] 5.2 ~~Native login via `ASAuthorizationPlatformPublicKeyCredentialProvider`~~ — DEFERRED to Phase 2 (needs Associated Domains)
- [x] 5.3 Implement recovery-code login (native form, calls `/api/auth/recovery` with `native: true`) — the primary login path for Phase 1 — `Auth/SignInView.swift` + `Auth/AuthViewModel.swift`
- [x] 5.4 Store the issued bearer token in the Keychain; attach `Authorization: Bearer` to all `/api/v1/*` requests — `Networking/KeychainStore.swift` + `Networking/APIClient.swift`
- [x] 5.5 Implement sign-out (calls `DELETE /api/v1/session`, clears the Keychain entry) — `AuthViewModel.signOut()`, wired to the "Sign Out" toolbar button in `Views/MainView.swift`

## 6. iOS: feed/article UI

- [x] 6.1 Feed list view (iPhone: navigation stack; iPad: `NavigationSplitView` sidebar) — one `NavigationSplitView` in `Views/MainView.swift` adapts to both automatically
- [x] 6.2 Article list view for a selected feed, paginated — `Views/ArticleListView.swift`
- [x] 6.3 Article detail view (rendered content) — `Views/ArticleDetailView.swift` + `Views/ArticleContentView.swift` (WKWebView renders the server-scrubbed content_html)
- [x] 6.4 Mark read/bookmark/archive actions wired to `POST /api/v1/read_state` — `ArticleDetailView` (read-on-open, bookmark/archive toolbar buttons)
- [x] 6.5 Subscribe/unsubscribe UI wired to `POST /api/v1/subscriptions` — `Views/FeedListView.swift` (add-feed alert, swipe-to-delete)

## 7. Local dev + verification

- [x] 7.1 Document the local-dev flow (run `make run`/`make serve`, point iOS Simulator at `http://localhost:4567`, log in via recovery code) in `ios/README.md`
- [~] 7.2 Verified what can be verified non-interactively: the app builds, installs, and launches in Simulator; the sign-in screen renders correctly (screenshot-checked); the full `/api/v1/*` flow (sign-up → subscribe → list feeds → list/read articles) was driven for real against the running dev server via curl/a WebAuthn-FakeClient script and returned correct data. **Full tap-through (typing a recovery code, browsing feeds/articles on-screen) needs a human at the Simulator** — a real test account already exists for this (see chat for the recovery code) with a subscribed feed that has articles.
- [~] 7.3 iPad build installs, launches, and renders full-screen edge-to-edge (screenshot-confirmed on iPad Pro 11-inch Simulator — no iPhone-sized letterboxing). Tapping through the actual login/feeds/article flow on-screen is the remaining human step — same caveat as 7.2.

## 8. Docs

- [x] 8.1 Update `SPEC.md` to remove/revise the "Mobile-native app — responsive web only" non-goal — struck both non-goal mentions, added a "Native iOS app" subsection under Scope evolution
- [x] 8.2 Add a `STUFF.md` entry for this change per existing changelog convention — #115, left `[ ]` (in progress, not shipped) per the Phase 1/2 split

## 9. Phase 3 — Reading experience parity (backend)

- [x] 9.1 Add `state` query param (`unread`/`bookmarked`/`archived`/`all`) to `GET /api/v1/articles`, reusing `ArticlesStore.recent`/`.for_feed`'s existing `state:` filter
- [x] 9.2 Add `GET /api/v1/search` (wraps `ArticlesStore.search`)
- [x] 9.3 Add `GET /api/v1/tags` (wraps `TagsStore.all`) and `tag_id` filter on `GET /api/v1/articles` (wraps `ArticlesStore.for_tag`)
- [x] 9.4 Add `GET /api/v1/topics` (wraps `TopicClusters.recent`) and `GET /api/v1/topics/:term` (wraps `ArticlesStore.for_topic`)
- [x] 9.5 Request specs covering the scenarios in `specs/mobile-reading-parity/spec.md` — 8 new examples in `spec/mobile_api_spec.rb`, full suite 1767/0

## 10. Phase 3 — Reading experience parity (iOS)

- [x] 10.1 Bookmarks screen — generalized the feed article-list into `ArticlesListView` (title + async fetch closure) so Bookmarks reuses it with `state: "bookmarked"` instead of a separate screen
- [x] 10.2 Search screen — `SearchView.swift` (`.searchable`-backed field + results list)
- [x] 10.3 Tags screen — `TagsListView.swift` (list tags → `ArticlesListView` filtered by `tag_id`)
- [x] 10.4 Topics screen — `TopicsListView.swift` (list topics → `ArticlesListView` filtered by topic term)
- [x] 10.5 Add navigation entry points for Bookmarks/Search/Tags/Topics — `SidebarView.swift`'s new "Library" section, above the existing "Feeds" section; `MainView.swift`'s detail switches on the new `SidebarItem` enum
- [x] 10.6 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders Library + Feeds sections correctly (screenshot-confirmed with real subscribed feeds). Tapping through each of the four new screens is a human-at-the-Simulator step, same as prior manual-verification tasks.

## 11. Phase 4a — Feed discovery & management (backend)

- [x] 11.1 Add `GET /api/v1/feed_catalog` (wraps `FeedCatalog.by_category` + `FeedCatalog::CATEGORIES` for labels)
- [x] 11.2 Add `GET /api/v1/feed_catalog/recommended` (wraps `FeedCatalog.recommend_for`)
- [x] 11.3 Add `GET /api/v1/feeds/popular?type=` (wraps `FeedsStore.popular_by_type`)
- [x] 11.4 Add `GET /api/v1/mute_rules`, `POST /api/v1/mute_rules`, `DELETE /api/v1/mute_rules` (wraps `MuteRulesStore`)
- [x] 11.5 Request specs covering the scenarios in `specs/mobile-feed-discovery/spec.md` — 6 new examples in `spec/mobile_api_spec.rb`, full suite 1773/0

## 12. Phase 4a — Feed discovery & management (iOS)

- [ ] 12.1 Catalog browse screen (categories → feeds → tap to subscribe)
- [ ] 12.2 "Recommended for you" section on the catalog screen
- [ ] 12.3 Popular-by-type charts (small section, e.g. on the catalog screen or Feeds sidebar)
- [ ] 12.4 Mute rules screen (list + add + remove, by kind)
- [ ] 12.5 Add navigation entry point(s) for catalog browse + mute rules
- [ ] 12.6 Verify in the Simulator against the local dev server

**Phase 4b (deferred, not yet tasked)**: AI feed recommender, OPML import/export — see design.md.
