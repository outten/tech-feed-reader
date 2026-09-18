## Requirements

### Requirement: Triage runs are listable, viewable, and re-runnable
The system SHALL expose `GET /api/v1/triage` (recent runs), `GET /api/v1/triage/:id` (one run, with each must-read/optional/skip entry resolved to its full article), and `POST /api/v1/triage` (trigger a new run, gated by `LlmGuard`), matching the web app's `/triage`.

#### Scenario: List recent runs
- **WHEN** an authenticated user requests `GET /api/v1/triage`
- **THEN** the response is HTTP 200 with their recent triage runs

#### Scenario: View a run with resolved articles
- **WHEN** an authenticated user requests `GET /api/v1/triage/:id` for their own run
- **THEN** the response includes must-read/optional/skip entries, each with the full article attached

#### Scenario: Trigger a new run
- **WHEN** an authenticated user with LLM budget available sends `POST /api/v1/triage`
- **THEN** a new run is generated, stored, and returned

#### Scenario: Trigger denied by budget guard
- **WHEN** an authenticated user without LLM budget available sends `POST /api/v1/triage`
- **THEN** the response is HTTP 429 with the guard's message (not a 500 or a silent empty result)

### Requirement: Digests are listable, viewable, generatable, and summarizable
The system SHALL expose `GET /api/v1/digests` (recent), `GET /api/v1/digests/:id` (one digest), `POST /api/v1/digests` (generate a new one), and `POST /api/v1/digests/:id/summarize` (on-demand Claude summary, cached — a second call doesn't re-spend tokens), matching the web app's `/digests`.

#### Scenario: List and view
- **WHEN** an authenticated user requests `GET /api/v1/digests` then `GET /api/v1/digests/:id` for one of them
- **THEN** both responses are HTTP 200

#### Scenario: Generate a new digest
- **WHEN** an authenticated user sends `POST /api/v1/digests`
- **THEN** a new digest is generated and stored

#### Scenario: Summarize is cached
- **WHEN** an authenticated user summarizes a digest twice
- **THEN** the second call returns the cached summary without calling Claude again

### Requirement: iOS app supports triage and digests
The iOS app SHALL let a signed-in user view and trigger triage runs, and view/generate/summarize digests.

#### Scenario: Run triage
- **WHEN** a signed-in user triggers a triage run
- **THEN** must-read/optional/skip sections show articles with titles

#### Scenario: Summarize a digest
- **WHEN** a signed-in user taps "Summarize" on a digest without one yet
- **THEN** a Claude-generated summary appears
