## Requirements

### Requirement: Articles are filterable by topic
The system SHALL let `GET /api/v1/articles` accept a `topic` query parameter (e.g. `humor`, `npr`, `pbs`), scoping results to articles from feeds in that topic — matching the web app's `/comics`, `/npr`, and `/pbs` pages, which are otherwise just topic-scoped views into the existing catalog-browse and article-list endpoints.

#### Scenario: Filter articles by topic
- **WHEN** an authenticated client requests `GET /api/v1/articles?topic=humor`
- **THEN** the response is HTTP 200 with articles from feeds in that topic only

### Requirement: Radio stations are browsable and followable
The system SHALL expose `GET /api/v1/radio/stations` (the curated station catalog grouped by category, with the user's followed station ids) and `POST`/`DELETE /api/v1/radio/follow` (body/query `station_id`), matching the web app's `/radio`.

#### Scenario: List stations
- **WHEN** an authenticated client requests `GET /api/v1/radio/stations`
- **THEN** the response is HTTP 200 with stations grouped by category and the user's followed station ids

#### Scenario: Follow and unfollow a station
- **WHEN** an authenticated user follows a station and later unfollows it
- **THEN** its id appears in, then disappears from, their followed station ids

### Requirement: iOS app supports Comics, NPR, PBS, and Radio
The iOS app SHALL let a signed-in user browse their subscribed Comics/NPR/PBS content (topic-filtered articles) and browse/follow/play radio stations (native audio playback, reusing the same player as podcasts).

#### Scenario: Browse a topic
- **WHEN** a signed-in user opens the Comics (or NPR, or PBS) screen
- **THEN** recent articles from that topic are shown

#### Scenario: Follow and play a radio station
- **WHEN** a signed-in user follows a radio station and taps play
- **THEN** the station's stream plays via the persistent mini-player
