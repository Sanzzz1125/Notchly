import SwiftUI
import AppKit
import EventKit

/// Sample data for screenshots / docs. `defaults write com.sanketh.Notchly demoMode -bool true`
enum Demo {
    static var on: Bool { P.bool("demoMode") }
}

// MARK: Calendar

struct CalEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
    var location: String = ""
}

enum Access { case unknown, granted, denied }

final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let store = EKEventStore()
    @Published var events: [CalEvent] = []      // selected day
    @Published var upcomingList: [CalEvent] = []
    @Published var busyDays = Set<Date>()
    @Published var day = Date()
    @Published var access: Access = .unknown
    var authorized: Bool { access == .granted }
    private var week: [CalEvent] = []
    private var alerted = Set<String>()

    func start() {
        if Demo.on { access = .granted; loadDemo(); return }
        syncStatus()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
    }
    private func syncStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted; refresh()
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            DispatchQueue.main.async { self?.access = ok ? .granted : .denied; self?.refresh() }
        }
    }
    func select(_ d: Date) { day = d; filter() }
    func refresh() {
        guard authorized, !Demo.on else { return }
        let cal = Calendar.current
        let s = cal.startOfDay(for: Date())
        guard let e = cal.date(byAdding: .day, value: 8, to: s) else { return }
        week = store.events(matching: store.predicateForEvents(withStart: s, end: e, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .map { CalEvent(id: ($0.eventIdentifier ?? $0.title ?? "") + "\($0.startDate.timeIntervalSince1970)", title: $0.title ?? "Event",
                            start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, color: Color(nsColor: $0.calendar.color),
                            location: $0.location ?? "") }
        filter()
    }
    private func filter() {
        let cal = Calendar.current
        events = week.filter { cal.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > cal.startOfDay(for: day) && !cal.isDate($0.end, inSameDayAs: cal.startOfDay(for: day))) }
        let now = Date()
        upcomingList = week.filter { $0.end > now }
        busyDays = Set(week.map { cal.startOfDay(for: $0.start) })
    }
    private func tick() {
        if Background.paused { return }
        guard authorized, P.bool("calendarAlerts") else { return }
        refresh()
        let now = Date()
        for ev in week where !ev.allDay && ev.start > now && ev.start < now.addingTimeInterval(300) {
            if alerted.contains(ev.id) { continue }
            alerted.insert(ev.id)
            let mins = max(1, Int(ev.start.timeIntervalSinceNow / 60))
            NotchState.shared.post(IslandAlert(symbol: "calendar", tint: ev.color, title: ev.title, detail: "Starts in \(mins) min", duration: 5))
        }
    }
    private func loadDemo() {
        let c = Calendar.current
        let now = Date()
        let base = c.date(bySetting: .second, value: 0, of: now) ?? now
        func in_(_ mins: Int) -> Date { base.addingTimeInterval(Double(mins) * 60) }
        let tomorrow = c.startOfDay(for: now.addingTimeInterval(86400))
        func tm(_ h: Int, _ m: Int = 0) -> Date { tomorrow.addingTimeInterval(Double(h * 3600 + m * 60)) }
        let col = { (h: String) in Color(hex: h) }
        week = [
            CalEvent(id: "1", title: "Design review", start: in_(-10), end: in_(50), allDay: false, color: col("#BF5AF2")),
            CalEvent(id: "2", title: "Lunch with Maya", start: in_(120), end: in_(180), allDay: false, color: col("#30D158")),
            CalEvent(id: "3", title: "Ship v1.2", start: in_(300), end: in_(330), allDay: false, color: col("#0A84FF")),
            CalEvent(id: "4", title: "Gym", start: tm(7), end: tm(8), allDay: false, color: col("#FF9F0A")),
            CalEvent(id: "5", title: "Team standup", start: tm(9, 30), end: tm(10), allDay: false, color: col("#0A84FF")),
            CalEvent(id: "6", title: "Dentist", start: tm(40, 0), end: tm(41), allDay: false, color: col("#FF375F")),
        ]
        upcomingList = week
        events = week.filter { c.isDateInToday($0.start) }
        busyDays = Set(week.map { c.startOfDay(for: $0.start) })
    }
}

// MARK: Reminders

struct ReminderItem: Identifiable, Hashable {
    let id: String
    var title: String
    var due: Date?
    var list: String = ""
}

final class ReminderService: ObservableObject {
    static let shared = ReminderService()
    private let store = EKEventStore()
    private var raw: [String: EKReminder] = [:]
    @Published var items: [ReminderItem] = []
    @Published var access: Access = .unknown
    var authorized: Bool { access == .granted }

    func start() {
        if Demo.on {
            access = .granted
            let t = Date()
            items = [ReminderItem(id: "1", title: "Reply to Sam about the invoice", due: t),
                     ReminderItem(id: "2", title: "Pick up dry cleaning", due: t),
                     ReminderItem(id: "3", title: "Book flights for June", due: nil),
                     ReminderItem(id: "4", title: "Water the plants", due: nil)]
            return
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted; refresh()
        case .notDetermined: access = .unknown
        default: access = .denied
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }
    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] ok, _ in
            DispatchQueue.main.async { self?.access = ok ? .granted : .denied; self?.refresh() }
        }
    }
    func refresh() {
        guard authorized, !Demo.on else { return }
        var end = Calendar.current.startOfDay(for: Date())
        end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        let pred = P.bool("remindersAll")
            ? store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        store.fetchReminders(matching: pred) { [weak self] rs in
            let list = rs ?? []
            DispatchQueue.main.async {
                guard let self = self else { return }
                var map: [String: EKReminder] = [:]
                self.items = list.map { r in
                    let id = r.calendarItemIdentifier
                    map[id] = r
                    return ReminderItem(id: id, title: r.title ?? "", due: r.dueDateComponents?.date, list: r.calendar.title)
                }
                self.raw = map
            }
        }
    }
    func complete(_ r: ReminderItem) {
        if Demo.on { items.removeAll { $0.id == r.id }; return }
        guard let ek = raw[r.id] else { return }
        ek.isCompleted = true
        try? store.save(ek, commit: true)
        withAnimation(Motion.tab) { items.removeAll { $0.id == r.id } }
        refresh()
    }
    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return }
        if Demo.on { items.insert(ReminderItem(id: UUID().uuidString, title: t, due: nil), at: 0); return }
        let r = EKReminder(eventStore: store)
        r.title = t
        r.calendar = store.defaultCalendarForNewReminders()
        try? store.save(r, commit: true)
        refresh()
    }
}

// MARK: Clipboard

struct ClipItem: Identifiable, Hashable {
    let id: UUID
    var text: String
    var pinned: Bool
    var date: Date
    var app: String
    var isLink: Bool { URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.hasPrefix("http") == true }
}

final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    @Published var items: [ClipItem] = []
    private var count = NSPasteboard.general.changeCount
    private var skip = 0
    private var timer: Timer?

    /// Only pinned snippets are written to disk (UserDefaults). Everything else lives in memory.
    func start() {
        if Demo.on {
            let n = Date()
            items = [ClipItem(id: UUID(), text: "https://notchly.app/getting-started", pinned: true, date: n, app: "Safari"),
                     ClipItem(id: UUID(), text: "hello@studio.example", pinned: true, date: n, app: "Mail"),
                     ClipItem(id: UUID(), text: "The quick brown fox jumps over the lazy dog", pinned: false, date: n, app: "Notes"),
                     ClipItem(id: UUID(), text: "git commit -m \"Polish the island\"", pinned: false, date: n, app: "Terminal"),
                     ClipItem(id: UUID(), text: "#0A84FF", pinned: false, date: n, app: "Figma")]
            return
        }
        let pins = UserDefaults.standard.stringArray(forKey: "clipPins") ?? []
        items = pins.map { ClipItem(id: UUID(), text: $0, pinned: true, date: .distantPast, app: "") }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func check() {
        if Background.paused { return }
        skip += 1
        if Eco.on && skip % 3 != 0 { return }
        let pb = NSPasteboard.general
        if pb.changeCount == count { return }
        count = pb.changeCount
        // Respect password managers: they flag secrets as concealed / transient.
        let types = pb.types?.map { $0.rawValue } ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let wasPinned = items.first { $0.text == s }?.pinned ?? false
        items.removeAll { $0.text == s }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let it = ClipItem(id: UUID(), text: s, pinned: wasPinned, date: Date(), app: app)
        let firstUnpinned = items.firstIndex { !$0.pinned } ?? items.count
        items.insert(it, at: wasPinned ? (items.firstIndex { $0.pinned } ?? 0) : firstUnpinned)
        let limit = max(5, Int(P.dbl("clipLimit")))
        var unpinned = 0
        items = items.filter { if $0.pinned { return true }; unpinned += 1; return unpinned <= limit }
        persist()
    }
    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        count = pb.changeCount
    }
    func togglePin(_ it: ClipItem) {
        guard let i = items.firstIndex(of: it) else { return }
        withAnimation(Motion.tab) {
            var x = items.remove(at: i)
            x.pinned.toggle()
            if x.pinned { items.insert(x, at: 0) }
            else { items.insert(x, at: items.firstIndex { !$0.pinned } ?? items.count) }
        }
        persist()
    }
    func remove(_ it: ClipItem) { withAnimation(Motion.tab) { items.removeAll { $0.id == it.id } }; persist() }
    func clear() { withAnimation(Motion.tab) { items = items.filter { $0.pinned } } }
    private func persist() {
        if Demo.on { return }
        UserDefaults.standard.set(items.filter { $0.pinned }.map { $0.text }, forKey: "clipPins")
    }
}

// MARK: Notes

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var text = ""
    var updated = Date()
    var title: String {
        let l = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return l.isEmpty ? "New note" : l
    }
}

final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published var notes: [Note] = []
    @Published var current: UUID?
    private var saveWork: DispatchWorkItem?

    init() {
        if let d = UserDefaults.standard.data(forKey: "notesData"), let n = try? JSONDecoder().decode([Note].self, from: d), !n.isEmpty {
            notes = n
        } else {
            let old = UserDefaults.standard.string(forKey: "notes") ?? ""   // migrate the single-note v1 format
            notes = [Note(text: old)]
        }
        if Demo.on {
            notes = [Note(text: "Launch checklist\n• Record the demo clip\n• Write release notes\n• Tag v1.2"),
                     Note(text: "Ideas\nGlance-able timers, shelf for screenshots"),
                     Note(text: "Groceries\nOat milk, coffee beans, limes")]
        }
        current = notes.first?.id
    }
    var selected: Note? { notes.first { $0.id == current } }
    func binding(_ id: UUID) -> Binding<String> {
        Binding(get: { self.notes.first { $0.id == id }?.text ?? "" },
                set: { v in
                    if let i = self.notes.firstIndex(where: { $0.id == id }) {
                        self.notes[i].text = v; self.notes[i].updated = Date(); self.scheduleSave()
                    }
                })
    }
    func add() {
        let n = Note()
        withAnimation(Motion.tab) { notes.insert(n, at: 0); current = n.id }
        scheduleSave()
    }
    func delete(_ id: UUID) {
        withAnimation(Motion.tab) {
            notes.removeAll { $0.id == id }
            if notes.isEmpty { notes = [Note()] }
            if current == id || !notes.contains(where: { $0.id == current }) { current = notes.first?.id }
        }
        scheduleSave()
    }
    private func scheduleSave() {
        if Demo.on { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, let d = try? JSONEncoder().encode(self.notes) else { return }
            UserDefaults.standard.set(d, forKey: "notesData")
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }
}

// MARK: Custom shortcuts

enum ShortcutKind: String, Codable, CaseIterable, Identifiable {
    case app = "App / File", url = "Website", siri = "Shortcuts app", shell = "Shell command"
    var id: String { rawValue }
    var hint: String {
        switch self {
        case .app: return "/Applications/Safari.app"
        case .url: return "https://example.com"
        case .siri: return "Name of a shortcut"
        case .shell: return "say hello"
        }
    }
}

struct CustomShortcut: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = "New shortcut"
    var symbol = "bolt.fill"
    var kind: ShortcutKind = .url
    var target = ""
}

final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    @Published var items: [CustomShortcut] = []
    init() {
        if Demo.on {
            items = [CustomShortcut(name: "Mail", symbol: "envelope.fill", kind: .app, target: "/System/Applications/Mail.app"),
                     CustomShortcut(name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", kind: .url, target: "https://github.com"),
                     CustomShortcut(name: "Focus mode", symbol: "moon.fill", kind: .siri, target: "Focus")]
            return
        }
        if let d = UserDefaults.standard.data(forKey: "customShortcuts"), let a = try? JSONDecoder().decode([CustomShortcut].self, from: d) { items = a }
    }
    func save() {
        if Demo.on { return }
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: "customShortcuts") }
    }
    func run(_ s: CustomShortcut) {
        let t = s.target.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        switch s.kind {
        case .app:
            NSWorkspace.shared.open(URL(fileURLWithPath: (t as NSString).expandingTildeInPath))
        case .url:
            if let u = URL(string: t.contains("://") ? t : "https://" + t) { NSWorkspace.shared.open(u) }
        case .siri:
            Shell.run("/usr/bin/shortcuts", ["run", t])
        case .shell:
            Shell.run("/bin/zsh", ["-c", t])
        }
        NotchState.shared.post(IslandAlert(symbol: s.symbol, tint: P.accent, title: s.name, duration: 1.4))
    }
}

enum Shell {
    @discardableResult
    static func run(_ exe: String, _ args: [String], wait: Bool = false) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        if !wait { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Quick toggles

enum QuickAction: String, CaseIterable, Identifiable {
    case focus, dark, awake, mute, screenshot, saver, sleepDisplay, eco
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focus: return "Do Not Disturb"
        case .dark: return "Dark Mode"
        case .awake: return "Keep Awake"
        case .mute: return "Mute"
        case .screenshot: return "Screenshot"
        case .saver: return "Screen Saver"
        case .sleepDisplay: return "Sleep Display"
        case .eco: return "Battery Saver"
        }
    }
    func symbol(on: Bool) -> String {
        switch self {
        case .focus: return on ? "moon.fill" : "moon"
        case .dark: return on ? "circle.lefthalf.filled" : "sun.max.fill"
        case .awake: return on ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .mute: return on ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .screenshot: return "camera.viewfinder"
        case .saver: return "sparkles.tv"
        case .sleepDisplay: return "display"
        case .eco: return on ? "leaf.fill" : "leaf"
        }
    }
    var isToggle: Bool { self == .focus || self == .dark || self == .awake || self == .mute || self == .eco }
    var tint: Color {
        switch self {
        case .focus: return Color(hex: "#7D7AFF")
        case .dark: return Color(hex: "#5E5CE6")
        case .awake: return Color.orange
        case .mute: return Color(hex: "#FF453A")
        case .eco: return Color(hex: "#30B94D")
        default: return P.accent
        }
    }
}

final class QuickActions: ObservableObject {
    static let shared = QuickActions()
    @Published var focusOn = false
    @Published var darkOn = true
    @Published var muted = false

    func isOn(_ a: QuickAction) -> Bool {
        switch a {
        case .focus: return focusOn
        case .dark: return darkOn
        case .awake: return KeepAwake.shared.on
        case .mute: return muted
        case .eco: return P.bool("ecoMode")
        default: return false
        }
    }

    func refresh() {
        darkOn = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        if Demo.on { return }
        DispatchQueue.global(qos: .utility).async {
            let m = MediaController.osa("output muted of (get volume settings)") == "true"
            DispatchQueue.main.async { self.muted = m }
        }
    }

    func perform(_ a: QuickAction) {
        switch a {
        case .focus:
            // macOS has no public Focus API: run the user's Shortcut (Settings → Controls), else open Focus settings.
            let name = P.str("focusShortcut")
            if name.isEmpty {
                if let u = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") { NSWorkspace.shared.open(u) }
            } else {
                Shell.run("/usr/bin/shortcuts", ["run", name])
                focusOn.toggle()
            }
        case .dark:
            let new = !darkOn
            darkOn = new
            DispatchQueue.global(qos: .userInitiated).async {
                _ = MediaController.osa("tell application \"System Events\" to tell appearance preferences to set dark mode to \(new)")
            }
        case .awake:
            KeepAwake.shared.toggle()
            objectWillChange.send()
        case .mute:
            let new = !muted
            muted = new
            DispatchQueue.global(qos: .userInitiated).async { _ = MediaController.osa("set volume output muted \(new)") }
        case .screenshot:
            NotchState.shared.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Shell.run("/usr/sbin/screencapture", ["-ic"]) }
        case .saver:
            NotchState.shared.close()
            Shell.run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case .sleepDisplay:
            NotchState.shared.close()
            Shell.run("/usr/bin/pmset", ["displaysleepnow"])
        case .eco:
            UserDefaults.standard.set(!P.bool("ecoMode"), forKey: "ecoMode")
            objectWillChange.send()
            NotchState.shared.post(IslandAlert(symbol: "leaf.fill", tint: .green, title: P.bool("ecoMode") ? "Battery Saver On" : "Battery Saver Off", duration: 1.6))
        }
    }
}

// MARK: Weather (opt-in, Open-Meteo, no key, no account)

struct WeatherNow: Equatable {
    var temp: Double
    var code: Int
    var hi: Double
    var lo: Double
    var city: String
    var hourly: [(Date, Double, Int)] = []
    static func == (a: WeatherNow, b: WeatherNow) -> Bool { a.temp == b.temp && a.code == b.code && a.city == b.city && a.hi == b.hi && a.lo == b.lo }
    var symbol: String { WeatherNow.symbol(code) }
    var text: String { WeatherNow.text(code) }
    static func symbol(_ c: Int) -> String {
        switch c {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    static func text(_ c: Int) -> String {
        switch c {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }
}

final class WeatherService: ObservableObject {
    static let shared = WeatherService()
    @Published var now: WeatherNow?
    @Published var status = ""
    private var fetched = Date.distantPast
    private var busy = false

    var enabled: Bool { P.bool("weatherEnabled") && P.bool("allowNetwork") }
    var fahrenheit: Bool { P.int("weatherUnit") == 1 }

    func formatted(_ t: Double) -> String { "\(Int(t.rounded()))°" }

    /// Fetches at most every 30 minutes, and only when something asks for it (panel opened).
    func refreshIfNeeded(force: Bool = false) {
        if Demo.on {
            let h = (0..<6).map { (Date().addingTimeInterval(Double($0) * 3600), 19.0 + Double($0) * 0.6, $0 < 3 ? 1 : 0) }
            now = WeatherNow(temp: fahrenheit ? 70 : 21, code: 1, hi: fahrenheit ? 75 : 24, lo: fahrenheit ? 57 : 14, city: "Cupertino", hourly: h)
            return
        }
        guard enabled, !Background.paused, !busy else { return }
        let city = P.str("weatherCity").trimmingCharacters(in: .whitespaces)
        if city.isEmpty { status = "Choose a city in Settings → Privacy"; return }
        if !force && Date().timeIntervalSince(fetched) < 1800 && now != nil { return }
        busy = true
        status = "Loading…"
        geocode(city) { [weak self] lat, lon, name in
            guard let self = self else { return }
            guard let lat = lat, let lon = lon else {
                DispatchQueue.main.async { self.busy = false; self.status = "City not found" }
                return
            }
            self.forecast(lat, lon, name ?? city)
        }
    }

    private func geocode(_ city: String, _ done: @escaping (Double?, Double?, String?) -> Void) {
        if let lat = UserDefaults.standard.object(forKey: "weatherLat") as? Double,
           let lon = UserDefaults.standard.object(forKey: "weatherLon") as? Double,
           UserDefaults.standard.string(forKey: "weatherResolved") == city {
            done(lat, lon, city); return
        }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        URLSession.shared.dataTask(with: c.url!) { d, _, _ in
            if let d = d, let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let r = (j["results"] as? [[String: Any]])?.first,
               let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double {
                UserDefaults.standard.set(lat, forKey: "weatherLat")
                UserDefaults.standard.set(lon, forKey: "weatherLon")
                UserDefaults.standard.set(city, forKey: "weatherResolved")
                done(lat, lon, r["name"] as? String)
            } else { done(nil, nil, nil) }
        }.resume()
    }

    private func forecast(_ lat: Double, _ lon: Double, _ name: String) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)), URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "2"), URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] d, _, _ in
            var out: WeatherNow?
            if let d = d, let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let cur = j["current"] as? [String: Any], let t = cur["temperature_2m"] as? Double, let code = cur["weather_code"] as? Int,
               let daily = j["daily"] as? [String: Any],
               let hi = (daily["temperature_2m_max"] as? [Double])?.first, let lo = (daily["temperature_2m_min"] as? [Double])?.first {
                var hourly: [(Date, Double, Int)] = []
                if let h = j["hourly"] as? [String: Any], let times = h["time"] as? [String], let temps = h["temperature_2m"] as? [Double], let codes = h["weather_code"] as? [Int] {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
                    if let tz = j["timezone"] as? String { f.timeZone = TimeZone(identifier: tz) }
                    for i in 0..<min(times.count, temps.count, codes.count) {
                        if let dt = f.date(from: times[i]), dt >= Date().addingTimeInterval(-1800), hourly.count < 6 { hourly.append((dt, temps[i], codes[i])) }
                    }
                }
                out = WeatherNow(temp: t, code: code, hi: hi, lo: lo, city: name, hourly: hourly)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if let o = out { self.now = o; self.fetched = Date(); self.status = "" } else { self.status = "Weather unavailable" }
            }
        }.resume()
    }
}
