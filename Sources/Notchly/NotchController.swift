import SwiftUI
import AppKit
import Carbon.HIToolbox

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
    private var timer: Timer?
    private var hoverStart: Date?
    private var leaveStart: Date?
    private var lastDrag = NSPasteboard(name: .drag).changeCount
    private var scrollAccum: CGFloat = 0
    private var lastKey = ""

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
        schedule(1.0 / 20.0)

        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] ev in
            self?.scroll(ev)
            return ev
        }
        HotKey.handler = { NotchState.shared.toggle() }
        HotKey.register()
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

    private var interval: TimeInterval = 0
    private func schedule(_ iv: TimeInterval) {
        if iv == interval && timer != nil { return }
        interval = iv
        timer?.invalidate()
        let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func setPaused(_ p: Bool) {
        Background.paused = p
        MediaController.shared.setPaused(p)
        if p {
            state.close()
            timer?.invalidate(); timer = nil; interval = 0
            panel.orderOut(nil)
        } else {
            reposition()
            panel.orderFrontRegardless()
            schedule(1.0 / 20.0)
        }
    }

    private func tick() {
        let want: TimeInterval = Eco.on ? 0.1 : (state.expanded ? 1.0 / 30.0 : 1.0 / 20.0)
        if want != interval { schedule(want) }
        let m = NSEvent.mouseLocation
        let pf = panel.frame
        let sz = state.islandSize
        let rect = NSRect(x: pf.midX - sz.width / 2, y: pf.maxY - sz.height, width: sz.width, height: sz.height)
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let now = Date()

        if !state.expanded {
            let hot = NSRect(x: rect.minX - 8, y: rect.minY - 6, width: rect.width + 16, height: rect.height + 12)
            let inside = hot.contains(m)
            panel.ignoresMouseEvents = !inside
            leaveStart = nil
            let dpb = NSPasteboard(name: .drag).changeCount
            if down && inside && dpb != lastDrag {
                lastDrag = dpb
                state.open(.tray)
                return
            }
            if !down { lastDrag = dpb }
            if inside && P.int("openMode") == 0 && !down {
                if hoverStart == nil { hoverStart = now }
                if now.timeIntervalSince(hoverStart ?? now) >= P.dbl("openDelay") {
                    hoverStart = nil
                    state.open(NotchTab(rawValue: P.str("defaultTab")))
                }
            } else if !inside {
                hoverStart = nil
            }
        } else {
            let hot = rect.insetBy(dx: -10, dy: -10)
            let inside = hot.contains(m)
            panel.ignoresMouseEvents = !inside
            hoverStart = nil
            if inside || down || state.pinned || !P.bool("collapseOnExit") {
                leaveStart = nil
            } else {
                if leaveStart == nil { leaveStart = now }
                if now.timeIntervalSince(leaveStart ?? now) >= P.dbl("closeDelay") {
                    leaveStart = nil
                    state.close()
                }
            }
        }
    }

    private var didSwitch = false

    private func scroll(_ ev: NSEvent) {
        guard state.expanded, P.bool("gestures") else { return }
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
