import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: Shared

struct AccessPrompt: View {
    let symbol: String
    let what: String
    let access: Access
    let pane: String
    let request: () -> Void
    var body: some View {
        EmptyState(symbol: symbol,
                   title: access == .denied ? "\(what) access is off" : "Allow \(what.lowercased()) access",
                   subtitle: access == .denied ? "Turn it on in System Settings → Privacy" : "Notchly only shows it here, nothing leaves your Mac",
                   actionTitle: access == .denied ? "Open Settings" : "Allow") {
            if access == .denied, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
            else { request() }
        }
    }
}

/// Row with hover highlight used by lists.
struct RowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) { content().contentShape(Rectangle()) }
            .buttonStyle(PressStyle(radius: DS.Radius.s, scale: 0.985))
    }
}

// MARK: Calendar

struct CalendarList: View {
    @ObservedObject var cal = CalendarService.shared
    var limit: Int = 50
    var soon: Bool = false
    private func label(_ ev: CalEvent) -> String {
        if ev.allDay { return soon ? "All day" : "All day" }
        let t = ev.start.formatted(date: .omitted, time: .shortened)
        if !soon { return t + " – " + ev.end.formatted(date: .omitted, time: .shortened) }
        let c = Calendar.current
        if c.isDateInToday(ev.start) { return t }
        if c.isDateInTomorrow(ev.start) { return "Tomorrow · " + t }
        return ev.start.formatted(.dateTime.weekday(.abbreviated)) + " · " + t
    }
    var body: some View {
        let list = soon ? cal.upcomingList : cal.events
        if !cal.authorized {
            AccessPrompt(symbol: "calendar.badge.exclamationmark", what: "Calendar", access: cal.access, pane: "Privacy_Calendars") { cal.requestAccess() }
        } else if list.isEmpty {
            EmptyState(symbol: "calendar", title: soon ? "Nothing coming up" : "No events")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(list.prefix(limit))) { ev in
                        let live = ev.start <= Date() && ev.end > Date() && !ev.allDay
                        HStack(spacing: DS.Space.s) {
                            Capsule().fill(ev.color).frame(width: 3, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ev.title).font(DS.Typo.bodyEm).lineLimit(1)
                                HStack(spacing: 4) {
                                    if live { Text("NOW").font(DS.Typo.micro).foregroundStyle(ev.color) }
                                    Text(label(ev)).font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .edgeFade()
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
    @Namespace private var ns
    var body: some View {
        GeometryReader { g in
            let compact = g.size.height < 150
            VStack(spacing: DS.Space.s) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(days, id: \.self) { d in dayButton(d, compact: compact) }
                }
                CalendarList().padding(compact ? DS.Space.s : DS.Space.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                    .card()
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
    func dayButton(_ d: Date, compact: Bool) -> some View {
        let sel = Calendar.current.isDate(d, inSameDayAs: cal.day)
        let busy = cal.busyDays.contains(Calendar.current.startOfDay(for: d))
        return Button { withAnimation(Motion.tab) { cal.select(d) } } label: {
            Group {
                if compact {
                    HStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(DS.Typo.micro).foregroundStyle(sel ? Color.white.opacity(0.85) : DS.Ink.secondary)
                        Text(d.formatted(.dateTime.day())).font(.system(size: 13, weight: .bold, design: .rounded))
                        Circle().fill(busy ? (sel ? Color.white : P.accent) : Color.clear).frame(width: 4, height: 4)
                    }
                    .padding(.vertical, 5)
                } else {
                    VStack(spacing: 1) {
                        Text(d.formatted(.dateTime.weekday(.abbreviated))).font(DS.Typo.micro)
                            .foregroundStyle(sel ? Color.white.opacity(0.85) : DS.Ink.secondary)
                        Text(d.formatted(.dateTime.day())).font(.system(size: 15, weight: .bold, design: .rounded))
                        Circle().fill(busy ? (sel ? Color.white : P.accent) : Color.clear).frame(width: 4, height: 4)
                    }
                    .padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity)
            .background {
                if sel { RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(P.accent).matchedGeometryEffect(id: "day", in: ns) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.94, fill: !sel))
    }
}

// MARK: Reminders

struct RemindersList: View {
    @ObservedObject var svc = ReminderService.shared
    var limit: Int = 50
    var compact = false
    var body: some View {
        if !svc.authorized {
            AccessPrompt(symbol: "checklist", what: "Reminders", access: svc.access, pane: "Privacy_Reminders") { svc.requestAccess() }
        } else if svc.items.isEmpty {
            EmptyState(symbol: "checkmark.circle", title: "All done")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: compact ? 6 : 4) {
                    ForEach(Array(svc.items.prefix(limit))) { r in
                        ReminderRow(item: r, compact: compact)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ReminderRow: View {
    let item: ReminderItem
    let compact: Bool
    @ObservedObject var svc = ReminderService.shared
    @StateObject private var done = Box<Bool>(false)
    var body: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                withAnimation(DS.press) { done.v = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { svc.complete(item) }
            } label: {
                Image(systemName: done.v ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                    .foregroundStyle(done.v ? Color.green : P.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressStyle(radius: 9, scale: 0.85, fill: false))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(DS.Typo.body).lineLimit(1)
                    .strikethrough(done.v).foregroundStyle(done.v ? DS.Ink.tertiary : DS.Ink.primary)
                if !compact, let d = item.due {
                    Text(d.formatted(date: .omitted, time: .shortened)).font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct RemindersTab: View {
    @ObservedObject var svc = ReminderService.shared
    @StateObject private var text = Box<String>("")
    var body: some View {
        VStack(spacing: DS.Space.s) {
            if svc.authorized {
                DSField(placeholder: "Add a reminder", text: $text.v, symbol: "plus") {
                    svc.add(text.v); text.v = ""
                }
            }
            RemindersList().padding(DS.Space.m).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
        }
    }
}

// MARK: Clipboard

struct ClipboardTab: View {
    @ObservedObject var cb = ClipboardStore.shared
    @StateObject private var query = Box<String>("")
    @StateObject private var flash = Box<UUID?>(nil)

    var shown: [ClipItem] {
        let q = query.v.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? cb.items : cb.items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                DSField(placeholder: "Search clipboard", text: $query.v, symbol: "magnifyingglass")
                Chip(title: "Clear", symbol: "trash") { cb.clear() }
            }
            if cb.items.isEmpty {
                EmptyState(symbol: "doc.on.clipboard", title: "Nothing copied yet", subtitle: "Copy something and it shows up here")
            } else if shown.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No matches")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { it in ClipRow(item: it, flash: flash) }
                    }
                    .padding(.vertical, 2)
                }
                .edgeFade()
            }
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var flash: Box<UUID?>
    @ObservedObject var cb = ClipboardStore.shared
    @StateObject private var hover = Box<Bool>(false)

    var body: some View {
        let copied = flash.v == item.id
        HStack(spacing: DS.Space.s) {
            Image(systemName: item.pinned ? "pin.fill" : (item.isLink ? "link" : "text.alignleft"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.pinned ? P.accent : DS.Ink.tertiary).frame(width: 14)
            Text(item.text).font(DS.Typo.body).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hover.v && !copied {
                IconButton(symbol: item.pinned ? "pin.slash" : "pin", size: 24, icon: 10, help: item.pinned ? "Unpin" : "Pin") { cb.togglePin(item) }
                IconButton(symbol: "xmark", size: 24, icon: 9, help: "Remove") { cb.remove(item) }
            } else if copied {
                Label("Copied", systemImage: "checkmark").font(DS.Typo.micro).foregroundStyle(Color.green)
            } else if !item.app.isEmpty {
                Text(item.app).font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary)
            }
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(hover.v ? DS.Fill.hover : DS.Fill.base))
        .contentShape(Rectangle())
        .onTapGesture {
            cb.copy(item.text)
            withAnimation(DS.press) { flash.v = item.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { if flash.v == item.id { withAnimation { flash.v = nil } } }
        }
        .onHover { h in withAnimation(DS.hoverAnim) { hover.v = h } }
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin") { cb.togglePin(item) }
            Button("Remove") { cb.remove(item) }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

// MARK: Notes

struct NotesTab: View {
    @ObservedObject var store = NotesStore.shared
    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 470
            HStack(spacing: DS.Space.s) {
                if wide {
                    VStack(spacing: DS.Space.xs) {
                        Chip(title: "New note", symbol: "plus", prominent: true) { store.add() }
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 3) {
                                ForEach(store.notes) { n in noteRow(n) }
                            }
                        }
                    }
                    .frame(width: 150)
                }
                VStack(spacing: 0) {
                    if !wide {
                        HStack {
                            Menu {
                                ForEach(store.notes) { n in Button(n.title) { store.current = n.id } }
                            } label: { Text(store.selected?.title ?? "Notes").font(DS.Typo.bodyEm) }
                                .menuStyle(.borderlessButton).fixedSize()
                            Spacer()
                            IconButton(symbol: "plus", size: 24, icon: 11) { store.add() }
                        }
                        .padding(.horizontal, DS.Space.m).padding(.top, 6)
                    }
                    if let id = store.current {
                        TextEditor(text: store.binding(id))
                            .scrollContentBackground(.hidden).font(.system(size: 13))
                            .padding(DS.Space.s)
                            .id(id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
                .overlay(alignment: .topTrailing) {
                    if wide, let id = store.current {
                        IconButton(symbol: "trash", size: 24, icon: 10, tint: DS.Ink.tertiary, help: "Delete note") { store.delete(id) }
                            .padding(6)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
    func noteRow(_ n: Note) -> some View {
        let sel = n.id == store.current
        return Button { withAnimation(Motion.tab) { store.current = n.id } } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(n.title).font(DS.Typo.bodyEm).lineLimit(1)
                Text(n.updated.formatted(.relative(presentation: .named))).font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).fill(sel ? P.accent.opacity(0.28) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: DS.Radius.s, scale: 0.98, fill: !sel))
    }
}

// MARK: Timer

struct TimerTab: View {
    @ObservedObject var t = TimerStore.shared
    var body: some View {
        GeometryReader { g in
            let ring = max(70, min(128, g.size.height - 2 * DS.Space.m))
            content(ring, g.size.width).frame(width: g.size.width, height: g.size.height)
        }
        .card()
    }

    func content(_ ring: CGFloat, _ width: CGFloat) -> some View {
        HStack(spacing: DS.Space.xl) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle().trim(from: 0, to: CGFloat(t.mode == .stopwatch ? (t.elapsed.truncatingRemainder(dividingBy: 60)) / 60 : t.progress))
                    .stroke(t.onBreak ? Color.green : P.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: t.progress)
                VStack(spacing: 0) {
                    Text(t.display).font(.system(size: ring > 100 ? 24 : 18, weight: .bold, design: .rounded)).monospacedDigit()
                    if t.mode == .focus { Text(t.onBreak ? "Break" : "Focus").font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary) }
                }
            }
            .frame(width: ring, height: ring)
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Segmented(items: TimerMode.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { t.mode }, set: { t.setMode($0) }))
                    .frame(maxWidth: 280)
                if t.mode == .timer {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(width > 540 ? [1, 5, 10, 15, 25, 45] : [5, 10, 25, 45], id: \.self) { m in
                            Chip(title: "\(m)m", prominent: Int(t.total / 60) == m) { t.setMinutes(Double(m)) }
                        }
                    }
                }
                HStack(spacing: DS.Space.s) {
                    Chip(title: t.running ? "Pause" : "Start", symbol: t.running ? "pause.fill" : "play.fill", prominent: true) { t.toggle() }
                    Chip(title: "Reset", symbol: "arrow.counterclockwise") { t.reset() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.m)
    }
}

// MARK: Stats

struct Ring: View {
    let label: String
    let value: Double
    let color: Color
    var size: CGFloat = 92
    var body: some View {
        VStack(spacing: DS.Space.xs) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: size > 70 ? 9 : 7)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, value))))
                    .stroke(color, style: StrokeStyle(lineWidth: size > 70 ? 9 : 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int(value * 100))%").font(.system(size: size > 70 ? 15 : 12, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: size, height: size)
            Text(label).font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary).lineLimit(1).fixedSize()
        }
        .frame(minWidth: size)
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color
    var body: some View {
        GeometryReader { g in
            let pts = values.enumerated().map { (i, v) in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(1, values.count - 1)), y: g.size.height * (1 - CGFloat(min(1, max(0, v)))))
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height)); p.addLine(to: f)
                    for q in pts.dropFirst() { p.addLine(to: q) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height)); p.closeSubpath()
                }.fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    for q in pts.dropFirst() { p.addLine(to: q) }
                }.stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct StatsTab: View {
    @ObservedObject var st = StatsService.shared
    @ObservedObject var bat = BatteryService.shared
    var body: some View {
        GeometryReader { g in
            let n = bat.hasBattery ? 4 : 3
            let wide = g.size.width > 560
            let gap = wide ? DS.Space.xl : DS.Space.m
            let avail = (wide ? g.size.width * 0.6 : g.size.width) - 2 * DS.Space.m
            let sz = max(48, min(88, g.size.height - 52, (avail - gap * CGFloat(n - 1)) / CGFloat(n)))
            HStack(spacing: DS.Space.l) {
                HStack(spacing: gap) {
                    Ring(label: "CPU", value: st.cpu, color: .green, size: sz)
                    Ring(label: "Memory", value: st.mem, color: .orange, size: sz)
                    Ring(label: "Disk", value: st.disk, color: .blue, size: sz)
                    if bat.hasBattery {
                        Ring(label: bat.charging ? "Charging" : "Battery", value: Double(bat.percent) / 100,
                             color: bat.percent <= 20 && !bat.plugged ? .red : .green, size: sz)
                    }
                }
                .layoutPriority(1)
                if wide {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        HStack { SectionLabel(text: "CPU · last minute"); Spacer(); Text("\(Int(st.cpu * 100))%").font(DS.Typo.digits).foregroundStyle(DS.Ink.secondary) }
                        Sparkline(values: st.cpuHistory, tint: .green)
                    }
                    .padding(DS.Space.m).card(DS.Radius.m)
                    .frame(height: sz + 22)
                }
            }
            .padding(.horizontal, DS.Space.m)
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
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Apps

struct AppsTab: View {
    @AppStorage("launchApps") var raw = ""
    static let fallback = ["/System/Applications/Safari.app", "/System/Applications/Notes.app", "/System/Applications/Music.app",
                           "/System/Applications/Calendar.app", "/System/Applications/Utilities/Terminal.app",
                           "/System/Applications/System Settings.app"]
    var paths: [String] {
        if Demo.on { return ["/System/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Notes.app", "/System/Applications/Music.app", "/System/Applications/Calendar.app", "/System/Applications/Utilities/Terminal.app", "/System/Applications/System Settings.app"].filter { FileManager.default.fileExists(atPath: $0) } }
        if raw.isEmpty { return AppsTab.fallback.filter { FileManager.default.fileExists(atPath: $0) } }
        return raw.components(separatedBy: "\n").filter { !$0.isEmpty && $0 != "-" }
    }
    func save(_ p: [String]) { raw = p.isEmpty ? "-" : p.joined(separator: "\n") }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                ForEach(paths, id: \.self) { p in
                    Button {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        NotchState.shared.close()
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 46, height: 46)
                            Text(URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent)
                                .font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.92))
                    .contextMenu { Button("Remove") { save(paths.filter { $0 != p }) } }
                }
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    let op = NSOpenPanel()
                    op.allowedContentTypes = [.application]
                    op.directoryURL = URL(fileURLWithPath: "/Applications")
                    if op.runModal() == .OK, let u = op.url { save(paths + [u.path]) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(width: 46, height: 46)
                            .foregroundStyle(DS.Ink.secondary)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                        Text("Add").font(DS.Typo.caption).foregroundStyle(DS.Ink.tertiary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.92))
            }
            .padding(2)
        }
        .edgeFade()
    }
}

// MARK: Controls (quick toggles + custom shortcuts)

struct ControlTile: View {
    let symbol: String
    let title: String
    let on: Bool
    let tint: Color
    let action: () -> Void
    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height)
            let icon = min(30, max(17, k * 0.27))
            Button(action: action) {
                VStack(spacing: k > 90 ? 8 : 5) {
                    Image(systemName: symbol).font(.system(size: icon, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(title).font(.system(size: k > 90 ? 11.5 : 9.5, weight: .semibold)).lineLimit(2)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.85).padding(.horizontal, 3)
                }
                .foregroundStyle(on ? Color.white : DS.Ink.secondary)
                .frame(width: g.size.width, height: g.size.height)
                .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(on ? tint : DS.Fill.base))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(on ? Color.white.opacity(0.2) : DS.Fill.stroke, lineWidth: 1))
                .shadow(color: on ? tint.opacity(0.45) : .clear, radius: 8, y: 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.93, fill: !on))
            .animation(DS.press, value: on)
        }
    }
}

struct ControlsTab: View {
    @ObservedObject var q = QuickActions.shared
    @ObservedObject var awake = KeepAwake.shared
    @ObservedObject var shortcuts = ShortcutStore.shared
    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > 540
            HStack(spacing: DS.Space.m) {
                VStack(spacing: DS.Space.xs) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: DS.Space.xs) {
                            ForEach(Array(QuickAction.allCases.dropFirst(row * 4).prefix(4))) { a in
                                ControlTile(symbol: a.symbol(on: q.isOn(a)), title: a.title, on: q.isOn(a), tint: a.tint) { q.perform(a) }
                            }
                        }
                    }
                }
                if wide {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        SectionLabel(text: "Shortcuts")
                        if shortcuts.items.isEmpty {
                            EmptyState(symbol: "bolt", title: "No shortcuts yet", subtitle: "Add apps, sites or commands", actionTitle: "Add in Settings") {
                                SettingsWindow.show(.shortcuts)
                            }
                        } else {
                            ScrollView(showsIndicators: false) {
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.xs), GridItem(.flexible(), spacing: DS.Space.xs)], spacing: DS.Space.xs) {
                                    ForEach(shortcuts.items) { s in
                                        Button { shortcuts.run(s) } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: s.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(P.accent).frame(width: 16)
                                                Text(s.name).font(DS.Typo.caption).lineLimit(1)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.horizontal, 9).frame(height: 34)
                                            .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(DS.Fill.base))
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.95))
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: min(240, g.size.width * 0.38))
                    .padding(DS.Space.m).card()
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onAppear { q.refresh() }
    }
}

// MARK: Weather

struct WeatherTab: View {
    @ObservedObject var w = WeatherService.shared
    var body: some View {
        Group {
            if let n = w.now {
                GeometryReader { g in
                    HStack(spacing: DS.Space.xl) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 10) {
                                Image(systemName: n.symbol).symbolRenderingMode(.multicolor).font(.system(size: 40))
                                Text(w.formatted(n.temp)).font(.system(size: 46, weight: .semibold, design: .rounded))
                            }
                            Text(n.text).font(DS.Typo.headline)
                            Text("\(n.city)  ·  H \(w.formatted(n.hi))  L \(w.formatted(n.lo))").font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary)
                        }
                        if g.size.width > 440 {
                            HStack(spacing: DS.Space.m) {
                                ForEach(Array(n.hourly.prefix(g.size.width > 560 ? 6 : 4).enumerated()), id: \.offset) { _, h in
                                    VStack(spacing: 5) {
                                        Text(h.0.formatted(.dateTime.hour())).font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary)
                                        Image(systemName: WeatherNow.symbol(h.2)).symbolRenderingMode(.multicolor).font(.system(size: 16))
                                        Text(w.formatted(h.1)).font(DS.Typo.digits)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DS.Space.m)
                    .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                }
            } else if !w.enabled {
                EmptyState(symbol: "cloud.sun", title: "Weather is off", subtitle: "The only feature besides lyrics that uses the internet. Opt in and pick a city.",
                           actionTitle: "Open Settings") { SettingsWindow.show(.privacy) }
            } else {
                EmptyState(symbol: "cloud.sun", title: w.status.isEmpty ? "Loading…" : w.status)
            }
        }
        .card()
        .onAppear { w.refreshIfNeeded() }
    }
}
