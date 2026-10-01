## MODIFIED Requirements

### Requirement: Passkeys are listable and revocable, with lockout protection
The system SHALL expose `GET /api/v1/account/passkeys` (list) and `DELETE /api/v1/account/passkeys/:credential_id` (revoke), refusing to delete the last passkey when the user has zero unconsumed recovery codes — matching the web app's lockout protection. Adding a passkey from the Account screen itself (as opposed to the sign-up registration ceremony, which creates one) is not in scope.

#### Scenario: List passkeys
- **WHEN** an authenticated user requests `GET /api/v1/account/passkeys`
- **THEN** the response is HTTP 200 with their registered passkeys

#### Scenario: Revoke a passkey with a safety net available
- **WHEN** an authenticated user with recovery codes remaining revokes a passkey
- **THEN** it is removed

#### Scenario: Refuse to revoke the last passkey with no recovery codes
- **WHEN** an authenticated user has exactly one passkey and zero unconsumed recovery codes
- **THEN** revoking it is refused (HTTP 422), preventing a permanent lockout
