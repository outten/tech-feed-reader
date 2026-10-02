## ADDED Requirements

### Requirement: Production domain serves an apple-app-site-association file
The system SHALL expose `GET /.well-known/apple-app-site-association` (no auth required) returning a JSON body declaring the iOS app's Team ID + bundle ID under the `webcredentials` service, so iOS can establish Associated Domains trust between the app and the production domain.

#### Scenario: AASA file is fetchable and well-formed
- **WHEN** a client requests `GET /.well-known/apple-app-site-association`
- **THEN** the response is HTTP 200 with `Content-Type: application/json`
- **THEN** the body's `webcredentials.apps` array contains exactly one entry matching `<team id>.<bundle id>`

#### Scenario: AASA route requires no authentication
- **WHEN** the request carries no session cookie or bearer token
- **THEN** the response is still HTTP 200 (not redirected to sign-in, not 401)

### Requirement: iOS app registers a passkey natively via Associated Domains
The iOS app SHALL perform passkey registration using `ASAuthorizationPlatformPublicKeyCredentialProvider`, scoped to the Associated Domains relying party, calling the existing `POST /api/auth/register/options` / `register/verify` endpoints — the same ceremony and relying party the web app already uses.

#### Scenario: New user signs up natively
- **WHEN** a user with no existing account completes native passkey registration in the iOS app
- **THEN** a new account and passkey are created via the existing registration ceremony
- **THEN** the response's one-time recovery codes are shown to the user once
- **THEN** the user is signed in with a bearer token, matching the native-client token-issuance behavior already in place

#### Scenario: User cancels the system passkey sheet
- **WHEN** a user dismisses the native passkey creation sheet without completing it
- **THEN** sign-up is not completed and the app shows a retryable state, not a crash or a hang

### Requirement: iOS app logs in natively via a shared passkey
The iOS app SHALL perform passkey login using `ASAuthorizationPlatformPublicKeyCredentialProvider`'s discoverable-credential request (no username required), calling the existing `POST /api/auth/login/options` / `login/verify` endpoints.

#### Scenario: Existing web user logs in natively on iOS
- **WHEN** a user who already registered a passkey via the web app chooses "Sign in with Passkey" on iOS
- **THEN** the system passkey picker shows their existing passkey (synced via iCloud Keychain)
- **THEN** completing the ceremony signs them into their existing account with a bearer token

#### Scenario: User cancels the system passkey picker
- **WHEN** a user dismisses the native passkey picker without selecting a credential
- **THEN** login is not completed and the app returns to the sign-in screen without crashing or hanging

### Requirement: Recovery-code login remains available as a fallback
The iOS app SHALL continue to offer recovery-code login (`POST /api/auth/recovery` with `native: true`) alongside native passkey login, since it is the only login path available in local development (no Associated Domains over `http://localhost`) and the only account-recovery path when a passkey is unavailable.

#### Scenario: Recovery code still works after native passkey login ships
- **WHEN** a user enters a valid, unconsumed recovery code
- **THEN** they are signed in exactly as before, unaffected by the native passkey login addition
