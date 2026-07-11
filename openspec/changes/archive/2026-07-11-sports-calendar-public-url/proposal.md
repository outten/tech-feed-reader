## Why

The existing `/sports/calendar.ics` endpoint sits behind the auth wall, so Apple Calendar, Google Calendar, and other clients that fetch the URL without cookies get redirected to `/sign-in` instead of iCal data. The calendar link on the Sports page is therefore broken for all external subscribers. The fix is a public, user-scoped URL that encodes the user identity in the path rather than in the session.

## What Changes

- Add a new public route `GET /:username/sports/calendar.ics` that returns the user's sports calendar without requiring a session.
- Add `/:username/` as a `PUBLIC_PREFIXES` entry in `app/auth.rb` so the before-filter passes these requests through unauthenticated. (Scoped tightly to the `.ics` suffix in the route itself.)
- Update `GET /sports/calendar` (the HTML view) to display the new URL as the subscribe link instead of `/sports/calendar.ics`.
- Keep the old `/sports/calendar.ics` route in place for backwards compatibility (it still works for logged-in users).

## Capabilities

### New Capabilities

- `sports-calendar-public-url`: A public, username-scoped iCal URL (`/:username/sports/calendar.ics`) that calendar apps can subscribe to without authentication.

### Modified Capabilities

<!-- None — no existing spec covers the sports calendar route. -->

## Impact

- `app/auth.rb` — add public prefix for the username-scoped calendar path.
- `app/main.rb` — add new route; update `@ical_url` in the HTML calendar view.
- `views/sports_calendar.erb` — subscribe link updates automatically via `@ical_url`.
- No database changes, no new gems.

---

**Will this work?** Yes. This is the same pattern used by Google Calendar exports, GitHub iCal feeds, and Fastmail. The username in the URL acts as a non-secret identifier (sports schedules contain no sensitive data). Anyone who knows a username can see their sports calendar — acceptable given the data is just team fixtures. The auth wall is bypassed only for paths matching `/:username/sports/calendar.ics`; all other routes remain protected.
