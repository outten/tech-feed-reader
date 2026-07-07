## Context

`bundler-audit check --update` exits non-zero on any advisory regardless of severity. The `bundle-audit` CLI supports a `--severity` flag (values: `low`, `medium`, `high`, `critical`) that can be used to set the minimum severity level that causes a non-zero exit. Anything below the threshold is still printed to the log but does not fail the step.

Current CI step:
```yaml
- name: Dependency audit (bundler-audit)
  run: bundle exec bundle-audit check --update
```

## Goals / Non-Goals

**Goals:**
- HIGH and CRITICAL advisories fail CI (merge blocked until resolved).
- LOW and MEDIUM advisories are logged but do not block merges.

**Non-Goals:**
- Suppressing or hiding LOW/MEDIUM output — they should still appear in the log for awareness.
- Changing how advisories are resolved or which gems are updated.

## Decisions

**Use `--severity high`** — `bundle-audit` treats severity as a minimum threshold, so `--severity high` matches both HIGH and CRITICAL. This is the single flag change needed.

Alternatives considered:
- `--ignore <CVE>`: per-advisory ignores create maintenance burden and go stale.
- Separate advisory database pinning: over-engineered for this need.

## Risks / Trade-offs

- [Risk] A HIGH/CRITICAL advisory emerges in a gem we can't immediately update → CI blocks as intended; we resolve or add a targeted `--ignore` for that specific CVE with a dated comment.
- [Trade-off] LOW/MEDIUM issues are visible in logs but easy to overlook. Acceptable given they don't represent active exploit risk warranting a merge block.

## Migration Plan

1. Update `.github/workflows/ci.yml` — add `--severity high` to the `bundle-audit check` command.
2. No rollback needed — reverting the flag restores original behaviour.
