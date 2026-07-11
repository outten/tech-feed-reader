## ADDED Requirements

### Requirement: Public username-scoped iCal URL
The system SHALL expose `GET /:username/sports/calendar.ics` as a public endpoint that returns the named user's sports calendar in iCal format without requiring an authenticated session.

#### Scenario: Valid username, unauthenticated request
- **WHEN** an unauthenticated client GETs `/outten/sports/calendar.ics`
- **THEN** the response SHALL be HTTP 200 with `Content-Type: text/calendar`
- **THEN** the body SHALL be a valid iCal payload (begins with `BEGIN:VCALENDAR`)

#### Scenario: Unknown username
- **WHEN** an unauthenticated client GETs `/nobody/sports/calendar.ics` and no user named "nobody" exists
- **THEN** the response SHALL be HTTP 404

#### Scenario: Calendar HTML page shows new URL as subscribe link
- **WHEN** a signed-in user visits `/sports/calendar`
- **THEN** the subscribe link SHALL point to `/:username/sports/calendar.ics` (using the signed-in user's username)
- **THEN** the link SHALL NOT point to `/sports/calendar.ics`

#### Scenario: Old URL still works for signed-in users
- **WHEN** a signed-in user GETs `/sports/calendar.ics`
- **THEN** the response SHALL be HTTP 200 with `Content-Type: text/calendar`
