# on-air

A macOS menu bar app that dramatically plays a countdown theme before every meeting — complete with a flashing red countdown pill in your menu bar.

Inspired by [this tweet](https://x.com/rtwlz/status/2036082537949434164).

## How it works

1. Reads your upcoming meetings from macOS Calendar via EventKit
2. Shows a compact live countdown like `((•)) 27m` or `((•)) 1:12` in the menu bar
3. Keeps the full meeting title on the first dropdown row and compact metadata like `7:00 AM (11m) · Home` underneath
4. Before the meeting, plays your countdown audio and the menu bar goes red
5. In the final 10 seconds, the red pill flashes
6. After the meeting starts, shows `((•)) LIVE` as a solid red pill for 60 seconds
7. Automatically skips events you've declined or marked as free
8. **Join Meeting** button appears in the dropdown when a video call URL is detected (Teams, Zoom, Google Meet, Webex, or any https:// link as fallback) — click to open it in your browser
9. **Notifications** toggle in the dropdown — opt in to receive a macOS notification when the countdown audio starts, showing the meeting name and time remaining
10. **Test Countdown** menu item lets you verify the full cycle without a real calendar event
11. Works with **any** calendar synced to macOS — Teams, Outlook, Google Calendar, iCloud

## Setup

```bash
git clone https://github.com/charistas/on-air.git
cd on-air
```

### Add your audio file

Place any countdown audio file in the project root as `countdown.mp3`. The BBC News countdown theme works great — search for "BBC News Countdown Theme" to find it. The app auto-detects the audio duration and triggers playback so that it finishes right as the meeting starts.

### Sync your work calendar

For **Teams / Outlook**: System Settings → Internet Accounts → add your Microsoft 365 account with Calendars enabled.

For **Google Calendar**: System Settings → Internet Accounts → add your Google account with Calendars enabled.

### Try it

```bash
bash install.sh              # builds the native app bundle, installs a login item, and runs it
```

`install.sh` compiles a native macOS menu bar app into `OnAir.app`, adds it to Login Items, and launches it. Calendar access belongs to `On Air`, not Terminal. The first launch will prompt for Calendar access — click Allow.

## Configuration

The installed Swift app auto-detects the audio duration and uses built-in defaults. To change timing constants, edit the top of `OnAir.swift` and reinstall:

| Constant | Default | Description |
|---|---|---|
| `countdownVisible` | `120` | Seconds before meeting to show `m:ss` countdown |
| `flashAt` | `10` | Seconds before meeting to start flashing red |
| `liveSeconds` | `60` | Seconds to show LIVE indicator after meeting starts |
| `upcomingWindow` | `7200` | Seconds ahead to look for upcoming meetings |

Audio trigger timing is derived automatically from the `countdown.mp3` duration.

## Uninstall

```bash
bash uninstall.sh
```

This stops the app and removes it from login items.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`swiftc`)

## Troubleshooting

If the app shows `Calendar access needed`, reset the app-specific TCC decision and reinstall:

```bash
tccutil reset Calendar com.on-air.countdown
bash install.sh
```

If you replace `countdown.mp3`, rerun `bash install.sh` so the bundled app resource is refreshed.

Use **Test Countdown** from the menu bar dropdown to verify the full cycle (countdown → audio → flash → LIVE → idle) without waiting for a real meeting.

## License

MIT
