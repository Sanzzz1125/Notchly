import SwiftUI
import AppKit
import AVFoundation

enum Onboarding {
    static var window: NSWindow?
    /// Debug hooks rebuild the window so a given page can be shown directly.
    static var debugRebuild = false
    static func show(page: Int = 0) {
        if page >= 0 && window != nil && debugRebuild { window?.close(); window = nil }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = NSColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 1)
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: OnboardingView(start: page))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    static func finish() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        window?.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotchState.shared.open(.home, byKeyboard: true)
        }
    }
}

private struct PermRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let status: String      // "", "Allowed", "Denied"
    let button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.Ink.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if status == "Allowed" {
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.green)
            } else if !button.isEmpty {
                Chip(title: status == "Denied" ? "Open Settings" : button, prominent: status != "Denied", action: action)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

struct OnboardingView: View {
    @StateObject private var page: Box<Int>
    init(start: Int = 0) { _page = StateObject(wrappedValue: Box<Int>(start)) }
    @ObservedObject private var cal = CalendarService.shared
    @ObservedObject private var rem = ReminderService.shared
    @StateObject private var cam = Box<AVAuthorizationStatus>(AVCaptureDevice.authorizationStatus(for: .video))
    @AppStorage("allowNetwork") private var net = true
    @AppStorage("theme") private var theme = 0
    private let last = 3

    private func status(_ a: Access) -> String { a == .granted ? "Allowed" : (a == .denied ? "Denied" : "") }
    private func settings(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page.v {
                case 0: welcome.transition(.asymmetric(insertion: .offset(x: 30).combined(with: .opacity), removal: .offset(x: -30).combined(with: .opacity)))
                case 1: permissions.frame(maxHeight: .infinity, alignment: .top).transition(.asymmetric(insertion: .offset(x: 30).combined(with: .opacity), removal: .offset(x: -30).combined(with: .opacity)))
                case 2: privacy.frame(maxHeight: .infinity, alignment: .top).transition(.asymmetric(insertion: .offset(x: 30).combined(with: .opacity), removal: .offset(x: -30).combined(with: .opacity)))
                default: ready.transition(.asymmetric(insertion: .offset(x: 30).combined(with: .opacity), removal: .offset(x: -30).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36).padding(.top, 34)
            HStack {
                HStack(spacing: 6) {
                    ForEach(0...last, id: \.self) { i in
                        Capsule().fill(i == page.v ? P.accent : Color.white.opacity(0.2)).frame(width: i == page.v ? 18 : 6, height: 6)
                    }
                }
                .animation(Motion.tab, value: page.v)
                Spacer()
                if page.v > 0 { Chip(title: "Back") { withAnimation(Motion.tab) { page.v -= 1 } } }
                Chip(title: page.v == last ? "Start using Notchly" : "Continue", prominent: true) {
                    if page.v == last { Onboarding.finish() } else { withAnimation(Motion.tab) { page.v += 1 } }
                }
            }
            .padding(.horizontal, 36).padding(.vertical, 20)
        }
        .frame(width: 620, height: 500)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104)
            Text("Welcome to Notchly").font(.system(size: 26, weight: .bold))
            Text("Your notch, turned into a control centre: music, calendar, files, timers and quick actions without switching apps.")
                .font(.system(size: 13)).foregroundStyle(DS.Ink.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 10) {
                how("cursorarrow.motionlines", "Hover the notch to open it (or click it, in Settings)")
                how("keyboard", "Press ⌥ Space to open or close from anywhere")
                how("square.and.arrow.down", "Drag a file toward the notch to drop it in the Tray")
                how("hand.draw", "Swipe two fingers left or right to change tabs")
            }
            .padding(.top, 8)
        }
    }
    func how(_ s: String, _ t: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s).font(.system(size: 14, weight: .semibold)).foregroundStyle(P.accent).frame(width: 26)
            Text(t).font(.system(size: 13))
        }
    }

    var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions, only what you choose").font(.system(size: 22, weight: .bold))
            Text("Notchly asks macOS for nothing until you press a button. Everything is optional and can be revoked in System Settings.")
                .font(.system(size: 12)).foregroundStyle(DS.Ink.secondary)
            PermRow(symbol: "calendar", tint: Color.red, title: "Calendar", detail: "Show your next events and event alerts.",
                    status: status(cal.access), button: "Allow") {
                if cal.access == .denied { settings("Privacy_Calendars") } else { cal.requestAccess() }
            }
            PermRow(symbol: "checklist", tint: Color.orange, title: "Reminders", detail: "Show to-dos and tick them off.",
                    status: status(rem.access), button: "Allow") {
                if rem.access == .denied { settings("Privacy_Reminders") } else { rem.requestAccess() }
            }
            PermRow(symbol: "camera.fill", tint: Color(hex: "#5E5CE6"), title: "Camera", detail: "Only while the Mirror tab is open. Nothing is recorded.",
                    status: cam.v == .authorized ? "Allowed" : (cam.v == .denied ? "Denied" : ""), button: "Allow") {
                if cam.v == .denied { settings("Privacy_Camera") } else {
                    AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { cam.v = AVCaptureDevice.authorizationStatus(for: .video) } }
                }
            }
            PermRow(symbol: "music.note", tint: Color.pink, title: "Music, Spotify & System Events",
                    detail: "macOS asks the first time you control playback, switch dark mode or mute.", status: "", button: "") {}
            Text("Notchly never needs Accessibility, Full Disk Access or Screen Recording.")
                .font(.system(size: 11)).foregroundStyle(DS.Ink.tertiary).padding(.top, 2)
        }
    }

    var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Private by design").font(.system(size: 22, weight: .bold))
            VStack(alignment: .leading, spacing: 8) {
                how("lock.shield.fill", "No account, no analytics, no telemetry. Ever.")
                how("internaldrive", "Your data stays on this Mac. Clipboard history lives in memory only.")
                how("chevron.left.forwardslash.chevron.right", "Open source: read exactly what it does.")
            }
            Toggle(isOn: $net) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Allow internet for lyrics and artwork").font(.system(size: 13, weight: .semibold))
                    Text("Song and artist names go to lrclib.net to fetch synced lyrics. Turn off and nothing leaves your Mac.")
                        .font(.system(size: 11)).foregroundStyle(DS.Ink.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            Text("Weather is a separate opt-in in Settings → Privacy and is off by default.")
                .font(.system(size: 11)).foregroundStyle(DS.Ink.tertiary)
        }
    }

    var ready: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 42)).foregroundStyle(P.accent)
            Text("You're all set").font(.system(size: 24, weight: .bold))
            Text("Pick a look. You can change everything later in Settings.").font(.system(size: 13)).foregroundStyle(DS.Ink.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(NotchTheme.all.prefix(8)) { th in
                    Button { withAnimation(DS.press) { theme = th.id } } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LinearGradient(colors: [th.top, th.bottom], startPoint: .top, endPoint: .bottom))
                                .frame(height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme == th.id ? P.accent : Color.white.opacity(0.14), lineWidth: theme == th.id ? 2.5 : 1))
                            Text(th.name).font(.system(size: 10.5)).foregroundStyle(DS.Ink.secondary)
                        }
                    }
                    .buttonStyle(PressStyle(radius: 10, scale: 0.95, fill: false))
                }
            }
            .padding(.top, 6)
        }
    }
}
