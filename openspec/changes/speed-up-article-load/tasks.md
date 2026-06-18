## 1. Profile & benchmark (no behavior change)

- [x] 1.1 Extend `scripts/bench_hotpaths.rb` (or add `scripts/bench_article_load.rb`) to time `ForYou.next_after` and a breakdown of `compute_ranking`: positive/negative corpus queries, `ArticlesStore.recent` candidate fetch (CANDIDATE_WINDOW=500), and the Ruby tokenize-and-score loop — against `DATABASE_URL` at full corpus.
- [x] 1.2 Capture `EXPLAIN (ANALYZE, BUFFERS)` for the candidate fetch (`ArticlesStore.recent` unread+subscription scoped) and the two corpus queries; record whether the ~4 s is IO-bound (SQL) or CPU-bound (Ruby scoring/tokenization).
- [x] 1.3 Record the baseline: uncached `next_after` ms, uncached full article-route ms, warm article-route ms. Write the numbers into the change for before/after comparison.

## 2. Unblock page render — defer "Read next"

- [x] 2.1 Add `GET /article/:uid/read-next` that renders just the Read-next card (personalized `ForYou.next_after`, falling back to FTS `Recommendation.for_article`) as an HTML fragment; JSON/HTML per the existing fragment pattern.
- [x] 2.2 In `views/article.erb`, render the Read-next card as a deferred/lazy fragment (turbo-frame or a small fetch, mirroring `_stock_news.erb`) with a lightweight skeleton placeholder.
- [x] 2.3 Remove the synchronous `ForYou.next_after` call from `get '/article/:uid'` so the article HTML no longer blocks on it; keep the FTS `@related` (cheap) inline.
- [x] 2.4 Add the Read-next JS to `views/layout.erb` (asset_mtime, guarded init, re-bind on `turbo:load`) — not a per-view `<script>`.
- [x] 2.5 Spec/test: article route returns without invoking `next_after`; the fragment endpoint returns a suggestion or the Related fallback; page renders when Redis is down.

## 3. Optimize the ranking computation — DESCOPED (see findings.md)

Investigated and dropped: measurement disproved the premise. Forcing the
candidate query off the seq scan was **469 ms** vs the planner's seq-scan plan
at **58 ms** — no index helps, the plan is already optimal. Residual costs
(cold PG buffers; keyword-mute `content_text LIKE`) aren't indexable and are
covered by Phase 2 (off critical path) + Phase 4 (warm cache).

- [x] 3.1 ~~Add an index~~ — measured counterproductive (469 ms vs 58 ms); dropped.
- [x] 3.2 ~~Reduce CPU work~~ — not CPU-bound (score loop ~14 ms); n/a.
- [x] 3.3 ~~Reuse list ranking in next_after~~ — moot; Phase 2 defers + Phase 4 warms.
- [x] 3.4 Ranking order unchanged — no algorithm change made (For-You specs still pass).
- [x] 3.5 Re-ran the bench — recorded in findings.md.

## 4. Keep the cache warm

- [x] 4.1 Add a Sidekiq worker that precomputes `ForYou.ranked_ids` for recently-active users; register it on a cron cadence below `RANKING_TTL`.
- [x] 4.2 Bound the job to "active" users (last-seen window) and respect the `db-s-1vcpu-1gb` connection budget; verify it doesn't starve the pool.
- [x] 4.3 Confirm the deferred Read-next fragment is fast on a normally-warm cache.

## 5. Client-side audit (measure-first) — DEFERRED

The reported "5 s uncached" was server-side (now ~24 ms). The client side was
already addressed in #98 / v1.0.6 (self-hosted Turbo removed the render-blocking
unpkg CDN; the article body had no serial-image problem in the profiled cases).
A full authenticated-waterfall audit is a low-priority follow-up, not part of
this change's win.

- [ ] 5.1 Capture an authenticated article-page network waterfall (headless CDP harness from #98) on a real, image-heavy article.
- [ ] 5.2 Identify any resources loading serially that could be parallel, or render-blocking/synchronous front-end steps; list concrete findings.
- [ ] 5.3 Fix only confirmed issues (e.g. lazy-load body images, parallelize independent fetches); skip if the waterfall is already clean post-Turbo-self-host.

## 6. Verify & lock in the budget

- [x] 6.1 Confirm uncached `/article/:uid` server render is < 800 ms at full corpus (the §1 bench).
- [x] 6.2 Add a guard test/bench that fails if the uncached article path regresses past budget.
- [x] 6.3 Run the full suite; manual/headless verify the article page renders fast and Read-next fills in; update STUFF.md / docs as needed.
