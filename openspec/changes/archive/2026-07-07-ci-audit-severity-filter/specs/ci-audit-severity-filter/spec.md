## ADDED Requirements

### Requirement: CI dependency audit only fails on HIGH or CRITICAL severity
The `bundle-audit check` step in `.github/workflows/ci.yml` SHALL exit non-zero only when an advisory with severity HIGH or CRITICAL is found. LOW and MEDIUM advisories SHALL be printed to the log but SHALL NOT cause the step to fail.

#### Scenario: HIGH severity advisory found
- **WHEN** `bundle-audit check --update --severity high` finds an advisory rated HIGH
- **THEN** the CI step exits non-zero and the job fails

#### Scenario: CRITICAL severity advisory found
- **WHEN** `bundle-audit check --update --severity high` finds an advisory rated CRITICAL
- **THEN** the CI step exits non-zero and the job fails

#### Scenario: LOW severity advisory found
- **WHEN** `bundle-audit check --update --severity high` finds only LOW severity advisories
- **THEN** the step exits zero, the advisory is visible in the log, and the job continues

#### Scenario: MEDIUM severity advisory found
- **WHEN** `bundle-audit check --update --severity high` finds only MEDIUM severity advisories
- **THEN** the step exits zero, the advisory is visible in the log, and the job continues

#### Scenario: No advisories found
- **WHEN** `bundle-audit check --update --severity high` finds no advisories
- **THEN** the step exits zero and the job continues normally
