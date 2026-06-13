# Pre-open-source secret scan — v1.0.0

**Date:** 2026-06-13 · **Scope:** entire git history (324 commits) at the v1.0.0
tag · **Purpose:** confirm no credentials, API keys, private keys, or user data
were ever committed before making the repository public.

**Verdict: CLEAN.** No secrets found anywhere in history. No key rotation and no
history rewrite are required; the repository is safe to publish from a secrets
standpoint.

## What was checked

| Check | Method | Result |
|---|---|---|
| `.env` / `.credentials` ever tracked | `git log --all --diff-filter=A --name-only` | Never committed. Only `.env.example` (a placeholder template) is tracked. |
| Real `API_SPORTS_KEY` value (present in the local `.env`) | grep the value across all `git log -p --all` diffs | 0 matches. |
| Provider/key signatures: `sk-ant-…`, AWS `AKIA…`, GitHub `ghp_…`, Slack `xox…`, `-----BEGIN … PRIVATE KEY-----` | regex over all history diffs | No matches. |
| Env-var assignments with real-looking values (`FINNHUB_API_KEY`, `ANTHROPIC_API_KEY`, `API_SPORTS_KEY`, `SESSION_SECRET`, `ADMIN_PASSWORD`, `DATABASE_URL`, `WEBAUTHN_*`) | regex over all history diffs, excluding `ENV[...]` reads | Only 3 hits, all placeholders/examples: `SESSION_SECRET=replace_with_64_byte_hex`, a docs `DATABASE_URL` with the password redacted as `…`, and a throwaway `postgres://tfr:tfr@…/tfr_dev` example. |
| User data DB / cached feed bodies (`data/app.db`, `*.sqlite`, `data/`) | `git log --all --name-only` | Never committed. |
| Tracked `.env.example` and `app/credentials.rb` | inspect current content | `.env.example` is all placeholders/empty values; `credentials.rb` only `dotenv`-loads `.env`/`.credentials` and reads `ENV` — embeds nothing. |

## Protections already in place

`.gitignore` excludes the secret- and data-bearing paths:

```
.credentials
.env
tmp/
.cache/
data/
```

Secrets are supplied at runtime via `.env` / `.credentials` (dev) and the host's
environment (production); see [`.env.example`](../.env.example) for the full list
of variables.

## Recommended follow-ups

- **Independent confirmation (optional):** run a dedicated scanner before flipping
  the repo public — `gitleaks detect` or `trufflehog git file://.` — for
  entropy-based detection beyond the high-signal patterns above.
- **If a secret is ever committed in future:** rotate the credential first, then
  scrub history (`git filter-repo`) — rotation matters more than the scrub, since
  anything pushed should be assumed captured.
- **Re-run this scan** if substantial history lands before the repo is published.

> Point-in-time audit. The conclusions reflect the repository state at v1.0.0
> (324 commits); they do not cover commits added afterward.
