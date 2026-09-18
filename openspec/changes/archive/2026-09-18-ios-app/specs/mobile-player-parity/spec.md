## ADDED Requirements

### Requirement: Mini-player supports seek, skip, and variable playback speed
The iOS mini-player SHALL support scrubbing to an arbitrary position, skipping backward 15 seconds and forward 30 seconds (matching the web app's skip amounts), and setting a playback rate from {1×, 1.25×, 1.5×, 1.75×, 2×} (matching the web app's options), with elapsed and total time both visible whenever the current item has a known duration.

#### Scenario: Scrub to a position
- **WHEN** a user drags the mini-player's scrubber to a new position and releases
- **THEN** playback jumps to that position and the elapsed-time label updates

#### Scenario: Skip forward and backward
- **WHEN** a user taps the skip-forward or skip-back control
- **THEN** playback moves 30 seconds forward or 15 seconds backward respectively, clamped to `[0, duration]`

#### Scenario: Change playback speed
- **WHEN** a user selects a different playback speed
- **THEN** subsequent playback uses that rate until changed again

#### Scenario: Live streams have no scrubber
- **WHEN** the current item is a radio station (no known duration)
- **THEN** the mini-player shows an indeterminate playing state instead of a scrubber/skip/speed controls

### Requirement: Playback position resumes locally per episode
The iOS app SHALL remember the last playback position of a podcast episode locally (not synced through the user's account, matching the web app's own `localStorage`-based, per-browser approach) and resume from it the next time that episode is played, unless the stored position is within the last 30 seconds of the episode's duration (in which case playback starts from the beginning, since the episode is effectively finished).

#### Scenario: Resume a partially-played episode
- **WHEN** a user plays an episode, stops partway through, and later plays that same episode again
- **THEN** playback resumes at the previously-reached position

#### Scenario: Don't resume into the tail
- **WHEN** the stored position for an episode is within 30 seconds of its total duration
- **THEN** playback starts from the beginning instead

### Requirement: Backgrounded audio exposes system remote controls
The iOS app SHALL publish Now Playing info (title, elapsed time, duration, rate) to `MPNowPlayingInfoCenter` and register play/pause/skip-backward/skip-forward/scrub commands with `MPRemoteCommandCenter`, so a user can control backgrounded playback from the lock screen, Control Center, CarPlay, or a connected AirPods/headset.

#### Scenario: Lock screen shows now-playing controls
- **WHEN** an episode is playing and the app is backgrounded or the device is locked
- **THEN** the lock screen shows the episode title, elapsed/remaining time, and working play/pause/skip controls

#### Scenario: Remote pause updates in-app state
- **WHEN** a user pauses from the lock screen or a headset button
- **THEN** the in-app mini-player reflects the paused state next time it's visible
