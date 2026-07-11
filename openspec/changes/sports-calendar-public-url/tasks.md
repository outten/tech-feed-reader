## 1. Auth bypass

- [x] 1.1 Add `PUBLIC_PATTERNS` array to `app/auth.rb` with regex `%r{\A/[^/]+/sports/calendar\.ics\z}` and update `public_path?` to check it

## 2. New route

- [x] 2.1 Add `GET /:username/sports/calendar.ics` route in `app/main.rb` — look up user by username (404 if not found), call `SportsMatchesStore.upcoming_for_followed_teams` with that user's id, return iCal payload
- [x] 2.2 Update `@ical_url` in `GET /sports/calendar` to use `/:username/sports/calendar.ics` (current signed-in user's username)

## 3. Specs

- [x] 3.1 Add specs to `spec/sports_calendar_spec.rb` (or equivalent) covering: public 200, unknown username 404, HTML page subscribe link, old URL still works for signed-in users
