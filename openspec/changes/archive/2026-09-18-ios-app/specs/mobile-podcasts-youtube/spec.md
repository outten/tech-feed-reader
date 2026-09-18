## ADDED Requirements

### Requirement: Podcast feeds are listable
The system SHALL expose `GET /api/v1/podcasts` returning the user's subscribed feeds that have at least one audio-enclosure article, with episode count and latest episode date, matching the web app's `/podcasts`.

#### Scenario: List podcast feeds
- **WHEN** an authenticated user with a subscribed podcast feed requests `GET /api/v1/podcasts`
- **THEN** the response is HTTP 200 with that feed, including `episode_count` and `latest_at`

#### Scenario: Non-podcast feeds excluded
- **WHEN** an authenticated user's subscriptions include a feed with no audio-enclosure articles
- **THEN** that feed does not appear in the `GET /api/v1/podcasts` response

### Requirement: YouTube channels are listable
The system SHALL expose `GET /api/v1/youtube/channels` returning the user's subscribed YouTube channel-feeds, with video count and latest video info, matching the web app's `/youtube`.

#### Scenario: List YouTube channels
- **WHEN** an authenticated user with a subscribed YouTube channel feed requests `GET /api/v1/youtube/channels`
- **THEN** the response is HTTP 200 with that channel, including `video_count`, `latest_at`, `latest_uid`, and `latest_url`

### Requirement: iOS app plays podcast episodes natively
The iOS app SHALL let a signed-in user browse their podcast feeds, see episodes (existing article list, filtered to audio-enclosure articles), and play an episode via a persistent native audio player that keeps playing across navigation, mirroring the web app's persistent mini-player.

#### Scenario: Browse podcast feeds and episodes
- **WHEN** a signed-in user opens the Podcasts screen
- **THEN** their podcast feeds are listed; selecting one shows its episodes

#### Scenario: Play an episode, persists across navigation
- **WHEN** a signed-in user starts playing an episode and navigates to a different screen
- **THEN** playback continues and a mini-player remains visible/controllable

### Requirement: iOS app embeds YouTube video playback
The iOS app SHALL let a signed-in user browse their YouTube channels, see videos, and play a video via an embedded YouTube player on the article detail screen, matching the web app's iframe embed on `/article/:uid`.

#### Scenario: Browse channels and videos
- **WHEN** a signed-in user opens the YouTube screen
- **THEN** their subscribed channels are listed; selecting one shows its videos

#### Scenario: Watch a video
- **WHEN** a signed-in user opens a YouTube video article
- **THEN** an embedded video player is shown instead of the plain article-content renderer
