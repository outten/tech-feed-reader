## ADDED Requirements

### Requirement: PBS show detail page exists at /pbs/:feed_id
For each subscribed PBS feed, a detail page SHALL exist at `/pbs/:feed_id` listing all recent episodes/articles for that show.

#### Scenario: Show detail page renders for subscribed PBS feed
- **GIVEN** a user is subscribed to a PBS feed
- **WHEN** they navigate to `/pbs/<feed_id>`
- **THEN** the page returns 200 and displays the show's name and its articles

#### Scenario: Non-PBS feed returns 404
- **GIVEN** a feed with `topic != 'pbs'`
- **WHEN** a user navigates to `/pbs/<feed_id>`
- **THEN** the server returns 404

#### Scenario: Unsubscribed PBS feed returns 404
- **GIVEN** a user is NOT subscribed to a PBS feed
- **WHEN** they navigate to `/pbs/<feed_id>`
- **THEN** the server returns 404

### Requirement: Each article has a context-appropriate action link
Each item on the show detail page SHALL show a primary action link appropriate to its content type.

#### Scenario: Audio episode shows Listen link
- **GIVEN** an article with a non-empty `audio_url`
- **WHEN** rendered on the show detail page
- **THEN** a "Listen" link appears pointing to `/article/:uid`

#### Scenario: YouTube video shows Watch link
- **GIVEN** an article whose URL contains `youtube.com` or `youtu.be`
- **WHEN** rendered on the show detail page
- **THEN** a "Watch" link appears pointing to the external YouTube URL with `target="_blank"`

#### Scenario: Text-only article shows Read link
- **GIVEN** an article with no `audio_url` and no YouTube URL
- **WHEN** rendered on the show detail page
- **THEN** a "Read" link appears pointing to `/article/:uid`

### Requirement: My PBS show names link to the detail page
In the "My PBS" section on `/pbs`, each subscribed show name SHALL be a link to `/pbs/:feed_id`.

#### Scenario: Show title is clickable
- **WHEN** the `/pbs` page renders the "My PBS" section
- **THEN** each show name SHALL be an `<a>` element linking to `/pbs/<feed_id>`
