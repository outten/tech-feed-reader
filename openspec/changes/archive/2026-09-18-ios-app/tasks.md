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

- [x] 12.1 Catalog browse screen — `CatalogView.swift` (categories → feeds → tap to subscribe, checkmark for already-subscribed)
- [x] 12.2 "Recommended for you" section on the catalog screen
- [x] 12.3 Popular-by-type charts — segmented-control type picker within `CatalogView` rather than a 5th near-duplicate screen
- [x] 12.4 Mute rules screen — `MuteRulesView.swift` (list + add via sheet + swipe-to-remove, by kind)
- [x] 12.5 Add navigation entry points for catalog browse + mute rules — `SidebarView.swift`'s new "Manage" section
- [x] 12.6 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders the new "Manage" section correctly (screenshot-confirmed)

**Phase 4b (deferred, not yet tasked)**: AI feed recommender, OPML import/export — see design.md.

## 13. Phase 5 — Podcasts & YouTube (backend)

- [x] 13.1 Add `GET /api/v1/podcasts` (wraps `ArticlesStore.podcast_feeds`)
- [x] 13.2 Add `GET /api/v1/youtube/channels` (wraps `ArticlesStore.youtube_channels`)
- [x] 13.3 Request specs covering the scenarios in `specs/mobile-podcasts-youtube/spec.md` — 2 new examples in `spec/mobile_api_spec.rb`, full suite 1775/0

## 14. Phase 5 — Podcasts & YouTube (iOS)

- [x] 14.1 Add `audioUrl`/`audioMimeType`/`audioDurationSeconds` to the `Article` model (backend already returns them; only the client-side model needed updating)
- [x] 14.2 Podcasts screen — `PodcastsView.swift` (feed list → episode list, reusing `ArticlesListView`)
- [x] 14.3 Shared `AudioPlayerViewModel` (native `AVPlayer`) — held at `TechFeedReaderApp`/`RootView`, above `MainView`'s `NavigationSplitView`, + `MiniPlayerView` bar
- [x] 14.4 Wire episode playback (play/pause button in article detail toolbar + mini-player) to the shared player
- [x] 14.5 Background audio playback capability (`UIBackgroundModes: [audio]` in both Info.plist fragments) so playback survives backgrounding
- [x] 14.6 YouTube channels screen — `YouTubeChannelsView.swift` (channel list → video list, reusing `ArticlesListView`)
- [x] 14.7 YouTube embed player — `YouTubePlayerView.swift` + `Article+YouTube.swift` (client-side video-ID extraction mirroring `youtube_video_id`/`youtube_embed_url`), shown above the description instead of the plain content renderer for YouTube articles
- [x] 14.8 Add navigation entry points for Podcasts + YouTube — `SidebarView.swift`'s new "Browse" section
- [x] 14.9 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders the new "Browse" section correctly (screenshot-confirmed)
- [x] 14.10 **UX gap fix (2026-09-16)**: the Podcasts episode lists (and every other article list — `ArticleRow` is shared) had no visible play affordance at all — only a small icon in the article-detail toolbar, reachable after navigating in. `ArticleRow` now shows the episode duration and an inline ▶/⏸ button (wired to the shared `AudioPlayerViewModel`, `.buttonStyle(.borderless)` so it plays without also triggering the row's navigation) for any article with an audio enclosure — matches the web app's per-row "▶ Listen" affordance, but plays directly instead of requiring a second tap. Screenshot-confirmed on iPad (Home's "Continue Listening" row, which reuses `ArticleRow`, now shows the play button).
## 15. Phase 6a — Sports (backend)

- [x] 15.1 Add `GET /api/v1/sports`, `GET /api/v1/sports/:sport_slug/leagues`, `GET /api/v1/sports/:sport_slug/:league_slug/teams` (catalog browse, wraps `SportsCatalog`, with the api-sports DB-teams fallback the web `/sports/manage/:sport/:league` route uses)
- [x] 15.2 Add `POST`/`DELETE /api/v1/sports/teams/follow`, `/leagues/follow`, `/players/follow` (wraps `SportsFollowsStore` + `ensure_catalog_*_in_db` helpers, mirroring the web follow routes exactly — including the `SportsTeamFetchWorker` enqueue on team follow)
- [x] 15.3 Add `GET /api/v1/sports/teams/:slug`, `/leagues/:slug`, `/players/:slug` (detail — DB-backed with catalog fallback for teams not yet synced, per the design.md simplification). Note: team detail's `standings` is a single object-or-null (`SportsStandingsStore.for_team`), league detail's `standings` is an array (`.for_league`) — different shapes by design, matches the underlying store methods.
- [x] 15.4 Add `GET /api/v1/sports/overview` (followed teams/leagues/players + live matches)
- [x] 15.5 Request specs covering the scenarios in `specs/mobile-sports/spec.md` — 13 new examples in `spec/mobile_api_spec.rb`, full suite 1788/0

## 16. Phase 6a — Sports (iOS)

- [x] 16.1 Sports models — `Sports.swift` (Sport, SportsLeague, SportsTeam, SportsMatch, SportsStanding, SportsPlayer + the three detail/overview response wrappers)
- [x] 16.2 Catalog browse screens — `SportsBrowseView.swift` (sport list → league list); team-follow toggle lives inline in league detail rather than a separate team-list screen (see 16.3)
- [x] 16.3 Team / League / Player detail screens — `SportsTeamDetailView.swift`, `SportsLeagueDetailView.swift` (merges standings/matches AND the league's teams-with-follow-toggle into one screen rather than a separate team-browse screen), `SportsPlayerDetailView.swift`
- [x] 16.4 Sports overview screen — `SportsHomeView.swift` (followed teams/leagues/players + live matches)
- [x] 16.5 Add a "Sports" navigation entry point — `SidebarView.swift`'s "Browse" section
- [x] 16.6 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders "Sports" in the Browse section correctly (screenshot-confirmed)

**Phase 6b (deferred, not yet tasked)**: tennis ATP/WTA rankings, Wikipedia league summaries, calendar/.ics surfacing — see design.md.

## 17. Phase 7 — Stocks (backend)

- [x] 17.1 Add `GET /api/v1/stocks/search` (wraps `StockQuoteProvider.search`)
- [x] 17.2 Add `GET /api/v1/stocks/:symbol` (quote + follow state, refreshing via `StockQuoteProvider.fetch_and_cache` if stale) and `GET /api/v1/stocks/:symbol/news`
- [x] 17.3 Add `POST`/`DELETE /api/v1/stocks/follow` (mirrors the web route's news-feed subscribe + eager-fetch behavior, not just the follow row)
- [x] 17.4 Add `GET /api/v1/stocks/ticker` and `GET /api/v1/stocks/sparklines` — defined *before* the `/:symbol` wildcard route (Sinatra matches route definitions in order; the wildcard would otherwise swallow them)
- [x] 17.5 Request specs covering the scenarios in `specs/mobile-stocks/spec.md` — 8 new examples in `spec/mobile_api_spec.rb`, full suite 1796/0

## 18. Phase 7 — Stocks (iOS)

- [x] 18.1 Stocks models — `StockQuote.swift` (StockQuote, StockDetail, StockSearchResult, TickerEntry)
- [x] 18.2 Search screen + symbol detail — `StockSearchView.swift`, `StockDetailView.swift` (quote, follow toggle, news reusing `ArticleRow`)
- [x] 18.3 Ticker view — `StocksHomeView.swift` (followed symbols + major indices)
- [x] 18.4 Add a "Stocks" navigation entry point — `SidebarView.swift`'s "Browse" section
- [x] 18.5 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders "Stocks" in the Browse section correctly (screenshot-confirmed)
- [x] 18.6 **Bug fix (2026-09-16)**: the Stocks tab showed nothing against real (non-test) data. Root cause: `stock_quotes`' `NUMERIC(12,4)` columns come back from `pg` as `BigDecimal`, which has no custom `#to_json` and falls back to `#to_s` — rendering scientific-notation strings like `"0.15e3"` instead of a JSON number. iOS's `Codable` expects a `Double` for `price`/`change`/etc. and silently failed to decode the whole response. Fixed with a `numeric_quote_fields` helper (casts to `Float` before serializing) applied in both `GET /api/v1/stocks/ticker` and `GET /api/v1/stocks/:symbol` — the only two DB-column-backed numeric JSON routes (`stock_quotes` is the only table in the schema with `NUMERIC`/`DECIMAL` columns, so no other route is affected). 2 new regression specs assert `price` decodes as `Numeric`, not a string. Verified live against `ios-tester`'s real Finnhub-fetched data.
- [x] 18.7 **Feature (2026-09-16, requested by user)**: a symbol detail page had no historical price chart at all — this doesn't exist on the web app either (it only has intraday sparklines for the major-index cards on `/stocks`), so this is new functionality, not a parity gap. Added `StockQuoteProvider.history(symbol, days:)` (same free Yahoo Finance chart endpoint `#sparkline` already uses, but keyed by an exact `period1`/`period2` window instead of a preset `range` bucket, so an arbitrary day count works, daily granularity) and `GET /api/v1/stocks/:symbol/history?days=7|30|60|90` (unsupported values clamp to 30). iOS: `StockDetailView` gains a segmented 7D/30D/60D/90D picker and a native Swift `Charts` line+area chart (first-party framework, no new dependency). 2 new backend specs; verified live against Yahoo Finance for all four ranges (e.g. AAPL 90D returned 62 trading-day points). Build succeeded on iPhone 17 + iPad Pro 11" (M5); full interactive verification (tapping into a symbol, switching ranges) needs a human at the Simulator per the established limitation.

## 19. Phase 8a — Misc content (backend)

- [x] 19.1 Add `topic` query param to `GET /api/v1/articles` (wraps `ArticlesStore.recent`'s existing `topic:` kwarg)
- [x] 19.2 Add `GET /api/v1/radio/stations` (wraps `RadioStore.stations_by_group` + `.followed_stations`) and `POST`/`DELETE /api/v1/radio/follow` (wraps `RadioStore.follow!`/`.unfollow!`)
- [x] 19.3 Request specs covering the scenarios in `specs/mobile-misc-content/spec.md` — 4 new examples in `spec/mobile_api_spec.rb`, full suite 1800/0

## 20. Phase 8a — Misc content (iOS)

- [x] 20.1 Comics / NPR / PBS screens — three thin `ArticlesListView(topic:)` call sites in `MainView.swift`, not three new view files
- [x] 20.2 Radio station catalog screen — `RadioStationsView.swift` (grouped list, follow toggle, tap to play)
- [x] 20.3 Generalize `AudioPlayerViewModel`/`MiniPlayerView` to play a plain stream URL + title — introduced `PlayableItem` (article-or-station), `currentArticle` → `currentItem`; `MiniPlayerView` shows an indeterminate indicator instead of a stuck-at-0% bar when duration is unknown (radio)
- [x] 20.4 Add navigation entry points for Comics, NPR, PBS, Radio — `SidebarView.swift`'s "Browse" section
- [x] 20.5 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders all four new entries correctly (screenshot-confirmed)

**Phase 8b (deferred, not yet tasked)**: Sudoku/Trivia games, radio AI recommendations — see design.md.

## 21. Phase 9 — AI features (backend)

- [x] 21.1 Add `GET /api/v1/triage`, `GET /api/v1/triage/:id` (each must-read/optional/skip entry resolved to its full article, not a separate uid→article map), `POST /api/v1/triage` (gated by `LlmGuard`, HTTP 429 on denial)
- [x] 21.2 Add `GET /api/v1/digests`, `GET /api/v1/digests/:id`, `POST /api/v1/digests`, `POST /api/v1/digests/:id/summarize` (gated by `LlmGuard`, cached — a second call doesn't re-spend tokens)
- [x] 21.3 Request specs covering the scenarios in `specs/mobile-ai-features/spec.md` — 10 new examples in `spec/mobile_api_spec.rb`, full suite 1810/0

## 22. Phase 9 — AI features (iOS)

- [x] 22.1 Triage models + screen — `Triage.swift`, `TriageHomeView.swift` (recent runs, trigger button), `TriageDetailView.swift` (must-read/optional/skip sections)
- [x] 22.2 Digests models + screen — `Digest.swift`, `DigestsHomeView.swift` (recent list, generate button), `DigestDetailView.swift` (summarize button, cached summary display)
- [x] 22.3 Add navigation entry points for Triage + Digests — `SidebarView.swift`'s new "AI" section
- [x] 22.4 Verified in the Simulator: builds clean on iPhone + iPad, sidebar renders correctly against the real dev server (screenshot-confirmed). The sidebar has grown long enough (6 sections, ~20 items) to need scrolling on iPad — noted to the user as a UX consideration for a later pass, not a defect.

## 23. Phase 10 — Account management (backend)

- [x] 23.1 Add `GET /api/v1/account` (username, display name, passkey count, recovery-code count, calendar `.ics` URL — resolves the Phase 6b calendar-surfacing deferral cheaply)
- [x] 23.2 Add `POST /api/v1/account/display_name`
- [x] 23.3 Add `POST /api/v1/account/recovery_codes/regenerate`
- [x] 23.4 Add `GET /api/v1/account/passkeys`, `DELETE /api/v1/account/passkeys/:credential_id` (same lockout protection as the web route)
- [x] 23.5 Add `DELETE /api/v1/account` (typed-username confirmation, sent as a JSON body rather than a query param since this is destructive and shouldn't land in access logs)
- [x] 23.6 Request specs covering the scenarios in `specs/mobile-account/spec.md` — 8 new examples in `spec/mobile_api_spec.rb`, full suite 1818/0

## 24. Phase 10 — Account management (iOS)

- [x] 24.1 Account models + screen — `Account.swift`, `AccountView.swift` (info, display-name edit, regenerate-codes button showing the new batch once via alert, passkey list + swipe-to-revoke, delete-account with typed confirmation, "Add to Calendar" opening the `.ics` URL in a `SafariView` sheet)
- [x] 24.2 Wire account deletion to sign out + clear the Keychain token locally — reuses `AuthViewModel.signOut()` (best-effort token revoke + local Keychain clear)
- [x] 24.3 Add a navigation entry point for Account — `SidebarView.swift`'s "Manage" section
- [x] 24.4 Verified in the Simulator: builds clean on iPhone + iPad against the real dev server

## 25. Seed data for manual testing

Not a product capability (no spec.md — this is dev tooling, not app behavior), but tracked here since it's part of the same effort: a script that populates one user's account with realistic content across every phase built so far, so every screen has something to look at instead of an empty state during manual testing.

- [x] 25.1 `scripts/seed_ios_demo_data.rb` + `make seed-ios-demo USER=`: subscribes to a real mix of catalog feeds (tech, podcast, YouTube, comics, NPR, PBS) and triggers a real fetch (`Scheduler.refresh_one`) so articles/images are genuine, not placeholder text
- [x] 25.2 Marks some articles read/bookmarked; adds a tag rule (applied against existing articles via `TagsApplier`); adds a mute rule
- [x] 25.3 Follows a sports team/league/player — replicates `ensure_catalog_team_in_db`'s logic inline (it's a private Sinatra `helpers` method, not callable from a standalone script) and seeds standings/match rows so team/league detail screens show real-looking data without waiting on a live ESPN sync
- [x] 25.4 Follows 2 stock symbols, seeds cached quotes (`StockQuotesStore.upsert`, no `FINNHUB_API_KEY` needed), and subscribes + real-fetches each symbol's news feed
- [x] 25.5 Follows 2 radio stations
- [x] 25.6 Generates a digest; runs triage if `ANTHROPIC_API_KEY` is set (skips gracefully, logged not errored, otherwise)
- [x] 25.7 Documented in `ios/README.md` (also refreshed the doc's stale "Phase 1" framing — it hadn't been updated since Phase 1 shipped)

**Verified live** against the real dev database with an existing account (`ios-tester`): all 6 feeds fetched real content (30/2/15/4/10/20 articles imported), tag matched existing articles, sports team/league/player followed with seeded standings/matches, both stock symbols followed with real news fetched, 2 radio stations followed, a digest generated (25 articles), and — since `ANTHROPIC_API_KEY` happened to be set on this machine — a real triage run completed (6 must-read / 9 optional / 15 skip).

## 26. Phase 11 — Article detail parity (backend)

- [x] 26.1 Add `summary` and `tags` to `GET /api/v1/articles/:uid` (wraps `SummaryStore.find` + `TagsStore.tags_for_article`)
- [x] 26.2 Add `POST /api/v1/articles/:uid/feedback` (wraps `ReadStateStore.mark_feedback`, validates `value ∈ {-1,0,1}`)
- [x] 26.3 Add `POST /api/v1/articles/:uid/tags/:tag_id` and `DELETE /api/v1/articles/:uid/tags/:tag_id` (wraps `TagsStore.tag_article`/`.untag_article`, 404 if the tag isn't owned by the caller — check via `TagsStore.find(api_user_id, tag_id)` first)
- [x] 26.4 Request specs covering the scenarios in `specs/mobile-article-detail-parity/spec.md` — 7 new examples in `spec/mobile_api_spec.rb`, full suite 1825/0. Note: every non-empty article gets an automatic extractive summary on import (`ArticlesStore#generate_extractive_for`), so "no summary yet" only occurs for empty-body articles — adjusted a test assumption accordingly.

## 27. Phase 11 — Article detail parity (iOS)

- [x] 27.1 Extend `Article` model: `summary` (new `ArticleSummary` type), `tags: [Tag]`, `feed: Feed?`, `feedback: Int?` — `Models/Article.swift` + `Models/Article+Display.swift` (relative time / reading time / duration / hero-image-URL helpers)
- [x] 27.2 Article detail header: hero image, feed name, author, relative time, reading time / episode duration
- [x] 27.3 "Source" link/button opening `article.url` in a `SafariView` sheet
- [x] 27.4 👍/👎 feedback controls wired to the new endpoint
- [x] 27.5 Mute-author / mute-keyword shortcuts on the article screen (reuses the existing `POST /api/v1/mute_rules`, just surfaced inline instead of only from the Mute Rules management screen)
- [x] 27.6 Tag chips: applied tags (tap to remove) + unapplied tags (tap to apply), wired to the new endpoints
- [x] 27.7 Cached summary display block
- [x] 27.8 Real mark-unread control (toolbar envelope icon toggles both ways now; `.task` still auto-marks-read once on open, matching the web app's behavior of marking read on open)
- [~] 27.9 Verified what can be verified non-interactively: `xcodegen generate` + clean build succeeded on iPhone 17 and iPad Pro 11" (M5) destinations, and the app installs and launches without crashing on both (screenshot-confirmed — iPhone 17 shows the recovery-code login screen; iPad Pro 11" is already signed in as `ios-tester` from an earlier session and shows the sidebar/split view with no regressions). **Full tap-through into an article to see the new header/feedback/mute/tags/summary chrome needs a human at the Simulator** — no Accessibility automation access in this environment, same limitation as every prior interactive-verification task. A fresh recovery code for `ios-tester` was minted for this (see chat).

## 28. Phase 12 — The reading river (backend)

- [x] 28.1 Add a `kind` query param to `GET /api/v1/articles` (`podcast` or unset/all), passed through to `ArticlesStore.recent` (matches the web app: `kind`/`topic` only apply on the unscoped branch, not the tag/feed branches)
- [x] 28.2 Add a `sort` query param (`relevance` or unset/chronological); when `relevance`, call `Recommendation::ForYou.score_window(api_user_id, state: :unread, kind:, topic:, limit:, offset:)` instead of `ArticlesStore.recent`, forcing the effective state to unread — mirrors `app/main.rb`'s web `/articles` route (~line 2122)
- [x] 28.3 Request specs covering the scenarios in `specs/mobile-reading-river/spec.md` — 2 new examples in `spec/mobile_api_spec.rb`

## 29. Phase 12 — The reading river (iOS)

- [x] 29.1 `APIClient.fetchArticles` gains `kind`/`sort` params, passed through to the existing query-building `urlPath` helper
- [x] 29.2 New `ReadingRiverView`: state filter (segmented control: all/unread/bookmarked/archived), kind filter (podcasts-only toggle), topic filter (picker — a static list mirroring `FeedCatalog::TOPICS`, not the unrelated AI topic-clusters `/api/v1/topics` endpoint the Topics sidebar item already uses), and a "For You (relevance)" toggle that also forces the state filter to unread, matching the web app
- [x] 29.3 Page-based "Load More" at the end of a full page (heuristic: last fetch returned a full page's worth of rows) — appends without duplicating or losing scroll position
- [x] 29.4 Add `.allArticles` to `SidebarItem`/`SidebarView` (Library section, above the per-feed list) and wire it in `MainView`'s switch
- [~] 29.5 Build succeeded and installed/launched cleanly on iPhone 17 and iPad Pro 11" (M5) — screenshot-confirmed the new "All Articles" sidebar entry renders correctly on iPad (already signed in). Interactive verification of the filters/sort/pagination themselves needs a human at the Simulator, same limitation as every prior interactive-verification task.

## 30. Phase 13 — Player parity (iOS only, no backend changes)

Everything here is local playback state — resume position lives in `UserDefaults`, matching the web app's own `localStorage`-based, non-account-synced approach. No new `/api/v1/*` surface.

- [x] 30.1 `AudioPlayerViewModel`: add `seek(to:)`, `skipBackward()`/`skipForward()` (15s/30s, matching the web app's `SKIP_BACK_S`/`SKIP_FWD_S`), `playbackRate` + `setPlaybackRate(_:)` (1×/1.25×/1.5×/1.75×/2×, matching the web `<select>` options)
- [x] 30.2 Resume-from-last-position: per-episode position saved to `UserDefaults` (throttled, matching the web's 5s throttle), restored on `play(_:)` unless within the last 30s of duration (matches the web's `RESUME_TAIL_S`)
- [x] 30.3 `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` wiring: title/elapsed/duration/rate published on every time-tick and state change; play/pause/skip-backward/skip-forward/changePlaybackPosition commands registered so lock-screen/CarPlay/AirPods controls work on backgrounded audio
- [x] 30.4 `MiniPlayerView`: scrubber (Slider, seeks on release), elapsed/duration time labels, skip-back/skip-forward buttons, playback-speed menu — all hidden for radio streams (no known duration), matching the existing indeterminate-progress fallback
- [~] 30.5 Build succeeded and installed/launched cleanly on iPhone 17 and iPad Pro 11" (M5), no regressions (screenshot-confirmed). Actually playing an episode, scrubbing, and checking Control Center/lock-screen controls needs a human at the Simulator — no Accessibility automation access in this environment, same limitation as every prior interactive-verification task.

## 31. Phase 14 — Home dashboard (backend)

- [x] 31.1 Add `GET /api/v1/home`: stats (`ReadStateStore.unread_count`/`.bookmarked_count`, `ArticlesStore.count_for_user`), today's matches + live matches (reusing `build_teams_by_id_for_matches` to merge `home_team`/`away_team`, same as `/api/v1/sports/overview`), and today's reading/listening/watching (same `Recommendation::ForYou.score_window` + kind-partition logic as the web's `load_whats_on_today!`, minus its YouTube-fallback padding — see design.md)
- [x] 31.2 Request specs covering the scenarios in `specs/mobile-home-dashboard/spec.md` — 3 new examples in `spec/mobile_api_spec.rb`. Caught a real environment footgun along the way (not an endpoint bug): scoping the run with `rspec -e "..."` corrupts `ENV['RACK_ENV']` (some gem in the load chain reads real `ARGV` for `-e`), which silently re-enables the shared Redis cache mid-test — saved as a memory (`feedback_rspec_dash_e_env_corruption`), use file:line targeting instead.

## 32. Phase 14 — Home dashboard (iOS)

- [x] 32.1 `APIClient.fetchHome()` + a `HomeResponse` model (stats, today_matches, live_matches, today_reading/listening/watching — reuses the existing `Article`/`SportsMatch` models)
- [x] 32.2 New `HomeView`: stats row, live matches + today's matches (reusing existing `MatchRow`), to-read/to-listen/to-watch sections (reusing `ArticleRow`), and a "Continue Listening" section built from local `UserDefaults` resume-position keys (`tfr.podcast.position.<uid>`, written by Phase 13, exposed via a new `AudioPlayerViewModel.storedPositions()` static) resolved via `fetchArticle(uid:)`
- [x] 32.3 Add `.home` to `SidebarItem`/`SidebarView` (top of Library) and make it `MainView`'s default `selection` so the app no longer opens to "Select an Item"
- [x] 32.4 Empty state ("Nothing New Today") when every section is empty
- [x] 32.5 Verified in the Simulator against the local dev server (real `ios-tester` data: stats, 2 live matches, 5 today's/upcoming matches) — screenshot-confirmed on iPad Pro 11" (M5). Caught a second real environment footgun along the way, unrelated to the endpoint itself: `xcodebuild install` (no `-configuration`) silently defaults to **Release**, which points at production (`https://feeder.tmoneystuff.com`) instead of localhost — every prior phase's install+screenshot verification this session had almost certainly been doing the same thing. Saved as a memory (`feedback_xcodebuild_install_defaults_release`); always pass `-configuration Debug` explicitly from here on.

## 33. Phase 15 — Discovery odds and ends (backend)

- [x] 33.1 `GET /api/v1/articles/bus?max_minutes=` (default 15, clamp `[1,90]`, limit 25 — mirrors the web `/bus` route's constants)
- [x] 33.2 `GET /api/v1/articles/lucky` (wraps `ArticlesStore.random(api_user_id, limit: 50)`)
- [x] 33.3 `POST /api/v1/feeds/:id/refresh` (enqueues `FeedRefreshWorker.perform_async`) and `POST /api/v1/feeds/:id/weight` (body `direction`, wraps `FeedFeedbackStore.bump`); `GET /api/v1/feeds` now merges in `weight` via `FeedFeedbackStore.weights_by_feed_id`
- [x] 33.4 `POST /api/v1/tags` (create + backfill, mirrors web `/tags`) and `DELETE /api/v1/tags/:id` (wraps `TagsStore.remove`)
- [x] 33.5 `GET /api/v1/onboarding/chips` (serializes `FeedCatalog::ONBOARDING_CHIPS`) and `POST /api/v1/onboarding/subscribe` (body `topics: [...]`, wraps `FeedCatalog.starters_for_topic` + `FeedsStore.add_for_user`, mirrors web `/welcome/subscribe`)
- [x] 33.6 `GET /api/v1/account/export` (wraps `AccountExport.for_user`, no attachment headers — this is an API call, not a browser download)
- [x] 33.7 Request specs covering the scenarios in `specs/mobile-discovery-odds-and-ends/spec.md` and the feed-weight scenario in `specs/mobile-api/spec.md` — 9 new examples. Caught a test-authoring mistake (not a route bug): JSON-body POST specs need an explicit `CONTENT_TYPE: application/json` header merge or Rack::Test defaults to form-urlencoded and Sinatra's form-param parsing drains the body before the route's own `parse_json_body` reads it — the real iOS client always sets this header itself, so production was never affected.

## 34. Phase 15 — Discovery odds and ends (iOS)

- [x] 34.1 `APIClient` methods for all six new endpoint groups above; `Feed` model gains `weight: Double?`; new `OnboardingChip` model
- [x] 34.2 `BusModeView`: episode list + a max-minutes stepper, reachable from the sidebar
- [x] 34.3 "I Feel Lucky" screen (reuses `ArticlesListView`), reachable from the sidebar
- [x] 34.4 Per-feed refresh-now + weight controls (up/down/reset) via a new `FeedArticlesView` wrapper (adds a toolbar menu around the existing `ArticlesListView`, rather than forking it) — used for the `.feed(_)` sidebar case
- [x] 34.5 `TagsListView` gains an "Add Tag" sheet (name/kind/value) and swipe-to-delete
- [x] 34.6 `WelcomeView` + `HomeGateView`: topic chips → subscribe, shown instead of `HomeView` when the account has zero subscribed feeds (fails open to `HomeView` on a network error during the check)
- [x] 34.7 `AccountView` gains an "Export My Data" action using `ShareLink` with the fetched export JSON written to a temp file
- [x] 34.8 Verified in the Simulator against the local dev server (`-configuration Debug` explicit) on iPhone 17 and iPad Pro 11" (M5) — screenshot-confirmed Home loads with the new "Bus Mode"/"I Feel Lucky" sidebar entries and no regressions. Hit two build errors along the way (both fixed, neither environment-related): a SwiftUI `ForEach`/`Binding` overload-resolution error in `WelcomeView` resolved by extracting the row into its own `@ViewBuilder` method, and `.foregroundStyle(.accentColor)` needing to be `Color.accentColor` (ShapeStyle has no bare `.accentColor` member, unlike `.tint`).

## 35. Phase 16 — Visual parity (backend)

- [x] 35.1 `GET /api/v1/articles` — recognize `kind=youtube` (map to `ArticlesStore`'s existing `:youtube` filter, alongside the current `podcast`/`all`), matching web's `/youtube` route's `kind: :youtube` usage
- [x] 35.2 Request spec covering the scenario in `specs/mobile-visual-parity/spec.md` — 1 new example in `spec/mobile_api_spec.rb`

## 36. Phase 16 — Visual parity (iOS)

- [x] 36.1 `Article+YouTube.swift` gains `youtubeThumbnailURL` (derives `https://i.ytimg.com/vi/<id>/hqdefault.jpg` from the existing `youtubeVideoID`, matching web's `youtube_thumbnail_url`); `Article+Display.swift` gains `thumbnailURL` (own image, else the YouTube fallback) and `excerptText` (whitespace-collapsed, truncated, mirrors `.podcast-card-excerpt`)
- [x] 36.2 New `ShowGridCard` component (cover art + title + meta line, grid-friendly) mirroring `.podcast-show-card` — used by both Podcasts' shows grid and YouTube's channels grid
- [x] 36.3 **Deviation from the plan**: rather than a separate `MediaCardRow` component, extended the existing shared `ArticleRow` in place with a leading thumbnail + excerpt (mirroring `.podcast-card`). `ArticleRow` already carried the duration badge + play button (added for the podcast-play-button fix) and is already what `ArticlesListView` uses for every list — Podcasts' "Recent Episodes", Comics, and NPR/PBS all get the image-led card look for free, with no risk of the two components drifting apart. A parallel `MediaCardRow` would have duplicated the play-button logic for no benefit.
- [x] 36.4 New `VideoGridCard` component (16:9 thumbnail + play-icon overlay, title, meta) mirroring `.youtube-video-card` — used by YouTube's new "Recent Videos" section
- [x] 36.5 `PodcastsView`: two sections — "Recent Episodes" (`ArticleRow` list, `kind: "podcast"`) above "Subscribed Shows" (`ShowGridCard` grid), matching the web page's order
- [x] 36.6 `YouTubeChannelsView`: two sections — "Recent Videos" (`VideoGridCard` grid, `kind: "youtube"`, new — doesn't exist on iOS today) above "Subscribed Channels" (`ShowGridCard` grid, reusing the same component Podcasts uses)
- [x] 36.7 Comics/NPR/PBS (`.comics`/`.npr`/`.pbs` cases in `MainView`) needed **no changes** — they already call the shared `ArticlesListView` → `ArticleRow`, so 36.3's enhancement applies automatically
- [x] 36.8 Verified in the Simulator against the local dev server (`-configuration Debug` explicit) on iPhone 17 and iPad Pro 11" (M5) — screenshot-confirmed on iPad: Home's "Continue Listening" row (which reuses `ArticleRow`) now shows a real cover-art thumbnail and excerpt text. Full interactive verification of the new Podcasts/YouTube grid sections needs a human at the Simulator per the established limitation (no Accessibility automation access).
- [x] 36.9 **Follow-up fix (2026-09-17, user feedback)**: user reported Podcasts looked great but YouTube's "Recent Videos" tiles "blend together — just images lined up, no sense of a tile." Root cause: `VideoGridCard` had no card container (background/padding) — just an image with text floating below it, so adjacent thumbnails had nothing separating them. Fixed by wrapping the card in a `secondarySystemGroupedBackground` container with padding + rounded corners (so each tile reads as one bounded unit), replacing the plain white play-glyph with a dark-scrim circle behind it (matches the web's `rgba(0,0,0,0.55)` play button — a bare white icon didn't read clearly against bright thumbnails), and adding an explicit "▶ Watch · <date>" line so the tile states its action instead of just showing a title. Could not re-verify visually (same Accessibility-automation limitation — tapping into YouTube isn't possible here); worth a look next time you're in the Simulator.
- [x] 36.10 **Second follow-up fix (2026-09-17, user feedback)**: user reported the fixed tile looked right at first, then "flickers and shows cards for each entry but with only the image and part of the source like BBC Earth" — i.e. scrolling into "Subscribed Channels" (which shows channel names like a nature channel would). Two real bugs, both fixed: (1) `ShowGridCard` (used by Subscribed Channels, and by Podcasts' Subscribed Shows) never got 36.9's card-container treatment — same "just images" problem, now consistent with `VideoGridCard`. (2) `VideoGridCard`'s thumbnail sized itself from the `AsyncImage`'s own content (`.aspectRatio` applied directly to the image), so the tile's height could jump the moment the network image finished loading — the actual "flicker," and a plausible way for the title/meta text to get squeezed out of a not-yet-settled row. Fixed by sizing the 16:9 frame from a `Color.clear` driver instead (fixed instantly at layout time) with the image as an `.overlay` filling already-settled bounds, so the frame never changes size once the image arrives. Build succeeded, no crash; still couldn't tap into YouTube itself to confirm the visual fix directly (no Accessibility automation here).

## 37. Phase 17 — Sports polish (backend)

- [x] 37.1 Fix `GET /api/v1/sports/leagues/:slug`: fall back to `SportsCatalog.all_leagues.find { |lg| lg[:slug] == slug }` (stripped of the embedded `:teams` array, matching `/api/v1/sports/:sport_slug/leagues`'s existing `.reject`) when `SportsLeaguesStore.find_by_slug` is nil, returning empty standings/matches + `followed: false` instead of a 404 — matches the existing `teams/:slug` fallback pattern
- [x] 37.2 Add `GET /api/v1/sports/tennis/rankings` (param `limit`; returns both `atp`/`wta` lists, wraps `SportsPlayersStore.top_ranked` + `.refresh_if_stale!`, mirrors the web `/sports/tennis` route) including the caller's followed player slugs
- [x] 37.3 Request specs covering the scenarios in `specs/mobile-sports-polish/spec.md` — 2 new examples in `spec/mobile_api_spec.rb`

## 38. Phase 17 — Sports polish (iOS)

- [x] 38.1 `MatchRow`: show home/away team logos (`imageUrl`, small `AsyncImage`) next to each name — new shared `TeamLogo` view (degrades to empty space, not a broken-image glyph, when a team has no logo)
- [x] 38.2 `SportsHomeView`'s Followed Teams/Players rows and `SportsLeagueDetailView`'s Teams section rows: add a small logo (`TeamLogo`, reused for both team and player headshots)
- [x] 38.3 `SportsTeamDetailView`: add a logo header (larger `imageUrl`, matching the web's team-page header treatment)
- [x] 38.4 New `TennisRankings` model + `APIClient.fetchTennisRankings()`; new `SportsTennisRankingsView` (ATP/WTA sections, headshot via `TeamLogo`, rank, inline ★/☆ follow toggle — no navigation required to follow)
- [x] 38.5 `SportsHomeView` gains a persistent "Tennis Rankings (ATP/WTA)" entry point (alongside "Browse Sports"), navigating to `SportsTennisRankingsView`
- [x] 38.6 Verified in the Simulator against the local dev server (`-configuration Debug` explicit) on iPad Pro 11" (M5) — screenshot-confirmed real team logos render correctly in Home's Live/Today's Matches sections (which reuse `MatchRow`): St. Louis Cardinals, Toronto Blue Jays, Miami Marlins, Mets, Titans, Dolphins, 49ers, Cardinals all show real ESPN logos; one seeded team with no `image_url` (a demo-data gap, not a code bug) degrades gracefully with no broken-image placeholder. Also verified live via curl: a catalog-only tournament (Wimbledon) now returns 200 with catalog data instead of 404, and the tennis-rankings endpoint returns real ATP/WTA lists (50 each) with correct followed-player state. Full suite 1846/0. Couldn't tap into Sports/Tennis Rankings directly to screenshot those specific screens (no Accessibility automation here) — worth a look next time you're in the Simulator.
