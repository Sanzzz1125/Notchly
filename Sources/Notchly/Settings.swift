import SwiftUI
import AppKit
import ServiceManagement

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var pane: Pane = .appearance
}

enum SettingsWindow {
    static var window: NSWindow?
    static func show(_ pane: Pane? = nil) {
        if let p = pane { SettingsNav.shared.pane = p }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Notchly"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", behavior = "Behavior", tabs = "Tabs & Home"
    case alerts = "Live Activities", media = "Media", timer = "Timer", controls = "Controls", shortcuts = "Shortcuts", power = "Battery", privacy = "Privacy", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .behavior: return "hand.tap.fill"
        case .tabs: return "square.grid.2x2.fill"
        case .alerts: return "bell.badge.fill"
        case .media: return "music.note"
        case .timer: return "timer"
        case .controls: return "switch.2"
        case .shortcuts: return "bolt.fill"
        case .power: return "battery.100.bolt"
        case .privacy: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNav.shared
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                    Text("Notchly").font(.system(size: 15, weight: .bold))
                }
                .padding(.bottom, 12).padding(.top, 8)
                ForEach(Pane.allCases) { p in
                    Button { nav.pane = p } label: {
                        HStack(spacing: 8) {
                            Image(systemName: p.symbol).frame(width: 18)
                            Text(p.rawValue)
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(nav.pane == p ? Color.accentColor.opacity(0.9) : Color.clear))
                        .foregroundStyle(nav.pane == p ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 190)
            .background(.ultraThinMaterial)
            Group {
                switch nav.pane {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .behavior: BehaviorPane()
                case .tabs: TabsPane()
                case .alerts: AlertsPane()
                case .media: MediaPane()
                case .timer: TimerPane()
                case .controls: ControlsPane()
                case .shortcuts: ShortcutsPane()
                case .power: PowerPane()
                case .privacy: PrivacyPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(String(format: step < 1 ? "%.2f" : "%.0f", value) + unit)
                .monospacedDigit().frame(width: 56, alignment: .trailing).foregroundStyle(.secondary)
        }
    }
}

struct GeneralPane: View {
    @AppStorage("showMenuIcon") var showMenuIcon = true
    @AppStorage("hotkey") var hotkey = true
    @AppStorage("display") var display = 0
    @AppStorage("haptics") var haptics = true
    @StateObject private var login = Box<Bool>(SMAppService.mainApp.status == .enabled)
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { login.v }, set: { v in
                    do { if v { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                    login.v = SMAppService.mainApp.status == .enabled
                }))
                Toggle("Show menu bar icon", isOn: $showMenuIcon)
            }
            Section("Display") {
                Picker("Show Notchly on", selection: $display) {
                    Text("Built-in / notch display").tag(0)
                    Text("Main display").tag(1)
                }
            }
            Section("Input") {
                Toggle("Global shortcut  ⌥ Space  to open / close", isOn: $hotkey)
                Toggle("Haptic feedback", isOn: $haptics)
            }
        }
    }
}

struct AppearancePane: View {
    @AppStorage("theme") var theme = 0
    @AppStorage("cardStyle") var cardStyle = 0
    @AppStorage("accentHex") var accentHex = "#0A84FF"
    @AppStorage("glassTint") var glassTint = 0.55
    @AppStorage("cornerRadius") var cornerRadius = 30.0
    @AppStorage("earWidth") var earWidth = 46.0
    @AppStorage("panelWidth") var panelWidth = 640.0
    @AppStorage("bodyHeight") var bodyHeight = 170.0
    @AppStorage("motion") var motion = 0
    var body: some View {
        Form {
            Section("Style") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(NotchTheme.all) { th in
                        Button { theme = th.id } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [th.top, th.bottom], startPoint: .top, endPoint: .bottom))
                                    .frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(theme == th.id ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: theme == th.id ? 2.5 : 1))
                                Text(th.name).font(.caption)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Picker("Cards", selection: $cardStyle) {
                    Text("Soft").tag(0)
                    Text("Outline").tag(1)
                    Text("Glossy").tag(2)
                }.pickerStyle(.segmented)
                if theme == 1 { SliderRow(title: "Glass opacity", value: $glassTint, range: 0.2...1, step: 0.05) }
                ColorPicker("Accent colour", selection: Binding(get: { Color(hex: accentHex) }, set: { accentHex = $0.hex }), supportsOpacity: false)
                HStack {
                    ForEach(["#0A84FF", "#BF5AF2", "#FF375F", "#FF9F0A", "#30D158", "#64D2FF"], id: \.self) { h in
                        Button { accentHex = h } label: {
                            Circle().fill(Color(hex: h)).frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.primary.opacity(accentHex == h ? 0.9 : 0), lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section("Size & shape") {
                SliderRow(title: "Panel width", value: $panelWidth, range: 420...900, step: 10, unit: " pt")
                SliderRow(title: "Panel height", value: $bodyHeight, range: 120...280, step: 10, unit: " pt")
                SliderRow(title: "Corner radius", value: $cornerRadius, range: 12...44, step: 1, unit: " pt")
                SliderRow(title: "Side ears (live activity)", value: $earWidth, range: 30...80, step: 1, unit: " pt")
            }
            Section("Motion") {
                Picker("Animation", selection: $motion) {
                    Text("Springy").tag(0)
                    Text("Calm").tag(1)
                }.pickerStyle(.segmented)
            }
        }
    }
}

struct BehaviorPane: View {
    @AppStorage("openMode") var openMode = 0
    @AppStorage("openDelay") var openDelay = 0.15
    @AppStorage("closeDelay") var closeDelay = 0.35
    @AppStorage("collapseOnExit") var collapseOnExit = true
    @AppStorage("gestures") var gestures = true
    @AppStorage("defaultTab") var defaultTab = "home"
    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the notch", selection: $openMode) {
                    Text("On hover").tag(0)
                    Text("On click").tag(1)
                }.pickerStyle(.segmented)
                if openMode == 0 { SliderRow(title: "Hover delay", value: $openDelay, range: 0...1, step: 0.05, unit: " s") }
                Picker("Opens to", selection: $defaultTab) {
                    ForEach(NotchTab.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("Closing") {
                Toggle("Collapse when the pointer leaves", isOn: $collapseOnExit)
                if collapseOnExit { SliderRow(title: "Close delay", value: $closeDelay, range: 0.1...2, step: 0.05, unit: " s") }
            }
            Section("Gestures") {
                Toggle("Swipe left / right with two fingers to switch tabs", isOn: $gestures)
                Text("Drag a file onto the notch to open the Tray. Press Esc to close.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TabsPane: View {
    @AppStorage("homeSide") var homeSide = "calendar"
    @AppStorage("sideWidth") var sideWidth = 210.0
    @StateObject private var order = Box<[NotchTab]>(NotchTab.ordered)
    @AppStorage("clipLimit") var clipLimit = 25.0
    @AppStorage("remindersAll") var remindersAll = false
    var body: some View {
        Form {
            Section("Tabs — drag to reorder, switch off what you don't use (you can also drag icons in the notch)") {
                List {
                    ForEach(order.v) { t in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            Image(systemName: t.symbol).frame(width: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.title)
                                Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if t != .home {
                                Toggle("", isOn: Binding(get: { t.isOn }, set: { UserDefaults.standard.set($0, forKey: "tab_\(t.rawValue)"); order.v = order.v }))
                                    .labelsHidden().toggleStyle(.switch)
                            }
                        }
                    }
                    .onMove { from, to in
                        var o = order.v
                        o.move(fromOffsets: from, toOffset: to)
                        order.v = o
                        NotchTab.saveOrder(o)
                    }
                }
                .frame(height: 380)
            }
            Section("Home") {
                Picker("Widget beside the player", selection: $homeSide) {
                    Text("Calendar").tag("calendar")
                    Text("Reminders").tag("reminders")
                    Text("System stats").tag("stats")
                    Text("Weather").tag("weather")
                    Text("None").tag("none")
                }
                SliderRow(title: "Widget width", value: $sideWidth, range: 150...300, step: 10, unit: " pt")
            }
            Section("Data") {
                SliderRow(title: "Clipboard items kept", value: $clipLimit, range: 5...100, step: 5)
                Toggle("Show all open reminders (not just today)", isOn: $remindersAll)
            }
        }
    }
}

struct ControlsPane: View {
    @AppStorage("focusShortcut") var focus = ""
    var body: some View {
        Form {
            Section("Do Not Disturb") {
                TextField("Name of your Shortcut", text: $focus, prompt: Text("e.g. Toggle Focus"))
                Text("macOS has no public API for Focus. Create a Shortcut in the Shortcuts app (action: Set Focus) and type its name here; the Do Not Disturb tile will run it. Leave empty to open Focus settings instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dark Mode & Mute") {
                Text("These use AppleScript. macOS asks once whether Notchly may control System Events.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var store = ShortcutStore.shared
    var body: some View {
        Form {
            Section("Your shortcuts — shown in the Controls tab") {
                if store.items.isEmpty { Text("No shortcuts yet.").foregroundStyle(.secondary) }
                ForEach($store.items) { $s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: s.symbol).frame(width: 22)
                            TextField("Name", text: $s.name, prompt: Text("Name")).labelsHidden()
                            Picker("", selection: $s.kind) { ForEach(ShortcutKind.allCases) { Text($0.rawValue).tag($0) } }
                                .labelsHidden().frame(width: 130)
                            Button { store.run(s) } label: { Image(systemName: "play.fill") }.help("Test")
                            Button(role: .destructive) { store.items.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }
                        }
                        HStack(spacing: 8) {
                            TextField("SF Symbol", text: $s.symbol, prompt: Text("SF Symbol name")).labelsHidden().frame(width: 150)
                            TextField(s.kind.hint, text: $s.target, prompt: Text(s.kind.hint)).labelsHidden()
                            if s.kind == .app {
                                Button("Choose…") {
                                    let op = NSOpenPanel(); op.allowedContentTypes = [.application, .item]
                                    if op.runModal() == .OK, let u = op.url { s.target = u.path; if s.name == "New shortcut" { s.name = u.deletingPathExtension().lastPathComponent } }
                                }
                            }
                        }
                        .font(.callout)
                    }
                    .padding(.vertical, 4)
                }
                Button { store.items.append(CustomShortcut()) } label: { Label("Add shortcut", systemImage: "plus") }
            }
            Section {
                Text("Shell commands run as you, with your permissions, only when you press the tile. Only add commands you understand.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: store.items) { _, _ in store.save() }
    }
}

struct AlertsPane: View {
    @AppStorage("mediaWings") var mediaWings = true
    @AppStorage("awakeIndicator") var awake = true
    @AppStorage("chargingAlerts") var charging = true
    @AppStorage("lowBatteryAlerts") var low = true
    @AppStorage("levelAlerts") var level = true
    @AppStorage("downloadAlerts") var downloads = false
    @AppStorage("calendarAlerts") var cal = true
    @AppStorage("trackAlerts") var track = true
    var body: some View {
        Form {
            Section("Always-on indicators") {
                Toggle("Music ears (artwork + equalizer)", isOn: $mediaWings)
                Toggle("Keep-awake indicator", isOn: $awake)
            }
            Section("Pop-up alerts") {
                Toggle("Charger plugged / unplugged", isOn: $charging)
                Toggle("Low battery", isOn: $low)
                Toggle("Volume changes", isOn: $level)
                Toggle("New song", isOn: $track)
                Toggle("Calendar event starting", isOn: $cal)
                Toggle("Download finished", isOn: $downloads)
            }
        }
    }
}

struct MediaPane: View {
    @AppStorage("lyrics") var lyrics = true
    @AppStorage("srcMusic") var music = true
    @AppStorage("srcBrowsers") var browsers = true
    @AppStorage("srcVideo") var video = true
    @AppStorage("srcOther") var other = true
    var body: some View {
        Form {
            Section("Show now-playing from") {
                Toggle("Music apps (Spotify, Apple Music, Tidal…)", isOn: $music)
                Toggle("Browsers (YouTube, web players…)", isOn: $browsers)
                Toggle("Video players (VLC, QuickTime, IINA…)", isOn: $video)
                Toggle("Everything else", isOn: $other)
                Text("Turn off a group to hide it from the notch. For music only, leave just the first switch on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Extras") {
                Toggle("Show synced lyrics (lrclib.net)", isOn: $lyrics)
            }
        }
    }
}

struct TimerPane: View {
    @AppStorage("focusMinutes") var focus = 25.0
    @AppStorage("breakMinutes") var brk = 5.0
    @AppStorage("autoBreak") var auto = true
    @AppStorage("timerSound") var sound = true
    var body: some View {
        Form {
            Section("Focus sessions") {
                SliderRow(title: "Focus", value: $focus, range: 5...90, step: 5, unit: " min")
                SliderRow(title: "Break", value: $brk, range: 1...30, step: 1, unit: " min")
                Toggle("Start the next phase automatically", isOn: $auto)
            }
            Section("Alerts") { Toggle("Play a sound when a timer finishes", isOn: $sound) }
        }
    }
}

struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    Text("Notchly").font(.title.bold())
                    Text("A dynamic island for your MacBook notch.").foregroundStyle(.secondary)
                    Button("Test alert") {
                        NotchState.shared.post(IslandAlert(symbol: "sparkles", tint: P.accent, title: "Hello", detail: "Notchly is alive"))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }
}

struct PowerPane: View {
    @AppStorage("ecoMode") var eco = false
    @AppStorage("ecoOnBattery") var ecoBat = true
    @StateObject private var paused = Box<Bool>(Background.paused)
    var body: some View {
        Form {
            Section("Run in background") {
                Toggle("Pause Notchly completely", isOn: Binding(get: { paused.v }, set: { v in
                    NotchController.shared.setPaused(v); paused.v = v
                }))
                Text("Hides the notch and stops all polling, media reading and alerts. Menu bar icon and this window stay available. Resume from the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Battery saver") {
                Toggle("Always use battery saver", isOn: $eco)
                Toggle("Turn on automatically when unplugged", isOn: $ecoBat)
                Text("Battery saver checks the pointer 10× per second instead of 20–30×, slows clipboard / volume / media checks, freezes the equalizer animation and skips lyric downloads.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PrivacyPane: View {
    @AppStorage("allowNetwork") var net = true
    @AppStorage("weatherEnabled") var weather = false
    @AppStorage("weatherCity") var city = ""
    @AppStorage("weatherUnit") var unit = 0
    var body: some View {
        Form {
            Section("Network") {
                Toggle("Allow internet access (lyrics from lrclib.net, Spotify artwork)", isOn: $net)
                Text("Nothing else ever leaves your Mac. There is no analytics, no tracking and no account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Weather (off by default)") {
                Toggle("Show weather (open-meteo.com — sends only your city name)", isOn: $weather).disabled(!net)
                TextField("City", text: $city, prompt: Text("e.g. Cupertino")).disabled(!weather || !net)
                Picker("Units", selection: $unit) { Text("°C").tag(0); Text("°F").tag(1) }.pickerStyle(.segmented).disabled(!weather || !net)
                Text("Open-Meteo needs no account or key. Your city is sent once to look up coordinates, then coordinates are sent to get the forecast. Nothing else, and never your location from the system.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What Notchly can see, and why") {
                Text("• Calendar & Reminders — shown in the notch only; never copied anywhere.\n• Camera — only while the Mirror tab is open.\n• Spotify / Music (Apple Events) — track info and play controls.\n• Now Playing (system) — title, artist and artwork of what is playing.\n• Clipboard — kept in memory only and cleared when you quit. Only snippets you pin are saved on this Mac. Items flagged as secret by password managers are skipped.\n• Downloads folder — only to notice a finished download (optional).")
                    .font(.callout)
                Text("Revoke any of these anytime in System Settings → Privacy & Security.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
