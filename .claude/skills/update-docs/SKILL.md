---
name: update-docs
description: Sweep recent merges and propose precise edits to README.md / AGENTS.md / CLAUDE.md / TODO.md / STUFF.md / SPEC.md so the docs reflect what's actually in main. Run after merging anything substantive. Read-only on code; edits docs only.
---

# Goal

After a feature merges, the docs drift unless someone updates them deliberately. This skill scans recent commits on `main`, classifies what changed, and proposes the minimum edits to keep each doc honest. Output is a set of focused `Edit` tool calls + a one-line summary per file touched.

# Inputs you can rely on

- `git log origin/main --since="<date>" --oneline` — list of recent merges. Default: last 7 days unless the user provides a window.
- `git show <sha> --stat` — file-level diff per merge.
- `gh pr list --state merged --limit 20 --json number,title,body,mergedAt` — PR titles/bodies for context.
- The doc files themselves: read them before editing.

Never invoke `Edit` on code under `app/`, `views/`, `public/`, `spec/`. This skill only edits docs.

# Doc surfaces and what they should reflect

| File | What lives here |
|---|---|
| `README.md` | App identity, getting-started, the pages table (one line per top-level route), the status paragraph at the top |
| `AGENTS.md` | Process, conventions, gotchas, decision log for *how we work* — not feature inventory |
| `CLAUDE.md` | Coding behaviour guardrails (think before coding, simplicity first, etc.). Rarely changes |
| `TODO.md` | Phased feature backlog with `merged` / `tests` / `not started` statuses. Move items between buckets as they ship |
| `STUFF.md` | Inbox of user-filed requests, each numbered. Each item gets a `**Shipped.** …` paragraph when done and the heading `[ ]` flips to `[x]` |
| `SPEC.md` | If it exists, the product north-star / non-goals. Avoid noisy churn — only update when a non-goal changes |

# Procedure

1. **Decide the window.**
   - If the user gave a date / commit / PR number, scope to that.
   - Otherwise: `git log origin/main --since="7 days ago" --pretty='%h %s'`.

2. **Classify each merge.**
   For each commit on main:
   - Skim the subject line and body.
   - Tag it: `feature` | `bugfix` | `refactor` | `docs-only` | `infra`.
   - Skip `docs-only` and pure `refactor` unless they touched a TODO/STUFF item.

3. **Update STUFF.md first** — it's the most user-visible.
   - If a merge resolves a numbered STUFF.md item, flip `[ ]` → `[x]` and append a `**Shipped.** <2–4 sentence summary citing files / behavior / how to test>` paragraph below the original item text.
   - If a merge resolves something *not* yet in STUFF.md (rare; means it was an ad-hoc engineering bundle), skip — STUFF is for user-filed items.

4. **Update TODO.md next.**
   - If the merge was part of a tracked phase (Sports SX, Multi-user A1, etc.), move the phase row from `tests` → `done` and bullet-list the shipped items under it. Reference commit SHA / PR number.
   - If the merge introduced new deferred work, add a follow-up item under the same phase.

5. **Update README.md** when:
   - A new top-level route shipped → add it to the pages table.
   - The status paragraph at the top is now inaccurate (e.g., a major capability is missing from the prose). One-sentence edit.
   - Getting-started commands changed (rare).

6. **Update AGENTS.md** when:
   - A new convention emerged (e.g., new test-running pattern, new branch-naming rule).
   - A gotcha bit us and we want the next agent to know.
   - Skip if the merge was purely feature work.

7. **Leave CLAUDE.md alone** unless an explicit guardrail changed.

8. **Leave SPEC.md alone** unless a non-goal flipped (e.g., we used to say "no real-time push" and shipped some).

# Output format

For each file touched, emit:

```
File: <path>
Change: <one-line summary>
```

Then `Edit` calls. Don't write a separate summary doc — the per-file lines ARE the summary.

# Anti-patterns

- **Don't bulk-list every commit** in CHANGELOG style. Docs aren't a changelog; they're a current-state snapshot.
- **Don't rephrase user prose in STUFF.md**. Preserve the user's original text verbatim; only append the `**Shipped.**` block.
- **Don't speculate.** If a merge is ambiguous (refactor that touched a STUFF item), open the diff and read.
- **Don't update CLAUDE.md based on a feature merge.** CLAUDE is process, not feature inventory.

# When to bail

- No merges in the window → say so and exit. Don't manufacture changes.
- Doc files have uncommitted edits → flag them and ask before editing.
- A merge looks user-facing but doesn't match any STUFF item → flag and ask whether to add a new STUFF item or skip.
