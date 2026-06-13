## Summary

<!-- What changed and why. One paragraph or bullets — a reviewer who reads only
     this section should understand the PR. Call out any doc updates. -->

## Test plan

- [ ] `make test` — <suite count, e.g. 312/0>
- [ ] CI passes
- [ ] <user-visible verification step>

## Checklist

- [ ] Tests added/updated for new behavior
- [ ] Docs updated in this PR (README / SPEC / AGENTS / docs/ as relevant) — "no doc reads as untrue after this PR"
- [ ] Respects the cache-only render contract (page renders don't fire feed fetches) — see [AGENTS.md](../AGENTS.md)
- [ ] Commit signed off (`git commit -s`) per [CONTRIBUTING.md](../CONTRIBUTING.md)

<!-- See CONTRIBUTING.md for branch naming, commit style, and the full workflow. -->
