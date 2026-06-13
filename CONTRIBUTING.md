# Contributing

> **As of v1.0.0 the MVP is complete and Feeder is open to contributors** (AGPL-3.0). Welcome! Get the shape of the system from [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), then follow the workflow below.

The PR workflow we use for this repo. Follow this for every change that lands on `main`. Inherited verbatim from [t-money-terminal](https://github.com/outten/t-money-terminal); change here only when this project's needs genuinely diverge.

## TL;DR

```bash
git checkout -b outten/TODO-NNN
# ... make changes, write tests, update docs ...
make test                             # must be 0 failures
git add <files>                       # stage explicitly, not -A
git commit -m "..."                   # see commit-message style below
git push -u origin outten/TODO-NNN
gh pr create --base main --head ...   # see PR body template below
# wait for CI green, then:
gh pr merge <N> --rebase --delete-branch
git checkout main && git pull --ff-only origin main && git remote prune origin
```

---

## Prerequisites

- **Ruby 3.4.1** (pinned in `.ruby-version`) + Bundler.
- **PostgreSQL** — the app and the test suite both need a Postgres database. The
  suite requires `TEST_DATABASE_URL` pointing at a *disposable* database (it
  truncates between examples):

  ```bash
  createdb tfr_dev tfr_test            # one-time
  make install                         # bundle install
  make migrate                         # apply db/migrations-postgres/*.sql
  TEST_DATABASE_URL=postgres://localhost/tfr_test make test   # full suite, must be 0 failures
  ```

- **Redis** is needed only to run Sidekiq workers locally (`make redis`, `make sidekiq`), not for the test suite.
- **No external API keys** are required to boot or to run tests. Anthropic / Finnhub keys are optional; features degrade gracefully when unset.

New to the codebase? Start with **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for the system map, then [AGENTS.md](AGENTS.md) for conventions.

---

## 1. Branch off `main`

```bash
git checkout main && git pull --ff-only origin main
git checkout -b outten/TODO-NNN
```

Branch naming: `outten/TODO-NNN` where `NNN` is the next sequential number (latest merged → look at `git log --oneline -10` and increment). One branch per PR; we don't keep long-lived feature branches.

> **External contributors:** fork the repository and open a PR from a branch on your fork (any descriptive branch name is fine — the `outten/…` prefix is the maintainer's convention for direct pushes). Everything else below applies the same.

## 2. Implement

- **Tests are required for new behaviour.** RSpec; tests live in `spec/`.
- **Update the relevant docs in the same PR** ([SPEC.md](SPEC.md), [AGENTS.md](AGENTS.md), README.md — whichever the change touches). The bar is "no doc reads as untrue after this PR." Don't leave docs to be reconciled later.
- **Mind the cache-only render contract** if you touch `/articles`, `/dashboard`, or any feed-fetching path. Page renders MUST NOT fire feed fetches — see [AGENTS.md → Caching architecture](AGENTS.md). The hard assertions live in `spec/articles_perf_spec.rb` once it exists.
- Run `make test` early and often.

## 3. Commit

### Stage explicitly

```bash
git add path/to/file.rb path/to/spec.rb path/to/doc.md
```

**Do not** use `git add -A` or `git add .` — it can sweep in `.credentials`, `data/app.db*`, cached feed bodies, or other private state. (Most of those are in `.gitignore`, but stage explicitly anyway.)

### Commit message style

```
<imperative subject — under ~70 chars>

<blank line>

<per-feature paragraphs describing WHAT and WHY>

<blank line>

Tests: <suite count, e.g. "42/0 (was 38)">.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Notable conventions:
- Lead with the user-facing capability, not the implementation detail.
- For multi-feature PRs, use a top-level paragraph per feature, optionally with sub-bullets.
- Always include a `Tests:` line so reviewers can see the suite-count delta at a glance.
- Always include the `Co-Authored-By: Claude Opus 4.7` line (Claude generated the change).

### One commit per PR (usually)

Most PRs are a single commit. Multiple commits are fine when the PR genuinely splits into independent units (e.g. "add CI workflow" + "tests for new feature"), but don't multi-commit just to track your steps.

### Never

- Force-push to `main`.
- Skip hooks (`--no-verify`).
- Amend a commit that's already pushed unless you control all consumers.
- Commit data files (`.credentials`, `data/app.db*`, cached feed bodies — `.gitignore` should catch all of them).

## 4. Push

```bash
git push -u origin outten/TODO-NNN
```

The `-u` sets upstream tracking so subsequent `git push` / `git pull` default to this branch.

## 5. Open the PR

```bash
gh pr create --base main --head outten/TODO-NNN \
  --title "..." \
  --body "$(cat <<'EOF'
## Summary

<one paragraph + bullets describing what shipped and why>

## Test plan
- [x] `make test` — <suite count>
- [ ] CI passes
- [ ] <user-visible verification step>
- [ ] <user-visible verification step>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

PR body conventions:
- **`## Summary`** — what changed, why. One paragraph or bulleted list. Aim for "a reviewer who reads only this section understands the PR."
- **`## Test plan`** — checklist with one box already checked (`make test` locally) and the rest as manual / CI / smoke-test steps.
- Doc updates explicitly called out in Summary so reviewers can see the docs aren't lagging.
- Trailer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

## 6. CI

`.github/workflows/ci.yml` runs on every PR:
- `bundle install` (cached on `Gemfile.lock`)
- Ruby syntax check on `scripts/*.rb`
- Full RSpec suite

CI is required to be green before merge. If it fails:
- Don't disable / skip the failing test.
- Fix the underlying issue, push the fix to the same branch, CI re-runs automatically.
- If you broke the cache-only render contract, `spec/articles_perf_spec.rb` will tell you exactly which assertion failed.

## 7. Merge

```bash
gh pr merge <N> --rebase --delete-branch
```

We use **rebase merge** to keep `main`'s history linear (matches the existing pattern — see `git log`). `--delete-branch` removes the remote branch on merge.

## 8. Sync local

```bash
git checkout main
git pull --ff-only origin main
git remote prune origin   # drop the deleted-remote-branch ref
```

---

## Releasing (maintainers)

Releases are tag-driven and ship to production via GitHub Actions. From a clean
`main`:

```bash
make deploy-patch   # or deploy-minor / deploy-major
```

This runs the full suite, bumps `VERSION`, commits `chore: release vX.Y.Z`, tags,
and pushes. Pushing the `v*` tag triggers [.github/workflows/deploy.yml](.github/workflows/deploy.yml),
which re-runs the suite, builds a `linux/amd64` image, pushes it to the registry,
and SSH-deploys the host. See [docs/ARCHITECTURE.md §9](docs/ARCHITECTURE.md) and
[DEPLOYMENT.md](DEPLOYMENT.md).

## License of contributions

This project is licensed under **[AGPL-3.0](LICENSE)**. By contributing, you agree
your contributions are licensed under those same terms. Please sign off your
commits to certify the [Developer Certificate of Origin](https://developercertificate.org/):

```bash
git commit -s -m "..."     # adds a Signed-off-by: trailer
```

Be kind in issues, reviews, and discussion — assume good faith and keep it
collaborative.

## Memory-backed workflow rules

These are saved in agent memory so future sessions honour them (inherited from `t-money-terminal` — same rules apply here):

1. **Review before shipping** — pause for explicit user go-ahead before commit / push / PR / merge. Even after green CI. The user can grant batch authority for a specific run ("commit, push, merge when CI is green"); honour the explicit scope but don't extrapolate to future work.
2. **Update relevant docs in each PR** — every PR that changes behaviour updates the touched docs. Don't let them drift.

---

## Where things live

| What | Where |
|---|---|
| Project brief | [SPEC.md](SPEC.md) |
| System architecture + diagrams | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Caching contract / store inventory / gotchas | [AGENTS.md](AGENTS.md) |
| Feature surface / page list | README.md |
| Roadmap (shipped / open / dropped) | SPEC.md tier list + PR history |
| Cache-only render contract enforcer | `spec/articles_perf_spec.rb` |
| CI definition | `.github/workflows/ci.yml` |
| Branch naming + commit style + PR body template | this file |
