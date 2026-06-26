## ADDED Requirements

### Requirement: Triage title links to in-app article page
On the triage page, the article title SHALL link to `/article/:uid` (the in-app reading view) rather than the external publisher URL. The link SHALL NOT open a new tab.

#### Scenario: Triage title navigates in-app
- **WHEN** a user clicks an article title on the triage page
- **THEN** the browser navigates to `/article/<uid>` within the same tab

#### Scenario: Triage title does not open external URL directly
- **WHEN** the triage page HTML is rendered
- **THEN** no article title `<a>` element SHALL have an `href` pointing to an external URL (http/https)

### Requirement: Triage page exposes a Source link to the original publisher
On the triage page, each article card SHALL include a "Source →" link in the meta row that opens the original publisher URL in a new tab. The link SHALL include `rel="noopener noreferrer"`.

#### Scenario: Source link present and external
- **WHEN** an article has a non-empty URL and is rendered on the triage page
- **THEN** the meta row SHALL contain a link with `target="_blank"` pointing to the article's original URL

#### Scenario: No source link when URL is absent
- **WHEN** an article has no URL
- **THEN** no Source link SHALL appear in the meta row

### Requirement: Triage page removes the "Open in app" link
The "Open in app →" link SHALL be removed from the triage article card meta row. It is redundant once the title links in-app.

#### Scenario: Open in app link absent
- **WHEN** the triage page is rendered
- **THEN** no element with the text "Open in app" SHALL appear in the article card

### Requirement: Digest article titles link to in-app article page
In the digest HTML body (`/digests/:id`), article titles SHALL link to `/article/:uid` rather than the external publisher URL.

#### Scenario: Digest title navigates in-app
- **WHEN** a digest is rendered in the browser
- **THEN** each article title link SHALL have `href="/article/<uid>"`

### Requirement: Digest page exposes a Source link to the original publisher
Each digest item SHALL include a "Source" link in the meta line that opens the original publisher URL in a new tab.

#### Scenario: Digest source link present
- **WHEN** a digest item has a non-empty URL
- **THEN** the item meta SHALL contain a link to the external URL with `target="_blank"`
