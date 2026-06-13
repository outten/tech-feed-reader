# Security Policy

## Supported versions

Feeder is an actively developed single-codebase project. Security fixes land on
`main` and ship in the next release; please run a recent version.

| Version | Supported |
|---|---|
| latest `main` / newest release (1.x) | ✅ |
| older tags | ❌ (upgrade to the latest) |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately via GitHub's **[Report a vulnerability](https://github.com/outten/tech-feed-reader/security/advisories/new)**
button (repo → **Security** → **Advisories**). This opens a private channel with
the maintainers. If that isn't available to you, use the in-app **Contact** form
(`/contact`) and say a maintainer should reach out privately — don't include
exploit details there.

When reporting, please include:

- A description of the issue and its impact.
- Steps to reproduce (or a proof of concept).
- Affected version / commit, and any relevant configuration.

**What to expect:** we aim to acknowledge a report within a few days, agree on a
remediation timeline, and credit you in the advisory once a fix is released
(unless you prefer to remain anonymous). Please give us reasonable time to ship a
fix before any public disclosure.

## Scope

In scope: the application code in this repository (auth/passkey flows, the auth
wall, session handling, rate limiting, the LLM quota guard, SQL/queries, output
escaping, the feed-fetch + sanitization pipeline).

Out of scope: vulnerabilities in third-party dependencies (report upstream),
issues that require a compromised host or operator account, and anything specific
to a **self-hosted** deployment's own configuration. Feeder is self-hostable
under AGPL-3.0 — operators are responsible for securing their own instances
(secrets management, TLS, OS patching, network controls).

## Handling secrets

Secrets are supplied at runtime via `.env` / `.credentials` (gitignored) and the
host environment — never committed. See [`.env.example`](.env.example) for the
variable list. If you believe a secret was committed, treat it as compromised:
rotate it first, then scrub history.
