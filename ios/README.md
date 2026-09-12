# Tech Feed Reader — iOS

Native SwiftUI client for iPhone and iPad. Lives entirely in this
directory — nothing here touches the Sinatra app under `app/`, `views/`,
or `public/`, and nothing there needs to change to build or run this.

See `openspec/changes/ios-app/` (proposal, design, specs, tasks) for the
full plan. Short version of where things stand:

- **Phase 1 (this pass):** native login via a recovery code, sign-up by
  handing off to the existing web `/sign-up` flow in an in-app browser
  sheet. Both get you a bearer token stored in the Keychain, used against
  the new `/api/v1/*` JSON API.
- **Phase 2 (later):** once a production domain + Apple Developer Team ID
  are set up, native passkey sign-up/login replaces the recovery-code
  path — see `openspec/changes/ios-app/design.md` → "Phase scoping".

## Requirements

- Xcode 15+ (built and verified against Xcode 26.6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — this repo doesn't
  commit `TechFeedReader.xcodeproj`; regenerate it from `project.yml`

## Setup

```sh
cd ios
xcodegen generate
open TechFeedReader.xcodeproj
```

## Running locally against the dev server

1. In the repo root, start the backend: `make run` (or `make serve`) — serves on `http://localhost:4567`.
2. In Xcode, run the `TechFeedReader` scheme on an iPhone or iPad Simulator (Debug
   configuration, which is what `xcodegen`'s default scheme uses). Debug builds point at
   `http://localhost:4567` automatically (see `xcconfig/Debug.xcconfig`) and allow local-network
   HTTP via `NSAllowsLocalNetworking` (`Info-Debug.plist` — Release omits this).
3. **Sign up:** tap "New here? Sign up" — this opens the production `/sign-up` page in an
   in-app browser sheet (Phase 1 has no native passkey UI yet). To sign up against your
   *local* server instead, visit `http://localhost:4567/sign-up` directly in Safari, complete
   registration there, and note the recovery codes shown on success.
4. **Log in:** back in the app, enter one of those recovery codes and tap "Log In".
5. You should land on the feed list (empty until you subscribe to something — the existing
   web UI at `http://localhost:4567/feeds` works fine for that against the same account).

## Configuration

- `project.yml` — XcodeGen project spec (target, deployment target iOS 17, `TARGETED_DEVICE_FAMILY = "1,2"` for iPhone + iPad).
- `xcconfig/Debug.xcconfig` / `xcconfig/Release.xcconfig` — `API_BASE_URL` per configuration.
  Release's is a placeholder (`REPLACE-WITH-PRODUCTION-DOMAIN.example`) until Phase 2's
  production domain is known.
- `TechFeedReader/Info-Debug.plist` / `Info-Release.plist` — per-configuration Info.plist
  fragments (Xcode's `GENERATE_INFOPLIST_FILE` merges these with the auto-generated keys in
  `project.yml`'s `settings`). Debug's carries the local-networking ATS exception; Release's
  doesn't.
- Bundle identifier (`com.techfeedreader.ios`) and `bundleIdPrefix` in `project.yml` are
  placeholders — replace once a real one is chosen.

## What's not here yet (Phase 2)

- Associated Domains entitlement + `apple-app-site-association` (needs a production domain
  and Apple Developer Team ID — see the deferred tasks in
  `openspec/changes/ios-app/tasks.md`).
- Native passkey sign-up/login via `ASAuthorizationPlatformPublicKeyCredentialProvider`.
- An app icon (the asset catalog has an empty placeholder slot).
