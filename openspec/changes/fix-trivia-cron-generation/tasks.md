## 1. Add content-quality guard to source selection

- [x] 1.1 In `app/games/trivia_store.rb`, add a `MIN_ARTICLE_CHARS` constant (100) and add `LENGTH(content_text) >= $N` to `fetch_source_articles`'s WHERE clause.
- [x] 1.2 Confirm the existing `SOURCE_ARTICLE_LIMIT` (20) and `SOURCE_WINDOW_HOURS` (24) still make sense unchanged — no change expected, just confirm the new filter composes correctly with the existing LIMIT/ORDER BY.

## 2. Alert on failed/skipped generation

- [x] 2.1 In `app/workers/generate_trivia_worker.rb`, add a `Notifier.push` call in the branch where `ensure_today!` returns `nil` (alongside the existing `AppLogger.warn('generate_trivia_skipped', ...)`), mirroring the dedupe/priority pattern used by `app/sidekiq_config.rb`'s dead-job `death_handlers`.
- [x] 2.2 Confirm `NTFY_URL` is configured on the Droplet so this alert actually reaches the operator (check `/opt/app/.env`); if unset, set it per `docs/alerting.md` and verify with the documented test push. **Confirmed unset** — no `NTFY_URL` line at all in `/opt/app/.env`. Left for the user to configure (picking a topic slug + subscribing from their phone isn't something to automate).

## 3. Test coverage

- [x] 3.1 Add a spec to `spec/trivia_spec.rb` (or wherever `TriviaStore`/`fetch_source_articles` is covered) asserting that an article with `content_text` shorter than `MIN_ARTICLE_CHARS` is excluded from `fetch_source_articles`, even when its `published_at` is more recent than other candidates.
- [x] 3.2 Add a spec asserting a normal mix of substantive articles is unaffected by the new filter (regression guard).
- [x] 3.3 Add a spec (or extend an existing `GenerateTriviaWorker` spec) confirming `Notifier.push` fires when `ensure_today!` returns `nil`.

## 4. Verify against the real historical failure

- [x] 4.1 Reproduce the fix against feed 254's actual historical data: query production (read-only) with the corrected `fetch_source_articles` logic against the 07-22/07-23 01:30 UTC cutoff windows and confirm it now selects substantive articles instead of `Three Word Phrase` captions. **Confirmed**: 07-22 01:30 UTC window goes from 345 chars (dominated by 0-length "GISEC GLOBAL"/"Black Hat USA" calendar entries and Three Word Phrase captions) to 60,207 chars of real news (Zelda, military-visuals, Odyssey articles); 07-23 windows recover similarly.
- [x] 4.2 Run `make test` (full suite, per project convention) before pushing. **1742 examples, 0 failures.**

## 5. Ship

- [ ] 5.1 Deploy via `make release-patch` (after explicit go-ahead) — never a manual `docker buildx`/`ssh` deploy.
- [ ] 5.2 Monitor the next scheduled 01:30 UTC production run after deploy and confirm a quiz is generated.
- [ ] 5.3 Update `STUFF.md` with a **Shipped.** statement once the fix is confirmed working in production.
