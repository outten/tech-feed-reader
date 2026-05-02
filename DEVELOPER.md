# Developer Guide

This file is kept as a stable entry point for contributors looking for a "developer guide" doc. The actual content has consolidated into:

- **[SPEC.md](SPEC.md)** — project brief: goals, non-goals, data model, page list, roadmap.
- **[AGENTS.md](AGENTS.md)** — architecture, caching contract, store inventory, provider waterfall, common gotchas, project structure, testing notes.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — PR workflow (branch / commit style / tests / CI / merge).
- README.md — feature surface, page list, getting started (TBD as features ship).
- TODO.md — roadmap (shipped + open + dropped) (TBD).

Start with [SPEC.md](SPEC.md) for the why and [AGENTS.md](AGENTS.md) for the how. Everything load-bearing about cache contract and store conventions lives in AGENTS.md.

## Quick reference (target — fill in as features ship)

```bash
make install                      # bundle install
make migrate                      # apply any pending db/migrations/*.sql
make run                          # dev server with rerun auto-reload (auto-migrates on boot)
make test                         # RSpec
make refresh-feeds                # poll every feed in FeedsStore once
make scheduler                    # long-running poller honouring per-feed intervals
```

## Contributing

The full PR workflow (branch naming, commit style, PR body template, CI, rebase-merge) lives in [CONTRIBUTING.md](CONTRIBUTING.md). Inherited verbatim from `t-money-terminal` so the muscle memory carries over.
