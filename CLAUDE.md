# CLAUDE.md

## Project overview

macOS menu bar app that plays a countdown theme before calendar meetings. Built as a native Swift menu bar app (`OnAir.swift`) so Calendar permission attaches to the app bundle via `com.on-air.countdown`.

## Setup

```bash
bash install.sh                  # builds the native app bundle and installs the login item
bash uninstall.sh                # stops app and removes the login item
```

The user must provide their own `countdown.mp3` in the project root (gitignored). `install.sh` copies it into the app bundle for login-item runs.

## Architecture

`OnAir.swift` is a single-file menu bar app built by `install.sh`. It handles:

- EventKit permission requests under the `com.on-air.countdown` bundle identifier
- `Enable Calendar Access` menu action opens System Settings Privacy pane when access is denied
- Audio stops automatically when calendar access is revoked mid-countdown
- Upcoming meeting lookup with a 1-second status bar timer
- Compact menu bar countdown rendering: `((•))`, `((•)) 27m`, `((•)) 1:12`, solid red pill, then flashing red pill
- A two-line dropdown header (`MenuHeaderView`): meeting title on the first line, compact metadata like `7:00 AM (11m) · Home` underneath. VoiceOver-accessible. Tooltip on long titles.
- `Join Meeting` dropdown action with prioritized URL detection: meeting-service `event.url` first, then meeting-service URLs in notes/location, then generic `event.url`, then generic URLs in notes/location. Hidden when no URL is detected or during test mode. Known services: Teams, Zoom, Meet, Webex (via `isMeetingService` helper).
- An always-present `Stop Audio` action that is disabled until audio is playing
- Opt-in `Notifications` toggle: fires a local notification (via `UserNotifications`) when countdown audio starts, showing meeting name and time remaining. Off by default; state persisted in `UserDefaults` key `notificationsEnabled`. Skipped during test mode.
- `Test Countdown` menu item for verifying setup without a real calendar event
- LIVE state: 60-second `((•)) LIVE` red pill after a meeting starts (real or test)
- Quiet rules: skips declined and free-availability events in `fetchNextEvent`
- AVFoundation audio playback with `AVAudioPlayerDelegate` for proper cleanup
- Sleep/wake handling via `NSWorkspace.didWakeNotification` — clears stale LIVE state and forces a calendar refetch
- "No audio" indicator in dropdown metadata when `countdown.mp3` is missing
- Tooltip on the status bar icon distinguishes access-denied from no-meetings state

App states: compact idle dot → compact timer → solid red timer pill while audio plays → flashing red timer pill in the final 10s → `((•)) LIVE` solid red pill for 60s after meeting start → back to idle.

Quiet rules: the app automatically skips events where the user's participation status is declined or the event availability is marked free. Tentative/no-response events are not skipped.

Test mode: `Test Countdown` injects a fake meeting `audioTrigger + 10` seconds in the future, exercising the full countdown → audio → flash → LIVE → idle cycle without needing a real calendar event. Works without Calendar access.

Configuration constants at the top of `OnAir.swift`: `countdownVisible`, `flashAt`, `liveSeconds`, `upcomingWindow`. Audio trigger is auto-detected from the mp3 duration.

## Important Files

- `OnAir.swift` — the menu bar app
- `install.sh` — builds `OnAir.app`, copies `countdown.mp3`, installs the login item, launches the app
- `uninstall.sh` — removes the login item and stops the running app
- `OnAir.app/Contents/Info.plist` — app bundle metadata and Calendar usage strings
- `README.md` — user-facing setup and behavior docs
- `AGENTS.md` — Codex-specific repo notes (equivalent of this file for Codex)

## Verification

For app changes, run:

```bash
swiftc -parse-as-library OnAir.swift -framework AppKit -framework AVFoundation -framework EventKit -framework UserNotifications -o /tmp/onair-swift-test
bash -n install.sh && bash -n uninstall.sh
bash install.sh
```

After reinstalling, confirm there is no fresh crash report in `~/Library/Logs/DiagnosticReports/` and that a live `OnAir.app/Contents/MacOS/OnAir` process exists.

## Known Constraints

- The menu bar surface must stay compact. Wide text labels disappear on crowded menu bars, so full meeting titles belong in the dropdown, not the status bar itself.
- `install.sh` requires Xcode Command Line Tools (`swiftc`).
- If Calendar permission gets wedged, reset with `tccutil reset Calendar com.on-air.countdown` and reinstall.

## Tech stack

- Swift / AppKit / EventKit / AVFoundation / UserNotifications

## Conventions

- Keep the app small and local to `OnAir.swift` unless a split is clearly justified
- No audio files committed (the mp3 is gitignored)
- Concise code, minimal comments — only comment non-obvious logic
- If architecture/install flow changes, update `README.md`, `CLAUDE.md`, and `AGENTS.md`
