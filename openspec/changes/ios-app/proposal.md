## Why

Tech Feed Reader is currently a responsive web app only (`SPEC.md` explicitly lists "Mobile-native app" as a non-goal). Users want a native iOS experience for reading their feeds on iPhone and iPad. This change reverses that prior non-goal decision and adds a first-class native client that shares the same account and data as the web app.

## What Changes

- Add a native iOS app (iPhone + iPad, iPad full-screen) built with Xcode/SwiftUI, living entirely under a new top-level `ios/` directory so it never intermingles with the existing Sinatra app's files.
- Add sign-up and login to the iOS app using the **same account system already in place**: passkeys (WebAuthn), not a new username/password system. **Assumption (stated, not asked): because the existing system is passkey-only with no email/password, the iOS app reuses the same passkeys via Associated Domains, so a user's passkey created on web works natively on iOS and vice versa** — this is the only approach consistent with the existing account model, so it's treated as a design decision rather than an open question.
- Add a new token-authenticated JSON API (`/api/v1/...`) exposing feeds, subscriptions, articles, and read-state, since **no general JSON API exists today** — only the WebAuthn ceremony endpoints are JSON. The web app's cookie-session HTML routes are untouched.
- Support running the iOS app locally against a local dev server (`make run`/`make serve` on `http://localhost:4567`) for development, in addition to pointing at production.
- Revise `SPEC.md`'s "Mobile-native app — responsive web only" non-goal, since it's being directly reversed by this change.
- **Grow the iOS app toward full feature parity with the web app, in phases** (Phase 3 onward — see `design.md` → "Feature-parity roadmap"). Phase 3, specced and built as part of this update: bookmarks, full-text search, tag browsing, topic browsing, and read/unread/archived filters on the article list — the reading-experience features that don't require a new content type or backend subsystem.
- **BREAKING**: none — all changes are additive (new directory, new API namespace, new entitlements/config). No existing web routes, sessions, or HTML behavior change.

## Capabilities

### New Capabilities
- `mobile-api`: Token-authenticated JSON API (feeds, subscriptions, articles, read-state) plus passkey-based token issuance for native clients, built alongside the existing cookie-session web auth without changing it.
- `ios-app`: Native SwiftUI iPhone/iPad client (login, sign-up, feed/article reading) living under `ios/`, buildable and runnable locally via Xcode against a local or production API.
- `mobile-reading-parity`: Phase 3 — bookmarks, search, tags, topics, and read-state filters, extending `mobile-api` and the iOS app's existing Feeds/Articles screens.
- `mobile-feed-discovery`: Phase 4a — curated catalog browse, recommended-for-you feeds, popular-by-type charts, and mute rules (keyword/author/feed). Phase 4b (AI feed recommender, OPML import/export) is deferred within the same phase — see design.md.
- `mobile-podcasts-youtube`: Phase 5 — podcast episode browsing + native audio playback (a persistent mini-player, not an embedded web `<audio>` tag — matches the web app's "survives navigation" mini-player while using the platform's native AVPlayer), and YouTube channel browsing + embedded video playback.
- `mobile-sports`: Phase 6a — browse the curated sports catalog (sport → league → team), follow/unfollow teams/leagues/players, team/league/player detail (standings, upcoming, recent results, mentioning articles), and a followed-sports overview with live matches. Phase 6b (tennis ATP/WTA rankings, Wikipedia league summaries, calendar/.ics surfacing) is deferred within the same phase — see design.md.
- `mobile-stocks`: Phase 7 — symbol search, quote detail + per-symbol news, follow/unfollow (which also subscribes to the symbol's news feed, matching the web app), and a ticker (followed symbols + major world indices).
- `mobile-misc-content`: Phase 8a — Comics/NPR/PBS (topic-scoped browsing of things already built — a `topic` filter on the existing articles endpoint) and Radio (station catalog, follow/unfollow, native playback via the same audio player Phase 5 built). Phase 8b (Sudoku/Trivia games, radio AI recommendations) is deferred — see design.md.
- `mobile-ai-features`: Phase 9 — Triage (Claude classifies unread articles into must-read/optional/skip, listable + re-runnable) and Digests (recent digests, on-demand Claude summary), both gated by the same `LlmGuard` budget check the web routes use. Later phase (account management) is roadmapped in `design.md` but not yet specced.

### Modified Capabilities
(none — no existing openspec-tracked spec has changing requirements; the only existing spec, `ticker-api`, is unrelated and untouched)

## Impact

- **New directory**: `ios/` at repo root — Xcode project, Swift sources, assets. Nothing in `app/`, `views/`, or `public/` is touched by the iOS app itself.
- **Backend (Sinatra)**: new `/api/v1/*` JSON routes for feeds/subscriptions/articles/read-state; new passkey-ceremony-to-token issuance logic alongside `app/auth.rb`; existing cookie/session auth and HTML routes unchanged.
- **Infra**: an `apple-app-site-association` file must be served from the production domain (Caddy config) and an Associated Domains entitlement added to the iOS app, so platform passkeys work across web and iOS. Local dev/simulator testing of the passkey ceremony itself is constrained by this (see design.md) — the recovery-code fallback already in the web app becomes the practical way to test login locally.
- **Docs**: `SPEC.md` non-goal statement needs updating to reflect this reversal.
- **Dependencies**: no new backend gems required beyond what's already used for WebAuthn (`app/auth.rb`); iOS side uses only first-party Apple frameworks (AuthenticationServices, SwiftUI) — no third-party iOS dependencies.
