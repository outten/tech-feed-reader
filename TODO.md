# TODOs

Informal scratch list of UI / UX / feature ideas. Add new items at the bottom; status moves left → right as work progresses.

**Status lifecycle**: `not implemented` → `in implementation` → `implemented` → `tests` → `merged`

| Stage | Meaning |
|---|---|
| `not implemented` | Idea captured, no code yet. |
| `in implementation` | Code being written; nothing committed. |
| `implemented` | Code written + locally exercised; no tests yet. |
| `tests` | Tests written and passing locally. |
| `merged` | Merged to `main` (with the commit SHA referenced). |

---

## Unified Articles & Podcasts, and UI/UX

**Status: `merged`** — partial scope, in commit `4be54c2`.

The original ask had three parts. After discussion we did the first two and intentionally dropped the third:

- [x] **Visual differentiation between articles and podcasts in the unified `/articles` list.** Each row has a left-gutter glyph: 📄 for articles, 🎧 for podcasts, plus `news-item-{article,podcast}` modifier classes for any future styling fork. The text "PODCAST" badge is gone from list rows (it stays on the article-detail header where it lives in a header context, not a list).
- [x] **Open list rows in a new tab.** The row anchor now carries `target="_blank" rel="noopener"`, so clicking a row opens the article in a new tab and `Cmd-W` returns the user to the list. Turbo respects the `target` attribute, so SPA navigation is unaffected.
- [ ] **Collapse `/podcasts` into `/articles`.** Declined — the show-grid view (one card per subscribed podcast, freshest first) on `/podcasts` is genuinely useful for "what's new from each show today?" and would clutter a unified list. `/articles?kind=podcast` already gives the linear-list view of episodes for users who prefer it.

Tests covering the new icons + open-in-new-tab behaviour live in [spec/podcast_integration_spec.rb](spec/podcast_integration_spec.rb).
