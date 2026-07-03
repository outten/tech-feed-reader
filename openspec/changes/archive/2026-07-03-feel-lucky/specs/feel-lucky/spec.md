## ADDED Requirements

### Requirement: Lucky page serves random cross-type articles
The system SHALL provide a page at `/lucky` that returns up to 50 randomly-selected articles from the signed-in user's subscriptions, with no topic or content-type filter.

#### Scenario: Returns 200 with articles for a user with subscriptions
- **WHEN** a signed-in user with subscribed feeds visits `/lucky`
- **THEN** the response SHALL be HTTP 200 and the body SHALL include article titles

#### Scenario: Each visit returns a different ordering
- **WHEN** `ArticlesStore.random` is called with the same user_id and limit twice
- **THEN** the query SHALL use `ORDER BY RANDOM()` so results are not guaranteed to be identical

#### Scenario: Audio article shows Listen action
- **WHEN** a randomly-selected article has a non-empty `audio_url`
- **THEN** the page SHALL render a "Listen" link to `/article/:uid`

#### Scenario: YouTube video shows Watch action
- **WHEN** a randomly-selected article has no audio_url and its URL contains `youtube.com` or `youtu.be`
- **THEN** the page SHALL render a "Watch" link opening the external URL in a new tab

#### Scenario: Text article shows Read action
- **WHEN** a randomly-selected article has no audio_url and no YouTube URL
- **THEN** the page SHALL render a "Read" link to `/article/:uid`

### Requirement: Dice icon in header
The signed-in header SHALL include a dice icon link to `/lucky`, placed next to the Bus icon, with `data-turbo-prefetch="false"` to prevent hover pre-fetching a wasted roll.

#### Scenario: Icon is active on /lucky
- **WHEN** the user is on `/lucky`
- **THEN** the dice icon link SHALL have the `active` CSS class

#### Scenario: Icon is not pre-fetched on hover
- **WHEN** the layout renders the dice icon link
- **THEN** it SHALL carry `data-turbo-prefetch="false"`
