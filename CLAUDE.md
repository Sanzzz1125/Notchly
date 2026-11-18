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
- `Spotify.swift` (PKCE auth, Keychain, `SpotifyAPI`, `SpotifyTrack`), `Playlists.swift` (`PlaylistService`, `StashStore`), `PlaylistsUI.swift` (bar, picker, Stash manager; used by the notch tab and by Music → Stash in the window).
- `Settings.swift` (sidebar: Music holds Stash / Playlists / Now Playing via `SettingsNav.musicTab`; `SettingsWindow.show(.stash/.playlists/.media)` deep-links), `Onboarding.swift`, `Brand.swift` (menu bar icon), `Prefs.swift` (defaults `P`, `Background`, `Eco`).
- `scripts/`: `make-icon.swift`, `screenshots.sh` + `winshot.swift` + `compose.py`, `package.sh`.

## Rules
- Keychain reads/writes must never run on the main thread (macOS may show a blocking permission prompt after every ad-hoc rebuild). Test mode (`-spotifyAPI` override) keeps tokens in memory.
- Spotify features: opt-in, quiet on success (errors only), no duplicates, only talk to Spotify on a click. Test with `python3 scripts/test-spotify.py` (fake server in `scripts/mock-spotify.py`); never write to the user's real account without asking.
- Never send synthetic key/mouse events to the frontmost app while testing: use `keypid`-style delivery to Notchly only, and move the pointer before clicking.
- No telemetry. Network only for lyrics/artwork (switchable in Settings → Privacy) and the **opt-in, off-by-default** Open-Meteo weather. Anything new that touches the network needs its own opt-in and a PRIVACY.md/README entry.
- Idle CPU must stay ~0%: no repeating timers while closed. Prefer notifications/listeners; any timer needs `tolerance` and must respect `Background.paused` and `Eco.on`.
- Services must not trigger permission prompts at launch; ask from onboarding or an Allow button.
- Only `@StateObject` + `Box<T>` for view state (no `@State`, `@Observable`, `#Preview`).
- Settings sliders that change the island must call `NotchState.preview(.layout/.ears/.motion)` so the effect is visible immediately.
- Motion: use `Motion.open/close/alert/tab` and `Motion.tabTransition`; never hard-code springs. User's chosen style must not be overridden by Eco (only the opt-in `ecoCalmMotion`).
- No nested scroll views in Settings panes (a fixed-height `List` inside a `Form` traps the scroll wheel).
- Never publish a second, fast-changing value from `MediaController`; put per-second data in `PlaybackClock`.

## Testing the UI without touching your settings
Launch `build/Notchly.app/Contents/MacOS/Notchly -factoryDefaults YES -demoMode YES -debugHooks YES -onboarded YES [-panelWidth 660 -bodyHeight 180]`
(arguments are in-memory only). Then `notifyutil -p notchly.debug.open.<tab>` / `.close` / `.alert` / `.pause` / `.resume` / `.settings.<pane>` / `.onboard.<n>`,
and capture with `build/winshot Notchly out.png [title]` (compile `scripts/winshot.swift`). `./scripts/screenshots.sh` does all of this for the docs.
