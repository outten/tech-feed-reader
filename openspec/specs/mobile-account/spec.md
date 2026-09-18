## Requirements

### Requirement: Current-user info and calendar subscription URL
The system SHALL expose `GET /api/v1/account` returning the signed-in user's username, display name, passkey count, and unconsumed recovery-code count, plus the public per-user sports-calendar `.ics` URL.

#### Scenario: Fetch account info
- **WHEN** an authenticated user requests `GET /api/v1/account`
- **THEN** the response is HTTP 200 with their username, display name, and calendar URL

### Requirement: Display name is editable
The system SHALL expose `POST /api/v1/account/display_name` (body `display_name`).

#### Scenario: Update display name
- **WHEN** an authenticated user updates their display name
- **THEN** subsequent `GET /api/v1/account` calls reflect the new value

### Requirement: Recovery codes are regeneratable
The system SHALL expose `POST /api/v1/account/recovery_codes/regenerate`, invalidating all existing codes and returning a fresh batch — shown once, matching the web app's "no way to retrieve them later" design.

#### Scenario: Regenerate
- **WHEN** an authenticated user regenerates their recovery codes
- **THEN** a new batch of codes is returned and the previous batch no longer works for login

### Requirement: Passkeys are listable and revocable, with lockout protection
The system SHALL expose `GET /api/v1/account/passkeys` (list) and `DELETE /api/v1/account/passkeys/:credential_id` (revoke), refusing to delete the last passkey when the user has zero unconsumed recovery codes — matching the web app's lockout protection. Adding a new passkey is not in scope here (see Phase 2).

#### Scenario: List passkeys
- **WHEN** an authenticated user requests `GET /api/v1/account/passkeys`
- **THEN** the response is HTTP 200 with their registered passkeys

#### Scenario: Revoke a passkey with a safety net available
- **WHEN** an authenticated user with recovery codes remaining revokes a passkey
- **THEN** it is removed

#### Scenario: Refuse to revoke the last passkey with no recovery codes
- **WHEN** an authenticated user has exactly one passkey and zero unconsumed recovery codes
- **THEN** revoking it is refused (HTTP 422), preventing a permanent lockout

### Requirement: Account is deletable with typed-username confirmation
The system SHALL expose `DELETE /api/v1/account` (body `confirm_username`), requiring it to match the signed-in user's username exactly, matching the web app's confirmation gate.

#### Scenario: Confirmed deletion
- **WHEN** an authenticated user sends `DELETE /api/v1/account` with `confirm_username` matching their username
- **THEN** their account and all per-user data are deleted

#### Scenario: Mismatched confirmation is refused
- **WHEN** `confirm_username` doesn't match
- **THEN** the account is not deleted (HTTP 400)

### Requirement: iOS app supports account management
The iOS app SHALL let a signed-in user view their account info, edit their display name, regenerate recovery codes, list and revoke passkeys, subscribe to their sports calendar, and delete their account.

#### Scenario: Manage account
- **WHEN** a signed-in user opens the Account screen
- **THEN** they can edit their display name, regenerate recovery codes, and see their passkeys
