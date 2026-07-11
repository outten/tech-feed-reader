## Context

Current state: `GET /sports/calendar.ics` calls `current_user_id` (from the session) and returns iCal data. The Sinatra `before` filter redirects any unauthenticated request to `/sign-in`, so calendar apps that fetch the URL bare receive a 302 redirect, not iCal data.

`app/auth.rb` has two bypass mechanisms:
- `PUBLIC_PATHS` — exact-match set
- `PUBLIC_PREFIXES` — prefix list (e.g. `/api/auth/`, `/img/`)

The new route needs to be public. The cleanest scope is to add a `PUBLIC_PREFIXES` entry that covers only the calendar path. We can't use a broad `/:username/` prefix (that would exempt too much), so the route itself enforces the `.ics` suffix and the auth exemption is handled by matching `request.path_info` against a regex in `public_path?`, or by making the route itself exempt via a narrower prefix check.

## Goals / Non-Goals

**Goals:**
- `GET /outten/sports/calendar.ics` works without a session cookie.
- The sports calendar HTML page shows the new URL as the subscribe link.
- Requesting a non-existent username returns 404.
- The old `/sports/calendar.ics` continues working for signed-in users.

**Non-Goals:**
- Token-based auth (username-in-URL is sufficient for low-sensitivity data).
- Per-user secret tokens / revocable URLs (future enhancement if needed).
- Changing the iCal payload format.

## Decisions

**Auth bypass via route-level regex in `public_path?`** — add a pattern `%r{\A/[^/]+/sports/calendar\.ics\z}` to a new `PUBLIC_PATTERNS` array in `auth.rb`. This is narrower than a prefix (won't accidentally expose other `/:username/*` paths) and keeps the auth logic in one place.

Alternative considered: add a `before` filter on the specific route that skips the global wall. Rejected — Sinatra's `before` filters run in registration order; a route-level skip is harder to test and easy to break.

**Username lookup** — `UsersStore.find_by_username(username)` (already exists for sign-in). Return 404 if not found.

**`@ical_url` update** — the HTML calendar view already uses `@ical_url` set in the route. Change it to `url("/#{current_username}/sports/calendar.ics")` where `current_username` is a helper that returns the signed-in user's username.

## Risks / Trade-offs

- [Risk] Username enumeration — a 404 vs 200 response reveals whether a username exists. Acceptable: usernames are already visible on the sign-in page and in the app.
- [Trade-off] No revocation mechanism — if a user changes their username (not currently supported), the old URL stops working. Acceptable for now; can add token-based URLs later.
- [Trade-off] `PUBLIC_PATTERNS` regex is a new concept alongside `PUBLIC_PATHS` / `PUBLIC_PREFIXES`. Minor complexity increase; worth it for precision.

## Migration Plan

1. Add `PUBLIC_PATTERNS` + regex to `auth.rb`.
2. Add `GET /:username/sports/calendar.ics` route in `main.rb` (before the dynamic `/:username` catch-all if one exists — check for route ordering conflicts).
3. Update `@ical_url` in `GET /sports/calendar`.
4. Add specs: public access, 404 on unknown username, correct iCal content-type.
