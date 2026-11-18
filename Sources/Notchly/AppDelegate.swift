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
        SpotifyAuth.shared.start()
        StatsService.shared.start()
        VolumeMonitor.shared.start()
        DownloadsWatcher.shared.start()
        NotchController.shared.start()
        buildMenu()
        installMainMenu()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshMenuIcon()
        }
        if !P.bool("onboarded") && !Demo.on {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Onboarding.show() }
        } else if !Demo.on {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotchState.shared.post(IslandAlert(symbol: "sparkles", tint: P.accent, title: "Notchly", detail: "Hover the notch to open", duration: 2.2))
            }
        }
    }

    /// An accessory app has no main menu, and macOS routes ⌘V/⌘C/⌘X/⌘A/⌘Z to text fields *through* an Edit menu.
    /// Without this, paste (and copy, select-all, undo) silently do nothing in every Notchly text field.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Notchly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        NSApp.mainMenu = main
    }

    /// notchly://callback?… (Spotify sign-in returns here)
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { SpotifyAuth.shared.handle(u) }
    }

    private func buildMenu() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        it.button?.image = Brand.menuBarIcon()
        let m = NSMenu()
        m.addItem(withTitle: "Open / Close  (⌥ Space)", action: #selector(toggle), keyEquivalent: "").target = self
        let pz = m.addItem(withTitle: "Pause Notchly (save battery)", action: #selector(pause), keyEquivalent: "")
        pz.target = self
        pauseItem = pz
        m.addItem(withTitle: "Keep Mac Awake", action: #selector(awake), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        m.addItem(withTitle: "Welcome Tour…", action: #selector(tour), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Notchly", action: #selector(quit), keyEquivalent: "q").target = self
        it.menu = m
        it.isVisible = P.bool("showMenuIcon")
        item = it
    }

    /// The menu bar icon is the way back from "Pause", so it stays visible while paused even if hidden in Settings.
    func refreshMenuIcon() {
        item?.isVisible = P.bool("showMenuIcon") || Background.user
        pauseItem?.title = Background.user ? "Resume Notchly" : "Pause Notchly (save battery)"
        item?.button?.alphaValue = Background.user ? 0.45 : 1
    }

    @objc private func toggle() { NotchState.shared.toggle() }
    @objc private func pause() {
        NotchController.shared.setPaused(!Background.user)
        refreshMenuIcon()
    }
    @objc private func awake() { KeepAwake.shared.toggle() }
    @objc private func settings() { SettingsWindow.show() }
    @objc private func tour() { Onboarding.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
