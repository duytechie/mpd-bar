# MPD Bar

A small, native macOS menu-bar controller for [Music Player Daemon](https://www.musicpd.org/), built with Swift and AppKit. It is designed for Apple silicon and has no third-party dependencies.

The menu-bar item shows the current artist/title and whether MPD is playing, paused, stopped, or unavailable. Its menu provides:

- Previous track
- Play / pause
- Next track
- Current song, elapsed time, duration, and volume
- MPD host, port, and optional password settings

## Requirements

- Apple silicon Mac
- macOS 13 or newer
- Swift 6 (Xcode Command Line Tools is sufficient)
- An MPD server reachable over TCP

## Build and run

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/MPD Bar.app"
```

The app is created at `dist/MPD Bar.app`. It is ad-hoc signed for local use.

MPD Bar connects to `127.0.0.1:6600` by default. Choose **Settings…** from its menu to use another server or password. For development runs, the initial configuration can also come from `MPD_HOST`, `MPD_PORT`, and `MPD_PASSWORD` environment variables.

## Development

```sh
swift run MPDBar
swift test
```

The app uses MPD's native text protocol directly. It opens short-lived TCP connections for status checks and commands, so a disconnected or sleeping MPD server does not block the menu-bar UI.
