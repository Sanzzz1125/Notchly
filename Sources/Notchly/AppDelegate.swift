import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var pauseItem: NSMenuItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        P.register()
        BatteryService.shared.start()
        MediaController.shared.start()
        CalendarService.shared.start()
        ReminderService.shared.start()
        ClipboardStore.shared.start()
        StatsService.shared.start()
        VolumeMonitor.shared.start()
        DownloadsWatcher.shared.start()
        NotchController.shared.start()
        buildMenu()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.item?.isVisible = P.bool("showMenuIcon")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NotchState.shared.post(IslandAlert(symbol: "sparkles", tint: P.accent, title: "Notchly", detail: "Hover the notch to open", duration: 2.2))
        }
    }

    private func buildMenu() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        it.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchly")
        let m = NSMenu()
        m.addItem(withTitle: "Open / Close  (⌥ Space)", action: #selector(toggle), keyEquivalent: "").target = self
        let pz = m.addItem(withTitle: "Pause Notchly (save battery)", action: #selector(pause), keyEquivalent: "")
        pz.target = self
        pauseItem = pz
        m.addItem(withTitle: "Keep Mac Awake", action: #selector(awake), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Notchly", action: #selector(quit), keyEquivalent: "q").target = self
        it.menu = m
        it.isVisible = P.bool("showMenuIcon")
        item = it
    }

    @objc private func toggle() { NotchState.shared.toggle() }
    @objc private func pause() {
        let p = !Background.paused
        NotchController.shared.setPaused(p)
        pauseItem?.title = p ? "Resume Notchly" : "Pause Notchly (save battery)"
        item?.button?.alphaValue = p ? 0.45 : 1
    }
    @objc private func awake() { KeepAwake.shared.toggle() }
    @objc private func settings() { SettingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
