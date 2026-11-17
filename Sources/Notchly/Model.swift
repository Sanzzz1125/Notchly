import SwiftUI
import AppKit

enum NotchTab: String, CaseIterable, Identifiable {
    case home, tray, clipboard, notes, calendar, reminders, timer, stats, controls, weather, apps, mirror
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
        case .controls: return "Controls"
        case .weather: return "Weather"
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
        case .controls: return "switch.2"
        case .weather: return "cloud.sun.fill"
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
        ordered.filter { $0 == .home || $0.isOn }
    }
    var isOn: Bool { UserDefaults.standard.bool(forKey: "tab_\(rawValue)") }
    var blurb: String {
        switch self {
        case .home: return "Now playing and your next event"
        case .tray: return "Hold files, drag them out, AirDrop"
        case .clipboard: return "History with search and pins"
        case .notes: return "Quick notes that save as you type"
        case .calendar: return "This week at a glance"
        case .reminders: return "Tick off to-dos"
        case .timer: return "Timer, stopwatch, focus sessions"
        case .stats: return "CPU, memory, disk, battery"
        case .controls: return "Dark mode, mute, keep awake, shortcuts"
        case .weather: return "Opt-in forecast (uses the internet)"
        case .apps: return "Launch your favourite apps"
        case .mirror: return "Camera mirror"
        }
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

/// Animation styles. Raw values 0 and 1 match the old "Springy" / "Calm" setting.
enum MotionStyle: Int, CaseIterable, Identifiable {
    case springy = 0, calm = 1, bouncy = 2, snappy = 3, smooth = 4, instant = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .springy: return "Springy"
        case .calm: return "Calm"
        case .bouncy: return "Bouncy"
        case .snappy: return "Snappy"
        case .smooth: return "Smooth"
        case .instant: return "Instant"
        }
    }
    var blurb: String {
        switch self {
        case .springy: return "Lively spring with a soft overshoot (default)."
        case .calm: return "Slow and gentle, no overshoot."
        case .bouncy: return "Playful, clearly overshoots and settles."
        case .snappy: return "Quick and crisp, barely any bounce."
        case .smooth: return "Eased glide, no spring at all."
        case .instant: return "No animation. Best for reduce-motion."
        }
    }
    /// (response, damping) for open, close, alert, tab.
    var springs: [(Double, Double)] {
        switch self {
        case .springy: return [(0.46, 0.80), (0.38, 0.92), (0.38, 0.68), (0.50, 0.90)]
        case .bouncy: return [(0.55, 0.58), (0.42, 0.76), (0.45, 0.48), (0.55, 0.70)]
        case .snappy: return [(0.28, 0.88), (0.24, 0.96), (0.26, 0.78), (0.30, 0.92)]
        default: return []
        }
    }
}

enum TabTransitionStyle: Int, CaseIterable, Identifiable {
    case slide = 0, push = 1, fade = 2, zoom = 3, none = 4
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .slide: return "Slide"
        case .push: return "Push"
        case .fade: return "Fade"
        case .zoom: return "Zoom"
        case .none: return "None"
        }
    }
}

enum Motion {
    static var style: MotionStyle {
        let chosen = MotionStyle(rawValue: P.int("motion")) ?? .springy
        // Your choice always wins, unless you opted in to calmer motion in battery saver (Settings → Battery).
        if Eco.on && P.bool("ecoCalmMotion") && chosen != .instant { return .smooth }
        return chosen
    }
    /// 0.5x (slower) ... 2x (faster)
    static var speed: Double { min(2.5, max(0.4, P.dbl("motionSpeed"))) }
    /// 0 (no overshoot) ... 1 (very bouncy); 0.5 = the style's own feel.
    static var bounce: Double { min(1, max(0, P.dbl("motionBounce"))) }
    static var calm: Bool { style == .calm || style == .smooth || style == .instant }

    private static func make(_ idx: Int, smooth: Double) -> Animation {
        let st = style
        if st == .instant { return .linear(duration: 0.01) }
        if st.springs.isEmpty {   // calm / smooth: eased, bounce slider adds a little spring
            let dur = (st == .calm ? smooth * 1.45 : smooth) / speed
            return bounce > 0.65 ? .spring(response: dur, dampingFraction: max(0.6, 1.0 - (bounce - 0.5) * 0.6)) : .smooth(duration: dur)
        }
        let (r, d) = st.springs[idx]
        return .spring(response: r / speed, dampingFraction: min(1, max(0.32, d - (bounce - 0.5) * 0.5)))
    }
    static var open: Animation { make(0, smooth: 0.45) }
    static var close: Animation { make(1, smooth: 0.38) }
    static var alert: Animation { make(2, smooth: 0.35) }
    static var tab: Animation { make(3, smooth: 0.42) }

    static func tabTransition(forward: Bool) -> AnyTransition {
        switch TabTransitionStyle(rawValue: P.int("tabTransition")) ?? .slide {
        case .slide:
            return .asymmetric(insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                               removal: .offset(x: forward ? -40 : 40).combined(with: .opacity))
        case .push:
            return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                               removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
        case .fade: return .opacity
        case .zoom:
            return .asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .scale(scale: 1.08).combined(with: .opacity))
        case .none: return .identity
        }
    }
}

final class NotchState: ObservableObject {
    static let shared = NotchState()
    @Published var expanded = false
    @Published var tab: NotchTab = .home
    @Published var alert: IslandAlert?
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = false
    @Published var pinned = false
    /// Shows sample ears for a moment so the Ear width setting is visible with nothing playing.
    @Published var earPreview = false
    @Published var forward = true
    var blockSwipe = false
    /// Opened with the keyboard while the pointer is elsewhere: stay open until the pointer visits, or Esc.
    var awaitingPointer = false
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
        blockSwipe = false
        withAnimation(Motion.tab) { tab = t }
    }
    private var alertWork: DispatchWorkItem?

    // MARK: Live preview for Settings
    enum PreviewKind { case layout, ears, motion }
    private var previewWork: [DispatchWorkItem] = []
    private var previewOwnsPin = false

    /// Settings sliders call this so a change is visible immediately: it opens the island (or shows sample ears),
    /// then puts everything back a few seconds after the last change.
    func preview(_ kind: PreviewKind) {
        guard !Background.paused else { return }
        previewWork.forEach { $0.cancel() }
        previewWork = []
        func later(_ t: Double, _ f: @escaping () -> Void) {
            let w = DispatchWorkItem(block: f)
            previewWork.append(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
        }
        func endLayout() {
            if previewOwnsPin { previewOwnsPin = false; pinned = false; close() }
        }
        switch kind {
        case .ears:
            if expanded { endLayout(); close() }
            withAnimation(Motion.alert) { earPreview = true }
            later(2.8) { withAnimation(Motion.close) { self.earPreview = false } }
        case .layout:
            if !expanded { open(.home) } else if tab != .home { go(.home) }
            if !pinned { pinned = true; previewOwnsPin = true }
            later(3.2) { endLayout() }
        case .motion:
            if expanded { endLayout(); pinned = false; close() }
            later(0.45) {
                self.open(.home)
                if !self.pinned { self.pinned = true; self.previewOwnsPin = true }
            }
            later(1.5) { self.go(.tray) }
            later(2.3) { self.go(.home) }
            later(3.1) { endLayout() }
            later(3.7) { self.post(IslandAlert(symbol: "sparkles", tint: P.accent, title: "Motion preview", detail: "Alerts use this too", duration: 1.8)) }
        }
    }

    func open(_ t: NotchTab? = nil, byKeyboard: Bool = false) {
        guard !Background.paused else { return }
        if let t = t { tab = t }
        if expanded { return }
        awaitingPointer = byKeyboard
        alertWork?.cancel()
        withAnimation(Motion.open) { alert = nil; expanded = true }
        if P.bool("haptics") {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    func close() {
        guard expanded else { return }
        pinned = false
        blockSwipe = false
        awaitingPointer = false
        withAnimation(Motion.close) { expanded = false }
    }
    func toggle() {
        if expanded { close(); return }
        open(NotchTab(rawValue: P.str("defaultTab")), byKeyboard: true)
        NotchController.shared.focusPanel()
    }

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
        earPreview
            || (P.bool("mediaWings") && MediaController.shared.isPlaying)
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
