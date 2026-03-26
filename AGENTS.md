# AGENTS.md

## Project overview

`on-air` is a macOS menu bar app that plays a countdown theme before calendar meetings.

The supported runtime is the native Swift app in `OnAir.swift`, built into `OnAir.app` by `install.sh`.

## Current architecture

### Production app

- `OnAir.swift`
- AppKit status item app
- EventKit for calendar access
- AVFoundation for audio playback
- UserNotifications for opt-in meeting notifications
- compact menu bar states:
  - `((•))`
  - `((•)) 27m`
  - `((•)) 1:12`
  - solid red timer pill while audio is playing
  - flashing red timer pill for the final 10 seconds
  - `((•)) LIVE` solid red pill for 60s after meeting start
- quiet rules: skips events with free availability or where the current user declined
- test mode: `Test Countdown` injects a fake meeting to verify the full cycle; works without Calendar access
- dropdown header shows:
  - meeting title
  - compact metadata like `7:00 AM (11m) · Home` or `7:00 AM (LIVE) · Home`
- URL detection: extracts video call URLs from `EKEvent.url`, notes, and location (Teams, Zoom, Meet, Webex; generic https:// fallback). Prioritized: meeting-service `event.url` → meeting-service URLs in notes/location → generic `event.url` → generic URLs in notes/location
- sleep/wake handling via `NSWorkspace.didWakeNotification` — clears stale LIVE state and forces a calendar refetch
- AVFoundation audio playback with `AVAudioPlayerDelegate` for cleanup after natural playback end
- "No audio" indicator in dropdown metadata when `countdown.mp3` is missing
- VoiceOver-accessible dropdown header with tooltip on long meeting titles
- Tooltip on status bar icon distinguishes access-denied from no-meetings idle state
- dropdown actions:
  - `Enable Calendar Access` when relevant — opens System Settings Privacy pane when access is denied
  - `Join Meeting` visible when a meeting URL is detected, hidden otherwise; opens URL in default browser
  - `Stop Audio` always visible, enabled only while audio is playing
  - `Notifications` toggle (off by default) — fires a local notification at audio start with meeting name and time remaining; state persisted via `UserDefaults` key `notificationsEnabled`
  - `Test Countdown`
  - `Quit`

## Critical constraints

### TCC / Calendar access

- Do not use LaunchAgent-based startup — it cannot acquire Calendar TCC permission.
- Do not use a shell-wrapper `.app` that `exec`s another binary — same TCC issue.
- Calendar access must belong to the app bundle identifier `com.on-air.countdown`.
- If Calendar access is broken, the known recovery path is:

```bash
tccutil reset Calendar com.on-air.countdown
bash install.sh
```

### Menu bar UX

- Keep the status item narrow.
- Do not put the meeting title back in the menu bar unless explicitly requested.
- Full context belongs in the dropdown because wide status items disappear on crowded menu bars.
- Avoid width-jumping behavior or progressive width fallbacks unless explicitly requested.

### Install/runtime

- `install.sh` is the canonical way to build and run the app.
- `install.sh` must:
  - build `OnAir.app`
  - copy `countdown.mp3` into the bundle when present
  - remove stale LaunchAgent state
  - ensure a login item exists
  - stop older app instances
  - launch the rebuilt app
- `uninstall.sh` must remove the login item and stop the running app.

## Important files

- `OnAir.swift` — production app logic
- `install.sh` — build/install/launch flow
- `uninstall.sh` — uninstall/stop flow
- `OnAir.app/Contents/Info.plist` — bundle metadata and privacy strings
- `README.md` — user-facing docs
- `CLAUDE.md` — Claude-specific repo notes

## Verification

When changing the Swift app or install flow, run:

```bash
swiftc -parse-as-library OnAir.swift -framework AppKit -framework AVFoundation -framework EventKit -framework UserNotifications -o /tmp/onair-swift-test
bash -n install.sh && bash -n uninstall.sh
bash install.sh
```

Useful runtime checks:

```bash
ps -axo pid,ppid,stat,comm,args | rg 'OnAir.app/Contents/MacOS/OnAir'
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" "select service,client,client_type,auth_value,last_modified from access where client='com.on-air.countdown';"
ls -1t "$HOME/Library/Logs/DiagnosticReports" | sed -n '1,10p'
```

No fresh `OnAir*.ips` crash report after reinstall is a meaningful signal that the app stayed up.

## Editing guidance

- Prefer small, reviewable changes.
- Preserve the compact status-item design unless the user explicitly asks for a different UX.
- Keep user-facing strings concise; menu bar and menu copy have hard space constraints.
- If behavior changes, update `README.md`.
- If architecture/install flow changes, update `README.md`, `CLAUDE.md`, and `AGENTS.md`.

## Environment assumptions

- macOS
- Xcode Command Line Tools installed
- user may have a crowded menu bar
- `countdown.mp3` is user-supplied and may be missing
