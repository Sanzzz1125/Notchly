import SwiftUI
import AppKit

func mmss(_ s: Double) -> String {
    let v = Int(max(0, s))
    return String(format: "%d:%02d", v / 60, v % 60)
}

// MARK: Home

struct HomeTab: View {
    @AppStorage("homeSide") var side = "calendar"
    @AppStorage("sideWidth") var sideW = 210.0
    @ObservedObject var media = MediaController.shared
    var body: some View {
        GeometryReader { g in
            // The player keeps at least 330 pt; the widget gets exactly the width you chose when there is room.
            let room = g.size.width - 330 - DS.Space.m
            // While a song is showing, the music box gets the whole width.
            let showSide = side != "none" && !media.hasTrack && room >= 140
            let w = min(CGFloat(sideW), max(140, room))
            HStack(spacing: DS.Space.m) {
                MediaCard()
                if showSide { SideWidget(kind: side).frame(width: w) }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

// MARK: Now Playing

struct Scrubber: View {
    let value: Double
    let tint: Color
    let onSeek: (Double) -> Void
    @StateObject private var drag = Box<Double?>(nil)
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        GeometryReader { g in
            let f = min(1, max(0, drag.v ?? value))
            let active = hover.v || drag.v != nil
            let h: CGFloat = active ? 7 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: h)
                Capsule().fill(tint).frame(width: max(h, g.size.width * CGFloat(f)), height: h)
                Circle().fill(Color.white).frame(width: 11, height: 11)
                    .shadow(color: Color.black.opacity(0.4), radius: 2)
                    .offset(x: max(0, g.size.width * CGFloat(f) - 5.5))
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(DS.hoverAnim, value: active)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in drag.v = Double(max(0, min(1, v.location.x / max(1, g.size.width)))) }
                .onEnded { v in
                    onSeek(Double(max(0, min(1, v.location.x / max(1, g.size.width)))))
                    drag.v = nil
                })
            .onHover { hover.v = $0 }
        }
        .frame(height: 16)
    }
}

struct MediaCard: View {
    @ObservedObject var m = MediaController.shared
    @ObservedObject var clock = MediaController.shared.clock
    @ObservedObject var svc = PlaylistService.shared
    @ObservedObject var st = NotchState.shared
    @StateObject private var pickerTrack = Box<SpotifyTrack?>(nil)

    /// The playlist bar only exists while Spotify is the playing app, and only if you turned the feature on.
    private func showBar(_ width: CGFloat) -> Bool {
        m.hasTrack && m.sourceBundle == "com.spotify.client" && svc.featureOn && width >= 360
    }

    var body: some View {
        GeometryReader { g in
            let art = max(60, min(200, g.size.height - 2 * DS.Space.m))
            let compact = g.size.height < 138
            let bar = showBar(g.size.width)
            HStack(spacing: DS.Space.m + 2) {
                artwork(art)
                if m.hasTrack { info(compact, g.size.width - art - 2 * DS.Space.m - 14) } else { idle }
                if bar {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 6)
                    SpotifyBar(compact: compact)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(DS.Space.m)
            .frame(width: g.size.width, height: g.size.height)
            .animation(Motion.open, value: bar)
        }
        .card()
        .overlay {
            if st.pickerOpen {
                PlaylistPicker(track: pickerTrack.v) { withAnimation(Motion.close) { st.pickerOpen = false } }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { PlaylistToast() }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .onChange(of: st.pickerOpen) { _, open in
            guard open else { return }
            pickerTrack.v = nil
            Task { pickerTrack.v = await svc.captureTrack() }     // the song you saw when you opened the picker
        }
    }

    func artwork(_ art: CGFloat) -> some View {
        Button { m.openSource() } label: {
            ZStack {
                LinearGradient(colors: [m.tint.opacity(0.75), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let a = m.art {
                    Image(nsImage: a).resizable().scaledToFill().transition(.opacity)
                } else if let ic = m.sourceIcon {
                    Image(nsImage: ic).resizable().scaledToFit().padding(art * 0.14).transition(.opacity)
                } else {
                    Image(systemName: "music.note").font(.system(size: art * 0.3, weight: .light)).foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: art, height: art)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m + 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m + 2, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: m.tint.opacity(m.hasTrack ? 0.5 : 0), radius: 14, y: 6)
            .scaleEffect(m.isPlaying ? 1 : 0.93)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: m.isPlaying)
            .animation(.easeInOut(duration: 0.35), value: m.art == nil)
        }
        .buttonStyle(PressStyle(radius: DS.Radius.m + 2, scale: 0.97, fill: false))
        .help(m.source.isEmpty ? "Open player" : "Open \(m.source)")
    }

    var idle: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Nothing playing").font(DS.Typo.title)
            Text("Play something in any app").font(DS.Typo.body).foregroundStyle(DS.Ink.secondary)
            HStack(spacing: DS.Space.xs) {
                Chip(title: "Spotify", symbol: "music.note") { NSWorkspace.shared.launchApplication("Spotify") }
                Chip(title: "Music", symbol: "music.quarternote.3") { NSWorkspace.shared.launchApplication("Music") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func info(_ compact: Bool, _ width: CGFloat) -> some View {
        let frac = clock.duration > 0 ? clock.position / clock.duration : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(m.title).font(DS.Typo.title).lineLimit(1)
            if !(compact && !clock.lyric.isEmpty) {
                Text(m.artist.isEmpty ? m.source : m.artist).font(DS.Typo.body).foregroundStyle(DS.Ink.secondary).lineLimit(1)
            }
            if !clock.lyric.isEmpty {
                Text(clock.lyric).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(m.tint).lineLimit(1)
                    .id(clock.lyric)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)), removal: .opacity))
            }
            Spacer(minLength: 0)
            if clock.duration > 0 { Scrubber(value: frac, tint: m.tint) { m.seek($0) } }
            if !compact && clock.duration > 0 {
                HStack {
                    Text(mmss(frac * clock.duration))
                    Spacer()
                    Text("-" + mmss(max(0, clock.duration - frac * clock.duration)))
                }
                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(DS.Ink.tertiary)
            }
            HStack(spacing: DS.Space.l) {
                Spacer(minLength: 0)
                IconButton(symbol: "backward.fill", size: 34, icon: 15, tint: DS.Ink.primary) { m.previous() }
                Button { m.playPause() } label: {
                    Image(systemName: m.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.black)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                        .background(Circle().fill(Color.white))
                        .shadow(color: m.tint.opacity(0.45), radius: 8, y: 2)
                }
                .buttonStyle(PressStyle(radius: 19, scale: 0.9, fill: false))
                IconButton(symbol: "forward.fill", size: 34, icon: 15, tint: DS.Ink.primary) { m.next() }
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: clock.lyric)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Side widgets

struct SideWidget: View {
    let kind: String
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionLabel(text: title)
            switch kind {
            case "reminders": RemindersList(limit: 4, compact: true)
            case "stats": StatsMini()
            case "weather": WeatherMini()
            default: CalendarList(limit: 3, soon: true)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .card()
    }
    var title: String {
        switch kind {
        case "reminders": return "To do"
        case "stats": return "System"
        case "weather": return "Weather"
        default: return "Up next"
        }
    }
}

struct StatsMini: View {
    @ObservedObject var st = StatsService.shared
    @ObservedObject var bat = BatteryService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            bar("CPU", st.cpu, .green)
            bar("Memory", st.mem, .orange)
            bar("Disk", st.disk, .blue)
            if bat.hasBattery { bar("Battery", Double(bat.percent) / 100, bat.percent <= 20 ? .red : .green) }
        }
        .onAppear { st.sample() }
    }
    func bar(_ n: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(n); Spacer(); Text("\(Int(v * 100))%").monospacedDigit() }
                .font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary)
            Meter(value: v, tint: c, height: 4)
        }
    }
}

struct WeatherMini: View {
    @ObservedObject var w = WeatherService.shared
    var body: some View {
        Group {
            if let n = w.now {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: n.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
                        Text(w.formatted(n.temp)).font(.system(size: 30, weight: .semibold, design: .rounded))
                    }
                    Text(n.text).font(DS.Typo.bodyEm)
                    Text("H \(w.formatted(n.hi))  L \(w.formatted(n.lo))").font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary)
                    Text(n.city).font(DS.Typo.caption).foregroundStyle(DS.Ink.tertiary).lineLimit(1)
                }
            } else {
                EmptyState(symbol: "cloud.sun", title: WeatherService.shared.enabled ? (w.status.isEmpty ? "Loading…" : w.status) : "Weather is off",
                           subtitle: WeatherService.shared.enabled ? "" : "Turn it on in Settings → Privacy")
            }
        }
        .onAppear { w.refreshIfNeeded() }
    }
}
