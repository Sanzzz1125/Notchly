# Notchly: notes for Claude Code

macOS 14+ SwiftUI/AppKit notch "dynamic island" app. Swift package, built into an .app by `./build.sh` (ad-hoc signed).

## Build / run
`./build.sh` builds, creates `build/Notchly.app`, compiles `bridge/MediaBridge.m` into the app (system-wide Now Playing) and launches it. Take screenshots with `screencapture` to check the UI.

## Toolchain limits (user has only Command Line Tools, no Xcode)
- No SwiftUI macros: don't use `@State` / `@Observable` / `#Preview`. Use `@StateObject` + `Box<T>` (Prefs.swift) and `ObservableObject`. `@AppStorage`, `@ObservedObject` are fine.

## Layout
- `NotchController.swift`: borderless NSPanel over the notch. **Event-driven** pointer logic (global+local mouse monitors, debounced open/close work items; no idle timer), drag-to-open, swipe gestures, ⌥Space hotkey, pause / screen-sleep, debug hooks.
- `Model.swift`: `NotchState` (expanded/tab/alert), `NotchTab` enum (add tabs here + `Prefs.defaults` `tab_<name>`), `Motion` springs, island sizing.
- `Design.swift`: design system. Use `DS.Space/Radius/Typo/Ink/Fill`, `PressStyle`, `IconButton`, `Chip`, `Segmented`, `DSField`, `Meter`, `EmptyState`, `.card()`. Don't use stock bordered buttons in the island.
- `Shape.swift`: `NotchShape`, `Surface` (themes), `NotchTheme`.
- `RootView.swift`: compact wings, alerts, expanded header (adaptive: narrow moves pin/gear left) + tab strip.
- `Home.swift` (Now Playing card, side widgets), `Tabs.swift` (calendar, reminders, clipboard, notes, timer, stats, apps, controls, weather), `Tray.swift`.
- `Services.swift` (battery via IOKit notification, timer, keep-awake, stats, volume via CoreAudio listener, downloads, tray store), `Data.swift` (calendar/reminders models, clipboard, notes, shortcuts, quick actions, weather, `Demo`), `Media.swift` (MediaRemote via perl bridge + AppleScript fallback, lrclib lyrics, `PlaybackClock`).
- `Settings.swift`, `Onboarding.swift`, `Brand.swift` (menu bar icon), `Prefs.swift` (defaults `P`, `Background`, `Eco`).
- `scripts/`: `make-icon.swift`, `screenshots.sh` + `winshot.swift` + `compose.py`, `package.sh`.

## Rules
- No telemetry. Network only for lyrics/artwork (switchable in Settings → Privacy) and the **opt-in, off-by-default** Open-Meteo weather. Anything new that touches the network needs its own opt-in and a PRIVACY.md/README entry.
- Idle CPU must stay ~0%: no repeating timers while closed. Prefer notifications/listeners; any timer needs `tolerance` and must respect `Background.paused` and `Eco.on`.
- Services must not trigger permission prompts at launch; ask from onboarding or an Allow button.
- Only `@StateObject` + `Box<T>` for view state (no `@State`, `@Observable`, `#Preview`).
- Never publish a second, fast-changing value from `MediaController`; put per-second data in `PlaybackClock`.

## Testing the UI without touching your settings
Launch `build/Notchly.app/Contents/MacOS/Notchly -factoryDefaults YES -demoMode YES -debugHooks YES -onboarded YES [-panelWidth 660 -bodyHeight 180]`
(arguments are in-memory only). Then `notifyutil -p notchly.debug.open.<tab>` / `.close` / `.alert` / `.pause` / `.resume` / `.settings.<pane>` / `.onboard.<n>`,
and capture with `build/winshot Notchly out.png [title]` (compile `scripts/winshot.swift`). `./scripts/screenshots.sh` does all of this for the docs.
