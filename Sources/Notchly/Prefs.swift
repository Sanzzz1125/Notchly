import SwiftUI
import AppKit

final class Box<T>: ObservableObject {
    @Published var v: T
    init(_ v: T) { self.v = v }
}

enum P {
    static let defaults: [String: Any] = [
        "theme": 0, "cardStyle": 0, "tabOrder": "", "accentHex": "#0A84FF", "glassTint": 0.5, "cornerRadius": 28.0,
        "earWidth": 46.0, "panelWidth": 660.0, "bodyHeight": 180.0, "motion": 0,
        "openMode": 0, "openDelay": 0.15, "closeDelay": 0.35, "collapseOnExit": true,
        "haptics": true, "hotkey": true, "gestures": true, "display": 0,
        "mediaWings": true, "trayRemove": true, "ecoMode": false, "ecoOnBattery": true, "allowNetwork": true, "srcMusic": true, "srcBrowsers": true, "srcVideo": true, "srcOther": true, "trackAlerts": true, "lyrics": true,
        "chargingAlerts": true, "lowBatteryAlerts": true, "levelAlerts": true,
        "downloadAlerts": false, "calendarAlerts": true, "awakeIndicator": true,
        "homeSide": "calendar", "defaultTab": "home", "showMenuIcon": true,
        "focusMinutes": 25.0, "breakMinutes": 5.0, "autoBreak": true, "timerSound": true,
        "clipLimit": 25.0, "remindersAll": false, "sideWidth": 210.0,
        "tab_tray": true, "tab_clipboard": true, "tab_notes": true, "tab_calendar": true,
        "tab_reminders": true, "tab_timer": true, "tab_stats": true, "tab_mirror": true, "tab_apps": true,
        "tab_controls": true, "tab_weather": false, "weatherEnabled": false, "weatherCity": "", "weatherUnit": 0,
        "focusShortcut": "", "ecoCalmMotion": false, "motionSpeed": 1.0, "motionBounce": 0.5, "tabTransition": 0, "onboarded": false, "demoMode": false, "debugHooks": false,
    ]
    static func register() {
        UserDefaults.standard.register(defaults: defaults)
        // `-factoryDefaults YES` (launch argument, in-memory only): ignore every saved preference.
        // Used by scripts/screenshots.sh so docs never show personal settings.
        if CommandLine.arguments.contains("-factoryDefaults") {
            var args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            for (k, v) in defaults where args[k] == nil { args[k] = v }
            UserDefaults.standard.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
        }
    }
    static func bool(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
    static func dbl(_ k: String) -> Double { UserDefaults.standard.double(forKey: k) }
    static func int(_ k: String) -> Int { UserDefaults.standard.integer(forKey: k) }
    static func str(_ k: String) -> String { UserDefaults.standard.string(forKey: k) ?? "" }
    static var accent: Color { Color(hex: str("accentHex")) }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255,
                  blue: Double(v & 255) / 255, opacity: 1)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.systemBlue
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Global switches for background work.
enum Background {
    /// User switched Notchly off ("Pause everything").
    static var user = false
    /// Screen asleep / Mac asleep.
    static var screenOff = false
    static var paused: Bool { user || screenOff }
}

enum Eco {
    /// Battery-saver: slower polling, no idle animations.
    static var on: Bool {
        if P.bool("ecoMode") { return true }
        let b = BatteryService.shared
        return P.bool("ecoOnBattery") && b.hasBattery && !b.plugged
    }
}
