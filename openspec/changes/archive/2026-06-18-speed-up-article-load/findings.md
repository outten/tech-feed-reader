# Phase 1 findings — where the uncached article-load time goes

Measured with `scripts/bench_hotpaths.rb` + `EXPLAIN (ANALYZE, BUFFERS)` against
the prod-scale dev DB (32,610 articles, user 1).

## Root cause: the For-You candidate fetch, run synchronously via `next_after`

`get '/article/:uid'` blocks on `Recommendation::ForYou.next_after` → `compute_ranking`.
The dominant term is the candidate fetch `ArticlesStore.recent(limit: 500, state: :unread)`.

Component breakdown (warm Postgres buffers):

| Component | Time |
|---|---|
| positive/negative corpus queries | ~1 ms |
| corpus tokenize | ~27 ms |
| CPU score loop (500 candidates) | ~14 ms |
| **candidate fetch `recent(500, unread)`** | **~95–160 ms inherent** |
| compute_ranking (full) | ~180 ms |

It is **SQL-bound, not CPU-bound** (the user's "possibly not indexed well" hunch).

## Why it balloons to seconds (the "uncached" symptom)

`EXPLAIN ANALYZE` shows the candidate query **Seq Scans all 32,610 articles**, then a
per-row subscription `EXISTS` nested loop (~64k buffer hits), then a mute anti-join,
then a top-500 sort. The existing `idx_articles_published_at` is **not used** because
~85% of articles pass the unread+subscribed filter, so the planner can't short-circuit
the `LIMIT 500` and instead materializes the whole filtered set and sorts.

Two amplifiers turn the ~180 ms warm case into seconds:

1. **Cold Postgres buffers** — the full seq scan reads ~3,856 pages from disk when
   cold. On the production `db-s-1vcpu-1gb` (1 GB RAM, can't cache the whole table),
   the first/idle load measured **~4,000 ms**. This is the most likely cause of the
   user-reported 5 s on an uncached page.
2. **Keyword mute rules** — the mute anti-join runs `LOWER(a.content_text) LIKE
   '%kw%'` over every candidate's full body. One keyword rule added **~650 ms** to the
   scan (118 ms → 782 ms). Scales with candidates × keyword-rule count × body size.

## Implication for the plan

- **Phase 2 (defer Read-next)** is the robust primary fix: it takes this fragile,
  variable cost (180 ms warm → 4 s cold → +650 ms/keyword-mute) off the critical
  render path entirely. The page paints immediately in all states.
- **Phase 3** should target the candidate fetch: avoid the full seq scan (walk
  `published_at DESC` and stop at the window), and/or stop scanning `content_text`
  with `LIKE` for keyword mutes. Gated on a before/after `EXPLAIN ANALYZE`.
- The CPU scoring loop and corpus queries are **not** worth optimizing (~40 ms total).

## Phase 3 update: an index would HURT — descoped

Tested forcing the candidate query off the seq scan (`SET enable_seqscan = off`)
to walk `idx_articles_published_at` and stop at 500:

| Plan | Execution time |
|---|---|
| Index-walk (forced) | **469 ms** |
| Planner default (seq scan + top-N sort) | **58 ms** |

The planner's seq-scan plan is ~8× faster — the per-row subscription `EXISTS` is a
cheap index probe, and walking `published_at` does per-feed bitmap scans across many
loops. **No index helps**; the candidate query (without mutes) is already ~58 ms warm.
The user's "not indexed well" hunch was reasonable but the data disproves it.

So the residual costs are NOT indexable:
- **Cold PG buffers** — an instance-RAM limitation (`db-s-1vcpu-1gb`), mitigated by
  Phase 2 (off the critical path) + Phase 4 (warm cache → fewer cold computes).
- **Mute `content_text LIKE`** — only with keyword mutes; reducing it means changing
  mute matching semantics (title-only) — out of scope / a separate decision.

**Phase 3 (3.1 add index) is dropped as counterproductive.** Phase 2 + Phase 4 cover
the real problem.

## Baseline (for before/after)

- Uncached `next_after` / `compute_ranking`: ~180 ms warm-buffer, up to ~4 s cold-buffer.
- Article route otherwise: `find_by_uid` ~20 ms, FTS `Related` ~0.1 ms.
- Target after change: uncached article HTML < 800 ms (achieved trivially once
  `next_after` is off the critical path).
