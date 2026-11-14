import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension View {
    func card(_ r: CGFloat = 16) -> some View {
        let style = P.int("cardStyle")
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return background(
            ZStack {
                shape.fill(Color.white.opacity(style == 1 ? 0.02 : 0.055))
                if style == 2 { shape.fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.clear], startPoint: .top, endPoint: .center)) }
                shape.strokeBorder(Color.white.opacity(style == 0 ? 0.03 : 0.09), lineWidth: 1)
            }
        )
    }
}

struct RootView: View {
    @ObservedObject var s = NotchState.shared
    @ObservedObject var media = MediaController.shared
    @ObservedObject var timer = TimerStore.shared
    @ObservedObject var awake = KeepAwake.shared
    @AppStorage("theme") var theme = 0
    @AppStorage("accentHex") var accentHex = "#0A84FF"
    @AppStorage("glassTint") var glassTint = 0.55
    @AppStorage("cornerRadius") var cornerRadius = 30.0
    @AppStorage("earWidth") var earWidth = 46.0
    @AppStorage("panelWidth") var panelWidth = 640.0
    @AppStorage("bodyHeight") var bodyHeight = 170.0
    @AppStorage("mediaWings") var mediaWings = true

    var body: some View {
        let size = s.islandSize
        let full = s.expanded ? s.expandedSize : size
        let hidden = !s.hasNotch && !s.expanded && s.alert == nil && !s.wingActive
        ZStack(alignment: .top) {
            Surface(t: s.shoulder, b: s.cornerR, theme: theme, accent: Color(hex: accentHex),
                    tint: glassTint, expanded: s.expanded, artTint: media.tint)
                .frame(width: size.width, height: size.height)
                .opacity(hidden ? 0 : 1)
            content(full)
                .frame(width: full.width, height: full.height, alignment: .top)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(NotchShape(t: s.shoulder, b: s.cornerR))
                .contentShape(Rectangle())
                .contextMenu {
                    Button(s.expanded ? "Close" : "Open") { s.toggle() }
                    Button(awake.on ? "Turn Keep Awake Off" : "Keep Mac Awake") { awake.toggle() }
                    Divider()
                    Button("Settings…") { SettingsWindow.show() }
                    Button("Quit Notchly") { NSApp.terminate(nil) }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.alert, value: s.wingActive)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder func content(_ size: CGSize) -> some View {
        if s.expanded {
            ExpandedView()
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.28).delay(0.14)),
                                        removal: .opacity.animation(.easeIn(duration: 0.1))))
        } else if let a = s.alert {
            AlertView(alert: a, notch: s.notchSize)
                .transition(.opacity)
                .onTapGesture { s.open() }
        } else if s.wingActive {
            WingsView(notch: s.notchSize, ear: CGFloat(earWidth), pad: s.shoulder)
                .transition(.opacity)
                .onTapGesture { s.open() }
        } else {
            Color.clear.contentShape(Rectangle()).onTapGesture { s.open() }
        }
    }
}

// MARK: Compact

struct Equalizer: View {
    let tint: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: Eco.on ? 0.2 : 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(tint)
                        .frame(width: 3, height: 4 + 11 * abs(sin(t * 4 + Double(i) * 1.3)))
                }
            }
            .frame(height: 16)
        }
    }
}

struct WingsView: View {
    let notch: CGSize
    let ear: CGFloat
    let pad: CGFloat
    @ObservedObject var media = MediaController.shared
    @ObservedObject var timer = TimerStore.shared
    @ObservedObject var awake = KeepAwake.shared

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: ear, alignment: .center)
            Spacer(minLength: notch.width)
            right.frame(width: ear, alignment: .center)
        }
        .padding(.horizontal, pad)
        .frame(height: notch.height)
    }

    @ViewBuilder var left: some View {
        if timer.running {
            Image(systemName: timer.mode == .stopwatch ? "stopwatch.fill" : "timer").foregroundStyle(Color.orange)
        } else if media.isPlaying {
            if let a = media.art {
                Image(nsImage: a).resizable().scaledToFill().frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "music.note").foregroundStyle(media.tint)
            }
        } else {
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(Color.orange)
        }
    }

    @ViewBuilder var right: some View {
        if timer.running {
            Text(timer.display).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.orange)
        } else if media.isPlaying {
            Equalizer(tint: media.tint)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

struct AlertView: View {
    let alert: IslandAlert
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: alert.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(alert.tint)
                    .frame(width: 110, alignment: .center)
                Spacer(minLength: notch.width)
                Text(alert.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .frame(width: 110, alignment: .center)
            }
            .frame(height: notch.height)
            if let l = alert.level {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(alert.tint).frame(width: max(4, g.size.width * CGFloat(min(1, max(0, l)))))
                    }
                }
                .frame(height: 5).padding(.horizontal, 26).padding(.bottom, 10)
                .animation(.easeOut(duration: 0.15), value: l)
            } else if !alert.detail.isEmpty {
                Text(alert.detail).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                    .padding(.horizontal, 20).padding(.bottom, 5)
            }
        }
    }
}

// MARK: Expanded

struct ExpandedView: View {
    @ObservedObject var s = NotchState.shared
    @ObservedObject var bat = BatteryService.shared
    @AppStorage("accentHex") var accentHex = "#0A84FF"
    @Namespace private var ns

    var body: some View {
        if s.tab == .mirror {
            mirrorFull
        } else {
            VStack(spacing: 0) {
                header.frame(height: s.notchSize.height)
                pane
                    .id(s.tab)
                    .transition(.asymmetric(
                        insertion: .move(edge: s.forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: s.forward ? .leading : .trailing).combined(with: .opacity)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    var mirrorFull: some View {
        ZStack(alignment: .topLeading) {
            CameraPreview()
            HStack(spacing: 8) {
                Button { s.go(.home) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Back").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                }.buttonStyle(.plain)
                Spacer()
            }
            .padding(.leading, 18).padding(.top, 4)
        }
    }

    func tabButton(_ t: NotchTab) -> some View {
        Button { s.go(t) } label: {
            ZStack {
                if s.tab == t {
                    Capsule().fill(Color(hex: accentHex).opacity(0.9))
                        .matchedGeometryEffect(id: "sel", in: ns)
                }
                Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(s.tab == t ? Color.white : Color.white.opacity(0.55))
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t.title)
        .onDrag { NSItemProvider(object: t.rawValue as NSString) }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                if let ns = obj as? NSString, let from = NotchTab(rawValue: ns as String) {
                    DispatchQueue.main.async { s.move(from, before: t) }
                }
            }
            return true
        }
    }

    var header: some View {
        HStack(spacing: 0) {
            Text(s.tab.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: s.notchSize.width)
            HStack(spacing: 0) {
                GeometryReader { g in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(NotchTab.enabled) { t in tabButton(t).id(t) }
                            }
                            .frame(minWidth: g.size.width, alignment: .trailing)
                        }
                        .onChange(of: s.tab) { _, new in
                            withAnimation(Motion.tab) { proxy.scrollTo(new, anchor: .center) }
                        }
                    }
                }
                .frame(height: 28)
                .padding(.trailing, 8)
                Button { s.pinned.toggle() } label: {
                    Image(systemName: s.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(s.pinned ? Color(hex: accentHex) : Color.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Keep open")
                Button { SettingsWindow.show() } label: {
                    Image(systemName: "gearshape.fill").foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Settings")
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.leading, 10)
        }
    }

    @ViewBuilder var pane: some View {
        switch s.tab {
        case .home: HomeTab()
        case .tray: TrayTab()
        case .clipboard: ClipboardTab()
        case .notes: NotesTab()
        case .calendar: CalendarTab()
        case .reminders: RemindersTab()
        case .timer: TimerTab()
        case .stats: StatsTab()
        case .mirror: MirrorTab()
        case .apps: AppsTab()
        }
    }
}
