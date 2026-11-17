# Notchly: notes for Claude Code

macOS 14+ SwiftUI/AppKit notch "dynamic island" app. Swift package, built into an .app by `./build.sh` (ad-hoc signed).

## Build / run
`./build.sh` builds, creates `build/Notchly.app`, compiles `bridge/MediaBridge.m` into the app (system-wide Now Playing) and launches it. Take screenshots with `screencapture` to check the UI.

## Toolchain limits (user has only Command Line Tools, no Xcode)
- No SwiftUI macros: don't use `@State` / `@Observable` / `#Preview`. Use `@StateObject` + `Box<T>` (Prefs.swift) and `ObservableObject`. `@AppStorage`, `@ObservedObject` are fine.

## Layout
- `NotchController.swift`: borderless NSPanel over the notch, pointer polling (hover open/close, drag detection), swipe gestures, hotkey (⌥Space), pause/eco.
- `Model.swift`: `NotchState` (expanded/tab/alert), tabs enum, `Motion` springs, island sizing.
- `Shape.swift`: `NotchShape`, `Surface` (themes), `NotchTheme`.
- `RootView.swift`: compact wings, alerts, expanded header + tab bar. `Tabs.swift`, `Tray.swift`: tab content.
- `Services.swift`, `Media.swift`: battery, calendar, reminders, clipboard, timer, stats, volume, downloads, media (MediaRemote via perl bridge + AppleScript fallback, lrclib lyrics).
- `Settings.swift`: settings window. `Prefs.swift`: defaults (`P`), `Background`, `Eco`.

## Rules
- No telemetry. Network only for lyrics/artwork, switchable in Settings → Privacy.
- Keep it working with idle CPU low; respect `Background.paused` and `Eco.on` in timers.
