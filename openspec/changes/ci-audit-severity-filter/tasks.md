## 1. Update CI workflow

- [x] 1.1 Add `--severity high` flag to the `bundle-audit check --update` command in `.github/workflows/ci.yml`

## 2. Verify

- [x] 2.1 Confirm CI passes on a branch with no HIGH/CRITICAL advisories (current state should be clean after json gem update)
