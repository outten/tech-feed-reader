## ADDED Requirements

### Requirement: iOS project lives in its own directory
The iOS app SHALL be a self-contained Xcode project at `ios/` in the repository root. No file under `app/`, `views/`, `public/`, or other existing Sinatra app directories SHALL be created or modified to support the iOS app itself.

#### Scenario: Project isolation
- **WHEN** the iOS app is added to the repository
- **THEN** all new iOS-specific files (Xcode project, Swift sources, assets) are under `ios/`
- **THEN** no existing file under `app/`, `views/`, or `public/` is modified as part of adding the iOS app

### Requirement: App supports iPhone and full-screen iPad
The app SHALL run natively on iPhone and iPad, with the iPad build using the full screen (not a scaled iPhone-compatibility layout).

#### Scenario: Runs on iPhone
- **WHEN** the app is launched on an iPhone (device or Simulator)
- **THEN** it presents a layout suited to the iPhone's screen

#### Scenario: Runs full-screen on iPad
- **WHEN** the app is launched on an iPad (device or Simulator)
- **THEN** it presents a native full-screen iPad layout, not an iPhone-sized window

### Requirement: Users can sign up and log in from the iOS app
The app SHALL let a user create a new account (sign-up) or log in to an existing account using the same passkey-based authentication as the web app, so the same account is usable across platforms.

#### Scenario: New user signs up
- **WHEN** a user with no existing account completes sign-up in the iOS app
- **THEN** a new account and passkey are created
- **THEN** the user is signed in and can see their (empty) feeds

#### Scenario: Existing web user logs in on iOS
- **WHEN** a user who already has an account and passkey from the web app logs in on the iOS app
- **THEN** they are signed in to the same account
- **THEN** their existing feed subscriptions, articles, and read-state are visible in the app

### Requirement: App displays the signed-in user's feeds and articles
Once signed in, the app SHALL display the user's subscribed feeds and their articles, sourced from the mobile JSON API.

#### Scenario: Viewing feeds after sign-in
- **WHEN** a signed-in user opens the app
- **THEN** their subscribed feeds are listed
- **THEN** selecting a feed shows its articles

### Requirement: App runs locally for development
The app SHALL be runnable in the Xcode Simulator against a locally running dev server (`make run`/`make serve`), without requiring a production deployment.

#### Scenario: Local run against dev server
- **WHEN** a developer runs the iOS app in the Simulator with the local dev server running on `http://localhost:4567`
- **THEN** the app successfully signs in and loads feed/article data from that local server
