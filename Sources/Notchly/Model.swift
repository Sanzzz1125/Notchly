import SwiftUI
import AppKit

enum NotchTab: String, CaseIterable, Identifiable {
    case home, tray, clipboard, notes, calendar, reminders, timer, stats, mirror, apps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .tray: return "Tray"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .timer: return "Timer"
        case .stats: return "System"
        case .mirror: return "Mirror"
        case .apps: return "Apps"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .tray: return "tray.and.arrow.down.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .timer: return "timer"
        case .stats: return "cpu"
        case .mirror: return "camera.fill"
        case .apps: return "square.grid.2x2.fill"
        }
    }
    static var ordered: [NotchTab] {
        let saved = P.str("tabOrder").split(separator: ",").compactMap { NotchTab(rawValue: String($0)) }
        var out: [NotchTab] = []
        for t in saved where !out.contains(t) { out.append(t) }
        for t in allCases where !out.contains(t) { out.append(t) }
        return out
    }
    static func saveOrder(_ a: [NotchTab]) {
        UserDefaults.standard.set(a.map { $0.rawValue }.joined(separator: ","), forKey: "tabOrder")
    }
    static var enabled: [NotchTab] {
        ordered.filter { $0 == .home || UserDefaults.standard.bool(forKey: "tab_\($0.rawValue)") }
    }
}

struct IslandAlert: Identifiable {
    let id = UUID()
    var symbol: String
    var tint: Color
    var title: String
    var detail: String = ""
    var level: Double? = nil
    var duration: Double = 2.6
}

enum Motion {
    static var calm: Bool { P.int("motion") == 1 }
    static var open: Animation { calm ? .smooth(duration: 0.45) : .spring(response: 0.46, dampingFraction: 0.8) }
    static var close: Animation { .spring(response: 0.38, dampingFraction: 0.92) }
    static var alert: Animation { calm ? .smooth(duration: 0.35) : .spring(response: 0.38, dampingFraction: 0.68) }
    static var tab: Animation { .spring(response: 0.5, dampingFraction: 0.9) }
}

final class NotchState: ObservableObject {
    static let shared = NotchState()
    @Published var expanded = false
    @Published var tab: NotchTab = .home
    @Published var alert: IslandAlert?
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = false
    @Published var pinned = false
    @Published var forward = true
    func move(_ a: NotchTab, before b: NotchTab) {
        var o = NotchTab.ordered
        guard a != b, let i = o.firstIndex(of: a), let ti = o.firstIndex(of: b) else { return }
        o.remove(at: i)
        var j = o.firstIndex(of: b) ?? o.count
        if i < ti { j += 1 }
        o.insert(a, at: min(j, o.count))
        NotchTab.saveOrder(o)
        withAnimation(Motion.tab) { objectWillChange.send() }
    }
    func go(_ t: NotchTab) {
        let all = NotchTab.enabled
        let a = all.firstIndex(of: tab) ?? 0, b = all.firstIndex(of: t) ?? 0
        forward = b >= a
        withAnimation(Motion.tab) { tab = t }
    }
    private var alertWork: DispatchWorkItem?

    func open(_ t: NotchTab? = nil) {
        if let t = t { tab = t }
        if expanded { return }
        alertWork?.cancel()
        withAnimation(Motion.open) { alert = nil; expanded = true }
        if P.bool("haptics") {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    func close() {
        guard expanded else { return }
        pinned = false
        withAnimation(Motion.close) { expanded = false }
    }
    func toggle() { expanded ? close() : open(NotchTab(rawValue: P.str("defaultTab"))) }

    func post(_ a: IslandAlert) {
        guard !expanded else { return }
        alertWork?.cancel()
        withAnimation(Motion.alert) { alert = a }
        let w = DispatchWorkItem { [weak self] in
            withAnimation(Motion.close) { self?.alert = nil }
        }
        alertWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + a.duration, execute: w)
    }

    var wingActive: Bool {
        (P.bool("mediaWings") && MediaController.shared.isPlaying)
            || TimerStore.shared.running
            || (P.bool("awakeIndicator") && KeepAwake.shared.on)
    }
    /// Shoulder (concave flare) radius for the current presentation.
    var shoulder: CGFloat {
        return 0
    }
    var cornerR: CGFloat {
        if expanded { return CGFloat(P.dbl("cornerRadius")) }
        if alert != nil { return 18 }
        return 10
    }
    var expandedSize: CGSize {
        CGSize(width: CGFloat(P.dbl("panelWidth")), height: notchSize.height + 8 + CGFloat(P.dbl("bodyHeight")))
    }
    var islandSize: CGSize {
        let n = notchSize
        let t = shoulder
        if expanded { return expandedSize }
        if let a = alert {
            return CGSize(width: n.width + 2 * 120 + 2 * t, height: n.height + (a.level != nil || !a.detail.isEmpty ? 22 : 0))
        }
        if wingActive { return CGSize(width: n.width + 2 * CGFloat(P.dbl("earWidth")) + 2 * t, height: n.height) }
        return CGSize(width: n.width, height: n.height)
    }
}
