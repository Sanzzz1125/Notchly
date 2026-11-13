import SwiftUI
import AppKit
import EventKit
import UniformTypeIdentifiers

private func fmt(_ s: Double) -> String {
    let v = Int(max(0, s))
    return String(format: "%d:%02d", v / 60, v % 60)
}

private struct Empty: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Color.white.opacity(0.35))
            Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Home
struct HomeTab: View {
    @AppStorage("homeSide") var side = "calendar"
    @AppStorage("sideWidth") var sideW = 210.0
    var body: some View {
        GeometryReader { g in
            let showSide = side != "none" && g.size.width > 520
            let w = min(CGFloat(sideW), g.size.width * 0.38)
            HStack(spacing: 12) {
                MediaCard()
                if showSide { SideWidget(kind: side).frame(width: w) }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

struct MediaCard: View {
    @ObservedObject var m = MediaController.shared
    @StateObject private var drag = Box<Double?>(nil)

    var body: some View {
        GeometryReader { g in
            let art = max(56, min(112, g.size.height - 24))
            let compact = g.size.height < 150
            HStack(spacing: 14) {
                artwork(art)
                if m.hasTrack { info(compact) } else { idle }
            }
            .padding(12)
            .frame(width: g.size.width, height: g.size.height)
        }
        .card()
    }

    func artwork(_ art: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [m.tint.opacity(0.7), Color.black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let a = m.art {
                Image(nsImage: a).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(width: art, height: art)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: m.tint.opacity(m.hasTrack ? 0.55 : 0), radius: 14, y: 6)
        .scaleEffect(m.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: m.isPlaying)
    }

    var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing playing").font(.system(size: 15, weight: .semibold))
            Text("Play something in any app").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55))
            HStack {
                Button("Spotify") { NSWorkspace.shared.launchApplication("Spotify") }
                Button("Music") { NSWorkspace.shared.launchApplication("Music") }
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func info(_ compact: Bool) -> some View {
        let frac = m.duration > 0 ? (drag.v ?? m.position / m.duration) : 0
        return VStack(alignment: .leading, spacing: 4) {
            Text(m.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
            if !(compact && !m.lyric.isEmpty) {
                Text(m.artist).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
            }
            if !m.lyric.isEmpty {
                Text(m.lyric).font(.system(size: 11, weight: .medium)).foregroundStyle(m.tint).lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(m.tint).frame(width: max(0, g.size.width * CGFloat(min(1, max(0, frac)))))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in drag.v = Double(max(0, min(1, v.location.x / g.size.width))) }
                    .onEnded { v in
                        m.seek(Double(max(0, min(1, v.location.x / g.size.width))))
                        drag.v = nil
                    })
            }
            .frame(height: 6)
            if !compact {
                HStack {
                    Text(fmt(frac * m.duration)).font(.system(size: 10)).monospacedDigit()
                    Spacer()
                    Text(fmt(m.duration)).font(.system(size: 10)).monospacedDigit()
                }
                .foregroundStyle(Color.white.opacity(0.5))
            }
            HStack(spacing: 26) {
                Spacer()
                Button { m.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 16)) }
                Button { m.playPause() } label: { Image(systemName: m.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)) }
                Button { m.next() } label: { Image(systemName: "forward.fill").font(.system(size: 16)) }
                Spacer()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SideWidget: View {
    let kind: String
    var body: some View {
        Group {
            switch kind {
            case "reminders": RemindersList(limit: 4)
            case "stats": StatsMini()
            default: CalendarList(limit: 5, soon: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

struct StatsMini: View {
    @ObservedObject var st = StatsService.shared
    @ObservedObject var bat = BatteryService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar("CPU", st.cpu, .green)
            bar("Memory", st.mem, .orange)
            bar("Disk", st.disk, .blue)
            if bat.hasBattery { bar("Battery", Double(bat.percent) / 100, bat.percent <= 20 ? .red : .green) }
        }
        .onAppear { st.sample() }
    }
    func bar(_ n: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(n); Spacer(); Text("\(Int(v * 100))%").monospacedDigit() }.font(.system(size: 10, weight: .medium))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(c).frame(width: g.size.width * CGFloat(min(1, max(0, v))))
                }
            }.frame(height: 4)
        }
    }
}

// MARK: Calendar
struct CalendarList: View {
    @ObservedObject var cal = CalendarService.shared
    var limit: Int = 50
    var soon: Bool = false
    private func label(_ ev: EKEvent) -> String {
        if ev.isAllDay { return "All day" }
        let t = ev.startDate.formatted(date: .omitted, time: .shortened)
        if !soon { return t }
        let c = Calendar.current
        if c.isDateInToday(ev.startDate) { return "Today · " + t }
        if c.isDateInTomorrow(ev.startDate) { return "Tomorrow · " + t }
        return ev.startDate.formatted(.dateTime.weekday(.abbreviated)) + " · " + t
    }
    var body: some View {
        let list = soon ? cal.upcomingList : cal.events
        if !cal.authorized {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 22)).foregroundStyle(Color.white.opacity(0.4))
                Text("Calendar access needed").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
                Button("Open Settings") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(u) }
                }.buttonStyle(.bordered).controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if list.isEmpty {
            Empty(symbol: "calendar", text: soon ? "Nothing coming up" : "No events")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(list.prefix(limit)), id: \.self) { ev in
                        HStack(spacing: 8) {
                            Capsule().fill(Color(nsColor: ev.calendar.color)).frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ev.title ?? "Event").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(label(ev)).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct CalendarTab: View {
    @ObservedObject var cal = CalendarService.shared
    var days: [Date] {
        let c = Calendar.current
        let t = c.startOfDay(for: Date())
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: t) }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let sel = Calendar.current.isDate(d, inSameDayAs: cal.day)
                    Button { cal.select(d) } label: {
                        VStack(spacing: 1) {
                            Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 9, weight: .medium))
                            Text(d.formatted(.dateTime.day())).font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sel ? P.accent : Color.white.opacity(0.07)))
                    }.buttonStyle(.plain)
                }
            }
            CalendarList().padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
        }
    }
}

// MARK: Reminders
struct RemindersList: View {
    @ObservedObject var svc = ReminderService.shared
    var limit: Int = 50
    var body: some View {
        if !svc.authorized {
            Empty(symbol: "checklist", text: "Allow Reminders access in System Settings")
        } else if svc.items.isEmpty {
            Empty(symbol: "checkmark.circle", text: "All done")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(svc.items.prefix(limit)), id: \.self) { r in
                        HStack(spacing: 8) {
                            Button { svc.complete(r) } label: {
                                Image(systemName: "circle").font(.system(size: 15)).foregroundStyle(P.accent)
                            }.buttonStyle(.plain)
                            Text(r.title ?? "").font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RemindersTab: View {
    @ObservedObject var svc = ReminderService.shared
    @StateObject private var text = Box<String>("")
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(P.accent)
                TextField("Add a reminder", text: $text.v)
                    .textFieldStyle(.plain)
                    .onSubmit { svc.add(text.v); text.v = "" }
            }
            .padding(9).card(12)
            RemindersList().padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
        }
    }
}

// MARK: Clipboard
struct ClipboardTab: View {
    @ObservedObject var cb = ClipboardStore.shared
    @StateObject private var flash = Box<String?>(nil)
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(cb.items.count) copied").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
                Spacer()
                Button("Clear") { cb.clear() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(P.accent)
            }
            if cb.items.isEmpty {
                Empty(symbol: "doc.on.clipboard", text: "Copy something and it shows up here")
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(cb.items, id: \.self) { s in
                            Button {
                                cb.copy(s); flash.v = s
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if flash.v == s { flash.v = nil } }
                            } label: {
                                HStack {
                                    Text(s).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 6)
                                    Image(systemName: flash.v == s ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(flash.v == s ? Color.green : Color.white.opacity(0.4))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .card(10)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Remove") { cb.remove(s) } }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Notes
struct NotesTab: View {
    @AppStorage("notes") var notes = ""
    var body: some View {
        TextEditor(text: $notes)
            .scrollContentBackground(.hidden)
            .font(.system(size: 13))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
    }
}

// MARK: Timer
struct TimerTab: View {
    @ObservedObject var t = TimerStore.shared
    var body: some View {
        GeometryReader { g in
            let ring = max(70, min(132, g.size.height - 24))
            content(ring).frame(width: g.size.width, height: g.size.height)
        }
        .card()
    }

    func content(_ ring: CGFloat) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle().trim(from: 0, to: CGFloat(t.mode == .stopwatch ? (t.elapsed.truncatingRemainder(dividingBy: 60)) / 60 : t.progress))
                    .stroke(t.onBreak ? Color.green : P.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(t.display).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                    if t.mode == .focus { Text(t.onBreak ? "Break" : "Focus").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.6)) }
                }
            }
            .frame(width: ring, height: ring)
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: Binding(get: { t.mode }, set: { t.setMode($0) })) {
                    ForEach(TimerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if t.mode == .timer {
                    HStack(spacing: 6) {
                        ForEach([1, 5, 10, 15, 25, 45], id: \.self) { m in
                            Button("\(m)m") { t.setMinutes(Double(m)) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { t.toggle() } label: {
                        Label(t.running ? "Pause" : "Start", systemImage: t.running ? "pause.fill" : "play.fill")
                            .frame(width: 80)
                    }
                    .buttonStyle(.borderedProminent).tint(P.accent)
                    Button { t.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }
}

// MARK: Stats
struct Ring: View {
    let label: String
    let value: Double
    let color: Color
    var size: CGFloat = 92
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, value))))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int(value * 100))%").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: size, height: size)
            Text(label).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
        }
    }
}

struct StatsTab: View {
    @ObservedObject var st = StatsService.shared
    var body: some View {
        GeometryReader { g in
            let sz = max(56, min(92, g.size.height - 50))
            HStack(spacing: 34) {
                Ring(label: "CPU", value: st.cpu, color: .green, size: sz)
                Ring(label: "Memory", value: st.mem, color: .orange, size: sz)
                Ring(label: "Disk", value: st.disk, color: .blue, size: sz)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .card()
        .onAppear { st.sample() }
    }
}

// MARK: Mirror
struct MirrorTab: View {
    var body: some View {
        CameraPreview()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Tray
struct DropZone: View {
    let symbol: String
    let title: String
    let action: ([URL]) -> Void
    @StateObject private var hot = Box<Bool>(false)
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20))
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(hot.v ? P.accent : Color.white.opacity(0.65))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hot.v ? P.accent.opacity(0.18) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(hot.v ? P.accent : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .scaleEffect(hot.v ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hot.v)
        .onDrop(of: [UTType.fileURL], isTargeted: $hot.v) { providers in
            loadFileURLs(providers, action)
            return true
        }
    }
}

struct TrayTab: View {
    @ObservedObject var tray = TrayStore.shared
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                DropZone(symbol: "tray.and.arrow.down.fill", title: "Drop to hold") { tray.add($0) }
                DropZone(symbol: "airplayaudio", title: "AirDrop") { urls in
                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                }
            }
            .frame(width: 130)
            ZStack {
                if tray.files.isEmpty {
                    Empty(symbol: "square.stack.3d.up", text: "Files you drop stay here — drag them out anywhere")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(tray.files, id: \.self) { u in
                                VStack(spacing: 4) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 48, height: 48)
                                    Text(u.lastPathComponent).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                                        .frame(width: 70)
                                }
                                .padding(8).card(12)
                                .onDrag { NSItemProvider(object: u as NSURL) }
                                .contextMenu {
                                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                                    Button("AirDrop") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [u]) }
                                    Button("Remove") { tray.remove(u) }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
            .overlay(alignment: .topTrailing) {
                if !tray.files.isEmpty {
                    Button { tray.clear() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.white.opacity(0.5)) }
                        .buttonStyle(.plain).padding(6)
                }
            }
        }
    }
}

// MARK: Apps
struct AppsTab: View {
    @AppStorage("launchApps") var raw = ""
    static let fallback = ["/System/Applications/Safari.app", "/System/Applications/Notes.app", "/System/Applications/Music.app",
                           "/System/Applications/Calendar.app", "/System/Applications/Utilities/Terminal.app",
                           "/System/Applications/System Settings.app"]
    var paths: [String] {
        if raw.isEmpty { return AppsTab.fallback.filter { FileManager.default.fileExists(atPath: $0) } }
        return raw.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != "-" }
    }
    func save(_ p: [String]) { raw = p.isEmpty ? "-" : p.joined(separator: "\n") }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                ForEach(paths, id: \.self) { p in
                    Button {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        NotchState.shared.close()
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 52, height: 52)
                            Text(URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent)
                                .font(.system(size: 10)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Remove") { save(paths.filter { $0 != p }) } }
                }
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    let op = NSOpenPanel()
                    op.allowedFileTypes = ["app"]
                    op.directoryURL = URL(fileURLWithPath: "/Applications")
                    if op.runModal() == .OK, let u = op.url { save(paths + [u.path]) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.system(size: 30, weight: .light)).frame(width: 52, height: 52)
                            .foregroundStyle(Color.white.opacity(0.6))
                        Text("Add").font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(2)
        }
    }
}
