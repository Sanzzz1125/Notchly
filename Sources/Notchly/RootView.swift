import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                .shadow(color: Color.black.opacity(s.expanded ? 0.4 : 0), radius: 16, y: 8)
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
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.3).delay(0.12)),
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
        TimelineView(.animation(minimumInterval: Eco.on ? 0.25 : 1.0 / 20.0)) { tl in
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
                        insertion: .offset(x: s.forward ? 40 : -40).combined(with: .opacity),
                        removal: .offset(x: s.forward ? -40 : 40).combined(with: .opacity)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, DS.Space.s)
            }
            .padding(.horizontal, DS.Space.xl - 2)
            .padding(.bottom, DS.Space.m + 2)
        }
    }

    var mirrorFull: some View {
        ZStack(alignment: .topLeading) {
            CameraPreview()
            Button { s.go(.home) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("Back").font(DS.Typo.caption)
                }
                .padding(.horizontal, 11).frame(height: 26)
                .background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle(radius: 13, scale: 0.94, fill: false))
            .padding(.leading, 18).padding(.top, 5)
        }
    }

    func tabButton(_ t: NotchTab) -> some View {
        Button { s.go(t) } label: {
            ZStack {
                if s.tab == t {
                    Capsule().fill(Color(hex: accentHex))
                        .matchedGeometryEffect(id: "sel", in: ns)
                        .shadow(color: Color(hex: accentHex).opacity(0.5), radius: 6, y: 1)
                }
                Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(s.tab == t ? Color.white : DS.Ink.secondary)
            }
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: 13, scale: 0.9, fill: s.tab != t))
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

    var pinButton: some View {
        IconButton(symbol: s.pinned ? "pin.fill" : "pin", size: 26, icon: 11,
                   tint: s.pinned ? Color(hex: accentHex) : DS.Ink.secondary, help: s.pinned ? "Unpin" : "Keep open") { s.pinned.toggle() }
    }
    var gearButton: some View {
        IconButton(symbol: "gearshape.fill", size: 26, icon: 11, help: "Settings") { SettingsWindow.show() }
    }

    var header: some View {
        GeometryReader { g in
            let wing = max(60, (g.size.width - s.notchSize.width) / 2)
            let narrow = wing < 190
            let tabs = NotchTab.enabled
            let stripW = wing - (narrow ? 4 : 62)
            let overflow = CGFloat(tabs.count) * 30 > stripW
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    if narrow {
                        pinButton; gearButton
                    } else {
                        Text(s.tab.title).font(DS.Typo.headline).foregroundStyle(DS.Ink.primary.opacity(0.9))
                            .id(s.tab.rawValue).transition(.opacity.combined(with: .offset(y: 4)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: wing, alignment: .leading)
                Spacer().frame(width: s.notchSize.width)
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(tabs) { t in tabButton(t).id(t) }
                            }
                            .frame(minWidth: stripW, alignment: .trailing)
                        }
                        .onChange(of: s.tab) { _, new in
                            withAnimation(Motion.tab) { proxy.scrollTo(new, anchor: .center) }
                        }
                    }
                    .frame(width: stripW)
                    .mask(
                        LinearGradient(stops: [.init(color: overflow ? .clear : .black, location: 0), .init(color: .black, location: overflow ? 0.1 : 0),
                                               .init(color: .black, location: overflow ? 0.9 : 1), .init(color: overflow ? .clear : .black, location: 1)],
                                       startPoint: .leading, endPoint: .trailing))
                    if !narrow { pinButton; gearButton }
                }
                .frame(width: wing, alignment: .trailing)
            }
            .animation(Motion.tab, value: s.tab)
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
        case .controls: ControlsTab()
        case .weather: WeatherTab()
        case .apps: AppsTab()
        case .mirror: MirrorTab()
        }
    }
}
