## Context

`TriviaStore.fetch_source_articles` (`app/games/trivia_store.rb`) selects trivia source material with:

```sql
SELECT title, url, content_text FROM articles
WHERE published_at > $1
  AND title IS NOT NULL
  AND content_text IS NOT NULL
  AND content_text != ''
ORDER BY published_at DESC
LIMIT $2   -- SOURCE_ARTICLE_LIMIT = 20
```

This trusts `published_at` as a proxy for "genuinely recent, substantive news" and trusts `content_text != ''` as a proxy for "has enough material to write a question about." Both assumptions broke down against a real feed: **feed 254, "Three Word Phrase"** (a webcomic). Its upstream RSS reports `published_at` for a large batch of items clustered at/near the fetch moment (confirmed: 82 rows sharing the exact value `2026-07-23T20:11:00Z`, plus individual rows dated `2026-08-01` and `2026-09-16` — in the future) while `content_text` is a handful of words of comic dialogue (`"*cough*"`, `"ha ha ha huhhhhgh"` — 4 to 60 characters). Because `content_text != ''` is satisfied and `published_at` sorts these rows to the top, they can (and on 07-22/07-23, did) occupy most or all of the top-20 slots, leaving `TriviaGenerator.generate` with ~1,700 characters of comic dialogue instead of the usual ~15,000–17,000 characters of real article text. Claude can't write 3+ valid multiple-choice news questions from that, `parse_questions` returns fewer than 3 valid results, and `generate` returns `status: :error`. `ensure_today!` returns `nil`. `GenerateTriviaWorker#perform` logs `AppLogger.warn('generate_trivia_skipped', ...)` and returns — Sidekiq sees a normal, successful job completion. No exception → no retry → no dead job → the `death_handlers` alert in `app/sidekiq_config.rb` never fires, because that alert is scoped to jobs that exhaust retries, not jobs that "succeed" at doing nothing.

This was confirmed directly against production: `docker compose logs sidekiq` shows `GenerateTriviaWorker` completing every day since 07-12 with no exception; the `trivia_generate_start`/`trivia_generate` structured log lines show `context_chars` dropping from a healthy ~15–17K to exactly 1,725 on the three affected runs (07-22 01:30 UTC, 07-23 01:30 UTC, and a 07-23 20:59 UTC manual retry); and a direct query against the production DB reproduced the exact top-20 selection at each of those moments, showing it dominated by feed 254's rows. By later on 07-23, enough real news had published past the pinned `2026-07-23T20:11:00Z` timestamp that the query recovered on its own — which is also why a manual CLI run at some other point in the day looks like it "just works."

The original hypothesis for this change (a stale/duplicate Sidekiq worker process causing `NameError: uninitialized constant GenerateTriviaWorker`) was investigated first per the task-1 gate in this change's original plan, and ruled out — that pattern appears in local dev logs only (multiple independently-started Sidekiq processes sharing one Redis in `make run-all`/`make sidekiq` sessions), never in production. It's a real dev-tooling rough edge but not the cause of the reported production failures, so it's out of scope here; the dev-tooling hardening tasks from the earlier plan are dropped rather than carried forward, since the actual production bug requires a different fix entirely and the current tasks should stay focused on it (worth raising separately if the dev-side flakiness itself bothers the user).

## Goals / Non-Goals

**Goals:**
- Make `fetch_source_articles` resilient to any feed's low-substance/junk articles polluting the trivia source pool — not just feed 254, since the same shape of bug (real-looking `published_at`, near-empty `content_text`) could come from a different feed later.
- Turn a failed/skipped trivia generation into a same-day, actionable signal, since this failure mode inherently completes the Sidekiq job without an exception.
- Verify the fix against the actual historical bad state (feed 254's pattern) so this specific case is confirmed closed, not just theoretically addressed.

**Non-Goals:**
- Fixing feed 254's upstream RSS or auditing other feeds for similar date/content quality issues — the user chose the general content-quality guard over unfollowing/excluding this one feed, so feed 254 keeps flowing into the normal reading experience; only trivia's source selection changes.
- Rewriting `TriviaGenerator`'s prompt/parsing logic — `parse_questions`'s `< 3` threshold and error handling are already correct; the problem is what's fed into it, not how the response is parsed.
- General sidekiq-cron / dev process-lifecycle hardening — investigated, real in dev, but not the cause of this bug; out of scope for this change.

## Decisions

1. **Add a minimum `content_text` length to `fetch_source_articles`'s WHERE clause**, e.g. `LENGTH(content_text) >= 100`. Chosen over a post-query Ruby filter so `LIMIT 20` still applies after quality filtering (fetching 20 already-good rows, not fetching 20 rows and then having fewer than 20 usable ones). 100 was picked by looking at real observed data: the shortest genuinely substantive article content seen in a healthy sample was 111 characters (a terse one-line news blurb); the longest observed junk row (feed 254) was 59 characters. A threshold of 100 clears all observed junk while keeping the shortest legitimate real article seen so far — with headroom, not a knife-edge cutoff.
   - *Alternative considered*: exclude feed 254 specifically (e.g. a feed-id denylist in the query, or unfollowing it). Rejected per explicit choice — it only patches this one feed and leaves the underlying assumption (`published_at` + non-empty `content_text` ⇒ good trivia material) broken for the next low-content feed.
   - *Alternative considered*: a per-feed cap (e.g. "no more than 2 articles per feed in the top 20") to guarantee topic diversity regardless of content length. Rejected as unnecessary for this bug — the actual failure was about substance (near-zero content), not about a single feed merely being over-represented; a length floor addresses the observed failure directly without adding a second, independent selection rule.
   - *Alternative considered*: clamp/reject `published_at` values in the future. Also would have caught 2 of the 82 bad rows, but not the other 80 (their `published_at` was merely "recent," not future) — the content-length floor catches all of them uniformly since every bad row observed had near-zero content, regardless of its exact timestamp.

2. **Alert when `ensure_today!` returns `nil`.** `GenerateTriviaWorker#perform` already distinguishes success from failure (`AppLogger.info` vs `AppLogger.warn('generate_trivia_skipped', ...)`); add a `Notifier.push` call in the failure branch, mirroring how `app/sidekiq_config.rb`'s `death_handlers` already alerts on dead jobs. This is the only way this class of failure (a job that completes without raising) becomes visible same-day instead of requiring someone to notice a missing quiz and go read logs.
   - *Alternative considered*: rely solely on `HealthAlertWorker`'s existing dead-set-size / feed-freshness checks. Rejected — neither check is scoped to "did today's trivia quiz get created," so neither would catch this.

3. **Verification uses the real historical bad state, not just a synthetic one.** Since the actual feed-254 data is sitting in the production DB, verification re-runs the equivalent of `fetch_source_articles` against the historical cutoff window that previously failed and confirms the new WHERE clause now selects substantive articles instead — this is stronger evidence than only checking against today's (currently healthy) window.

## Risks / Trade-offs

- [A legitimate but very short news blurb (under 100 chars) gets excluded from the trivia pool] → Acceptable: `SOURCE_ARTICLE_LIMIT` only needs 20 usable articles out of a 24h pool that's routinely in the thousands (2,437 with non-empty content_text observed in one snapshot); losing occasional very-short legitimate blurbs doesn't threaten reaching 20.
- [A different feed produces junk with `content_text` just over the 100-char floor] → The floor is a heuristic, not a guarantee; it directly closes the observed failure without claiming to solve source-quality in general. If this recurs with a different shape of junk, that's a follow-up, not evidence this fix was wrong.
- [The new `Notifier.push` on skipped generation could be noisy if `TriviaGenerator.available?` is false in an environment without `ANTHROPIC_API_KEY` (e.g. some future staging setup)] → Scope the alert to the actual failure path already distinguished in the worker (`AppLogger.warn('generate_trivia_skipped', ...)`), which already fires in both the "unavailable" and "failed" cases today; this isn't a new noise source, just a new place the existing signal also gets pushed.

## Migration Plan

No data migration. This is a query/logic change in `app/games/trivia_store.rb` and `app/workers/generate_trivia_worker.rb`, deployed via the project's standard `make release-patch` release process. Rollback is a plain revert — no persisted state changes shape.

## Open Questions

(none outstanding — root cause and fix approach are confirmed against production logs and the production database)
