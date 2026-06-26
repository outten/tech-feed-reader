## MODIFIED Requirements

### Requirement: At least one video per subscribed YouTube channel
The "To watch today" section SHALL show at least one video from each subscribed YouTube channel, using the channel's most recent video even if it was not published today.

#### Scenario: Channel with no video today shows latest historical video
- **GIVEN** a user is subscribed to a YouTube channel
- **AND** that channel has not published any video today
- **AND** the channel has at least one ingested article from a previous date
- **WHEN** the home page loads
- **THEN** the most recent article from that channel SHALL appear in `@today_watching`

#### Scenario: Channel with a video today is not duplicated
- **GIVEN** a user is subscribed to a YouTube channel that published a video today
- **WHEN** the home page loads
- **THEN** that channel's today video appears normally (via the scored window); no additional fallback video from that channel is added

#### Scenario: Multiple channels, some without today's video
- **GIVEN** a user is subscribed to two YouTube channels
- **AND** channel A published a video today; channel B has not published recently
- **WHEN** the home page loads
- **THEN** both channels contribute at least one video to `@today_watching`

#### Scenario: Ten-video cap still enforced
- **GIVEN** today's videos already fill all 10 slots
- **WHEN** the home page loads
- **THEN** no fallback videos are added and `@today_watching` contains exactly 10 videos
