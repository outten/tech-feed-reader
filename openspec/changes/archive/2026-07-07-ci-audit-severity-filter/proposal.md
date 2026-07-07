## Why

The GitHub Actions CI pipeline fails on any vulnerability found by `bundler-audit`, including LOW and MEDIUM severity advisories. This blocks merges for low-risk issues that aren't actionable (e.g., CVE-2026-54696 on `json` 2.19.5 was rated Low and only required a gem bump that CI itself was blocking). Only HIGH and CRITICAL vulnerabilities represent genuine merge blockers.

## What Changes

- Update the `bundle-audit check` command in `.github/workflows/ci.yml` to ignore LOW and MEDIUM severity advisories, so only HIGH and CRITICAL findings fail the job.

## Capabilities

### New Capabilities

- `ci-audit-severity-filter`: CI dependency audit step only fails on HIGH or CRITICAL severity vulnerabilities; LOW and MEDIUM are reported but do not block the build.

### Modified Capabilities

<!-- None — no existing spec covers CI audit behavior. -->

## Impact

- `.github/workflows/ci.yml` — one-line change to the `bundle-audit check` command.
- No application code, gems, or runtime behaviour affected.
- LOW/MEDIUM advisories will still appear in the CI log but will no longer cause the job to exit non-zero.
