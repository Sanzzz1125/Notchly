import SwiftUI
import AppKit
import Carbon.HIToolbox
import notify
import Combine

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { NotchState.shared.close() }
}

enum HotKey {
    static var handler: (() -> Void)?
    private static var ref: EventHotKeyRef?
    private static var installed = false
    static func register() {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                HotKey.handler?()
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        unregister()
        guard P.bool("hotkey") else { return }
        let id = EventHotKeyID(signature: OSType(0x4E544348), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref)
    }
    static func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
    }
}

final class NotchController {
    static let shared = NotchController()
    private let state = NotchState.shared
    private var panel: NotchPanel!
    private var hosting: NSHostingView<RootView>!
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var guardTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastDrag = NSPasteboard(name: .drag).changeCount
    private var scrollAccum: CGFloat = 0
    private var didSwitch = false
    /// After the island closes, hover must leave the notch once before it can re-open (prevents flicker loops).
    private var armed = true

    func start() {
        panel = NotchPanel()
        hosting = NSHostingView(rootView: RootView())
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
            HotKey.register()
        }
        // Sleep / wake: stop all work while the screen is off.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setScreenOff(true) }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setScreenOff(false) }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.setScreenOff(true) }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.setScreenOff(false) }

        installMonitors()

        // The only polling left: a short guard timer while the island is open (catches a missed mouse event).
        state.$expanded.removeDuplicates().sink { [weak self] open in
            guard let self = self else { return }
            if open {
                self.openWork?.cancel(); self.openWork = nil
                self.startGuard()
            } else {
                self.closeWork?.cancel(); self.closeWork = nil
                self.guardTimer?.invalidate(); self.guardTimer = nil
                self.armed = false
                self.panel.ignoresMouseEvents = true
            }
        }.store(in: &cancellables)

        HotKey.handler = { NotchState.shared.toggle() }
        HotKey.register()
        installDebugHooks()
    }

    private var debugTokens: [Int32] = []
    /// Developer hooks for scripted screenshots: `defaults write com.sanketh.Notchly debugHooks -bool true`,
    /// then `notifyutil -p notchly.debug.open.tray`. Local-only (Darwin notifications), off by default.
    private func installDebugHooks() {
        guard P.bool("debugHooks") else { return }
        for t in NotchTab.allCases {
            var tok: Int32 = 0
            notify_register_dispatch("notchly.debug.open.\(t.rawValue)", &tok, DispatchQueue.main) { [weak self] _ in
                self?.state.pinned = true
                if self?.state.expanded == true { self?.state.go(t) } else { self?.state.open(t) }
                self?.state.pinned = true
            }
            debugTokens.append(tok)
        }
        for p in Pane.allCases {
            var t: Int32 = 0
            let name = "notchly.debug.settings." + p.rawValue.lowercased().replacingOccurrences(of: " & ", with: "").replacingOccurrences(of: " ", with: "")
            notify_register_dispatch(name, &t, DispatchQueue.main) { _ in SettingsWindow.show(p) }
            debugTokens.append(t)
        }
        var tok: Int32 = 0
        notify_register_dispatch("notchly.debug.close", &tok, DispatchQueue.main) { [weak self] _ in self?.state.close() }
        debugTokens.append(tok)
        var tp: Int32 = 0
        notify_register_dispatch("notchly.debug.pause", &tp, DispatchQueue.main) { [weak self] _ in self?.setPaused(true) }
        debugTokens.append(tp)
        var tr: Int32 = 0
        notify_register_dispatch("notchly.debug.resume", &tr, DispatchQueue.main) { [weak self] _ in self?.setPaused(false) }
        debugTokens.append(tr)
        var tk: Int32 = 0
        notify_register_dispatch("notchly.debug.keyboard", &tk, DispatchQueue.main) { _ in NotchState.shared.toggle() }
        debugTokens.append(tk)
        var tok2: Int32 = 0
        notify_register_dispatch("notchly.debug.alert", &tok2, DispatchQueue.main) { _ in
            NotchState.shared.post(IslandAlert(symbol: "bolt.fill", tint: .green, title: "Charging", detail: "82%", level: 0.82, duration: 6))
        }
        debugTokens.append(tok2)
    }

    private func targetScreen() -> NSScreen? {
        if P.int("display") == 1 { return NSScreen.main ?? NSScreen.screens.first }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }
        let top = screen.safeAreaInsets.top
        var size = CGSize(width: 160, height: 28)
        let has = top > 0
        if has, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            size = CGSize(width: screen.frame.width - l.width - r.width, height: top)
        } else if has {
            size = CGSize(width: 185, height: top)
        }
        if state.notchSize != size { state.notchSize = size }
        if state.hasNotch != has { state.hasNotch = has }
        let w = max(CGFloat(P.dbl("panelWidth")) + 60, 700)
        let h = size.height + 8 + CGFloat(P.dbl("bodyHeight")) + 40
        let f = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        if panel.frame != f { panel.setFrame(f, display: true) }
    }

    /// Make the panel key so Esc closes it and text fields work after a keyboard open.
    func focusPanel() { panel.makeKey() }

    // MARK: Pause

    func setPaused(_ p: Bool) {
        Background.user = p
        applyPauseState()
    }
    private func setScreenOff(_ off: Bool) {
        Background.screenOff = off
        applyPauseState()
    }
    private func applyPauseState() {
        let off = Background.paused
        MediaController.shared.setPaused(off)
        if off {
            state.close()
            removeMonitors()
            guardTimer?.invalidate(); guardTimer = nil
            panel.orderOut(nil)
        } else {
            reposition()
            panel.orderFrontRegardless()
            installMonitors()
            if state.expanded { startGuard() }
        }
    }

    // MARK: Pointer (event driven: no idle timer)

    private func installMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.evaluate() }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] ev in self?.evaluate(); return ev }) { monitors.append(l) }
        if let sc = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] ev in self?.scroll(ev); return ev }) { monitors.append(sc) }
    }
    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        openWork?.cancel(); openWork = nil
        closeWork?.cancel(); closeWork = nil
    }
    private func startGuard() {
        guardTimer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.evaluate() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        guardTimer = t
    }

    private func pointerInside() -> Bool {
        let m = NSEvent.mouseLocation
        let pf = panel.frame
        // Cheap reject: the island always lives inside the panel frame.
        guard pf.insetBy(dx: -20, dy: -20).contains(m) else { return false }
        let sz = state.islandSize
        let r = NSRect(x: pf.midX - sz.width / 2, y: pf.maxY - sz.height, width: sz.width, height: sz.height)
        let hot = state.expanded ? r.insetBy(dx: -10, dy: -10) : NSRect(x: r.minX - 8, y: r.minY - 6, width: r.width + 16, height: r.height + 12)
        return hot.contains(m)
    }

    private func evaluate() {
        guard !Background.paused, panel != nil else { return }
        let inside = pointerInside()
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if !state.expanded {
            let dpb = NSPasteboard(name: .drag).changeCount
            if !inside {
                armed = true
                openWork?.cancel(); openWork = nil
                if !down { lastDrag = dpb }
                return
            }
            if down && dpb != lastDrag {           // a file is being dragged onto the notch
                lastDrag = dpb
                state.open(.tray)
                return
            }
            if !down { lastDrag = dpb }
            guard P.int("openMode") == 0, !down, armed, openWork == nil else { return }
            let delay = P.dbl("openDelay")
            if delay <= 0.01 { state.open(NotchTab(rawValue: P.str("defaultTab"))); return }
            let w = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.openWork = nil
                if !self.state.expanded, self.armed, self.pointerInside(), NSEvent.pressedMouseButtons & 1 == 0 {
                    self.state.open(NotchTab(rawValue: P.str("defaultTab")))
                }
            }
            openWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        } else {
            if inside { state.awaitingPointer = false }
            let hold = inside || down || state.pinned || state.awaitingPointer || !P.bool("collapseOnExit")
            if hold { closeWork?.cancel(); closeWork = nil; return }
            guard closeWork == nil else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.closeWork = nil
                if self.state.expanded, !self.pointerInside(), !self.state.pinned, !self.state.awaitingPointer,
                   NSEvent.pressedMouseButtons & 1 == 0 {
                    self.state.close()
                }
            }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, P.dbl("closeDelay")), execute: w)
        }
    }

    // MARK: Swipe between tabs

    private func scroll(_ ev: NSEvent) {
        guard state.expanded, P.bool("gestures"), !state.blockSwipe else { return }
        // Scrolling over the top bar (icon strip) must only scroll the strip, not change pages.
        if ev.window === panel && ev.locationInWindow.y > panel.frame.height - state.notchSize.height - 6 { return }
        if ev.phase.contains(.began) || ev.phase.contains(.mayBegin) { scrollAccum = 0; didSwitch = false }
        let ended = ev.phase.contains(.ended) || ev.phase.contains(.cancelled)
        if !ev.momentumPhase.isEmpty { return }
        if abs(ev.scrollingDeltaX) > abs(ev.scrollingDeltaY) && !didSwitch {
            scrollAccum += ev.scrollingDeltaX
            if abs(scrollAccum) > 90 {
                let tabs = NotchTab.enabled
                if let i = tabs.firstIndex(of: state.tab) {
                    let n = scrollAccum < 0 ? i + 1 : i - 1
                    if n >= 0 && n < tabs.count { state.go(tabs[n]) }
                }
                scrollAccum = 0
                didSwitch = !ev.phase.isEmpty
            }
        }
        if ended { scrollAccum = 0; didSwitch = false }
    }
}
