## ADDED Requirements

### Requirement: Native clients can obtain a bearer token via existing passkey ceremonies
The system SHALL allow a native client to complete the existing WebAuthn register/login ceremonies (`/api/auth/register/verify`, `/api/auth/login/verify`) and, when the request indicates a native client, receive an opaque bearer token in the JSON response in addition to (not instead of) the existing cookie-session behavior for browser clients.

#### Scenario: Native login issues a token
- **WHEN** a native client completes `/api/auth/login/verify` with the native-client flag set
- **THEN** the response is HTTP 200 with a JSON body containing a bearer `token`
- **THEN** the existing cookie-session behavior for browser clients is unaffected

#### Scenario: Browser login is unchanged
- **WHEN** a browser completes `/api/auth/login/verify` without the native-client flag
- **THEN** the response sets the session cookie exactly as it does today
- **THEN** no bearer token is included in the response body

### Requirement: Bearer token authenticates the JSON API
The system SHALL authenticate `GET/POST /api/v1/*` requests via an `Authorization: Bearer <token>` header, looking up the token against the `api_tokens` table. Requests without a valid token SHALL receive HTTP 401.

#### Scenario: Valid token
- **WHEN** a request to `/api/v1/feeds` includes a valid, unexpired bearer token
- **THEN** the response is HTTP 200 with the token owner's data

#### Scenario: Missing or invalid token
- **WHEN** a request to any `/api/v1/*` route has a missing or invalid bearer token
- **THEN** the response is HTTP 401

### Requirement: Sign-out revokes the token
The system SHALL expose `DELETE /api/v1/session` that deletes the presented token's row from `api_tokens`, immediately invalidating it for future requests.

#### Scenario: Successful sign-out
- **WHEN** an authenticated native client calls `DELETE /api/v1/session`
- **THEN** the response is HTTP 200 (or 204)
- **THEN** subsequent requests using that same token receive HTTP 401

### Requirement: JSON API exposes feeds, subscriptions, articles, and read-state
The system SHALL expose token-authenticated JSON endpoints equivalent to the existing HTML routes' data: subscribed feeds, paginated articles (optionally filtered by feed), a single article by uid, subscribe/unsubscribe, and read/bookmark/archive state changes.

#### Scenario: List subscribed feeds
- **WHEN** an authenticated client requests `GET /api/v1/feeds`
- **THEN** the response is HTTP 200 with a JSON array of the user's subscribed feeds

#### Scenario: List articles for a feed
- **WHEN** an authenticated client requests `GET /api/v1/articles?feed_id=<id>`
- **THEN** the response is HTTP 200 with a JSON array of articles belonging to that feed, paginated

#### Scenario: Fetch a single article
- **WHEN** an authenticated client requests `GET /api/v1/articles/:uid` for an article they can access
- **THEN** the response is HTTP 200 with that article's full content

#### Scenario: Mark an article read
- **WHEN** an authenticated client sends `POST /api/v1/read_state` marking an article as read
- **THEN** the response is HTTP 200
- **THEN** the article's read state for that user is updated, matching what the web app would show

#### Scenario: Subscribe to a feed
- **WHEN** an authenticated client sends `POST /api/v1/subscriptions` for a feed they are not yet subscribed to
- **THEN** the response is HTTP 200/201
- **THEN** the feed appears in a subsequent `GET /api/v1/feeds` call for that user

### Requirement: Feed list includes each feed's current relevance weight
`GET /api/v1/feeds` SHALL include each feed's current per-user weight (from the existing `feed_feedback` weighting used by the For-You ranker), so the client can show it without a second round-trip.

#### Scenario: Default weight
- **WHEN** an authenticated client requests `GET /api/v1/feeds` for a feed they've never up/down-weighted
- **THEN** that feed's `weight` is `1.0`

#### Scenario: Adjusted weight
- **WHEN** an authenticated client has previously up-weighted a feed
- **THEN** that feed's `weight` in the response reflects the adjustment
