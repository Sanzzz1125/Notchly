import SwiftUI
import AppKit

final class MediaController: ObservableObject {
    static let shared = MediaController()
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var hasTrack = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var art: NSImage?
    @Published var tint: Color = .white
    @Published var source = ""
    @Published var lyric = ""
    @Published var sourceBundle = ""
    private var bridgeLive = false
    private var lastBridgeLine = Date.distantPast
    private var bridgeProc: Process?
    private var bridgeTries = 0

    private var artURL = ""
    private var trackKey = ""
    private var lyrics: [(Double, String)] = []
    private let q = DispatchQueue(label: "notchly.media")
    private var busy = false

    struct Info { var app: String; var playing: Bool; var title: String; var artist: String; var album: String; var pos: Double; var dur: Double; var art: String; var bundle: String = ""; var artData: Data? = nil }

    func start() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        startBridge()
        poll()
    }

    // MARK: System-wide bridge (MediaRemote through perl)
    private static let perlScript = "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die 'load'; my $s = DynaLoader::dl_find_symbol($l, $ARGV[1]) or die 'sym'; my $f = DynaLoader::dl_install_xsub('main::fn', $s); &$f();"

    private var bridgeLib: String? {
        guard let dir = Bundle.main.privateFrameworksPath else { return nil }
        let p = dir + "/libNotchlyMedia.dylib"
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    private func startBridge() {
        guard let lib = bridgeLib, bridgeTries < 6, !Background.paused, bridgeProc?.isRunning != true else { return }
        bridgeTries += 1
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", MediaController.perlScript, lib, "notchly_media_stream"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        var buf = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            buf.append(d)
            while let nl = buf.firstIndex(of: 10) {
                let line = buf.subdata(in: buf.startIndex..<nl)
                buf.removeSubrange(buf.startIndex...nl)
                DispatchQueue.main.async { self?.handleLine(line) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.bridgeLive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self?.startBridge() }
            }
        }
        do { try p.run(); bridgeProc = p } catch {}
    }

    static func category(_ b: String) -> String {
        let l = b.lowercased()
        let music = ["com.spotify.client", "com.apple.music", "com.apple.itunes", "com.tidal", "com.amazon.music", "com.deezer", "com.apple.podcasts", "com.soundcloud", "fm.", "com.sonos"]
        if music.contains(where: { l.hasPrefix($0) }) { return "music" }
        let video = ["org.videolan", "com.apple.quicktime", "com.colliderli.iina", "com.apple.tv", "io.mpv", "com.netflix", "tv.plex"]
        if video.contains(where: { l.hasPrefix($0) }) { return "video" }
        let browsers = ["chrome", "safari", "firefox", "thebrowser", "edgemac", "brave", "opera", "vivaldi", "browser", "comet", "perplexity", "webkit", "arc"]
        if browsers.contains(where: { l.contains($0) }) { return "browser" }
        return "other"
    }
    static func allowed(_ b: String) -> Bool {
        switch category(b) {
        case "music": return P.bool("srcMusic")
        case "video": return P.bool("srcVideo")
        case "browser": return P.bool("srcBrowsers")
        default: return P.bool("srcOther")
        }
    }
    static func appName(_ b: String) -> String {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
            return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
        }
        return b
    }

    private func handleLine(_ line: Data) {
        guard let j = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        bridgeLive = true
        lastBridgeLine = Date()
        let title = j["title"] as? String ?? ""
        let bundle = j["app"] as? String ?? ""
        if title.isEmpty || !MediaController.allowed(bundle) { clear(); return }
        var info = Info(app: MediaController.appName(bundle), playing: j["playing"] as? Bool ?? false, title: title,
                        artist: j["artist"] as? String ?? "", album: j["album"] as? String ?? "",
                        pos: j["elapsed"] as? Double ?? 0, dur: j["duration"] as? Double ?? 0, art: "")
        info.bundle = bundle
        apply(info)
        if let b64 = j["art"] as? String, let d = Data(base64Encoded: b64), let img = NSImage(data: d) {
            art = img
            tint = MediaController.average(img)
        }
    }

    private var pollN = 0
    func setPaused(_ p: Bool) {
        if p { bridgeProc?.terminate(); bridgeProc = nil; bridgeLive = false }
        else { bridgeTries = 0; startBridge() }
    }
    private func poll() {
        if Background.paused { return }
        pollN += 1
        if Eco.on && pollN % 3 != 0 { return }
        if busy { return }
        if bridgeLive && Date().timeIntervalSince(lastBridgeLine) < 5 { return }
        let ids = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        var apps: [String] = []
        if ids.contains("com.spotify.client") { apps.append("Spotify") }
        if ids.contains("com.apple.Music") { apps.append("Music") }
        if apps.isEmpty { clear(); return }
        busy = true
        q.async { [weak self] in
            var best: Info?
            for a in apps {
                if let i = MediaController.query(a) {
                    if best == nil { best = i }
                    if i.playing { best = i; break }
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if let b = best { self.apply(b) } else { self.clear() }
            }
        }
    }

    private func clear() {
        if hasTrack || isPlaying {
            hasTrack = false; isPlaying = false; title = ""; artist = ""; art = nil; lyric = ""; trackKey = ""; source = ""
        }
    }

    private func apply(_ i: Info) {
        source = i.app
        sourceBundle = i.bundle
        isPlaying = i.playing
        hasTrack = true
        position = i.pos
        duration = i.dur
        let key = i.app + i.title + i.artist
        if key != trackKey {
            let first = trackKey.isEmpty
            trackKey = key
            title = i.title; artist = i.artist; album = i.album
            lyrics = []; lyric = ""
            loadArt(i.art)
            if P.bool("lyrics") && P.bool("allowNetwork") { loadLyrics(i) }
            if !first && i.playing && P.bool("trackAlerts") {
                NotchState.shared.post(IslandAlert(symbol: "music.note", tint: tint, title: i.title, detail: i.artist, duration: 2.8))
            }
        }
        if !lyrics.isEmpty {
            var cur = ""
            for l in lyrics where l.0 <= i.pos + 0.3 { cur = l.1 }
            if cur != lyric { lyric = cur }
        }
    }

    private func loadArt(_ url: String) {
        if url.isEmpty { artURL = ""; art = nil; tint = .white; return }
        if url == artURL { return }
        artURL = url
        art = nil
        tint = .white
        guard P.bool("allowNetwork"), let u = URL(string: url), !url.isEmpty else { return }
        URLSession.shared.dataTask(with: u) { [weak self] d, _, _ in
            guard let d = d, let img = NSImage(data: d) else { return }
            let c = MediaController.average(img)
            DispatchQueue.main.async { self?.art = img; self?.tint = c }
        }.resume()
    }

    private func loadLyrics(_ i: Info) {
        let key = trackKey
        let clean = i.title.replacingOccurrences(of: "\\(.*?\\)|\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let firstArtist = (i.artist.components(separatedBy: CharacterSet(charactersIn: ",&;")).first ?? i.artist)
            .trimmingCharacters(in: .whitespaces)
        let tries: [[URLQueryItem]] = [
            [URLQueryItem(name: "track_name", value: i.title), URLQueryItem(name: "artist_name", value: i.artist)],
            [URLQueryItem(name: "track_name", value: clean), URLQueryItem(name: "artist_name", value: firstArtist)],
            [URLQueryItem(name: "q", value: clean + " " + firstArtist)],
        ]
        attemptLyrics(tries, 0, key, i.dur)
    }

    private func attemptLyrics(_ tries: [[URLQueryItem]], _ n: Int, _ key: String, _ dur: Double) {
        guard n < tries.count, var c = URLComponents(string: "https://lrclib.net/api/search") else { return }
        c.queryItems = tries[n]
        guard let u = c.url else { return }
        var req = URLRequest(url: u)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] d, _, _ in
            var best: [(Double, String)] = []
            if let d = d, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
                let cands = arr.filter { (($0["syncedLyrics"] as? String) ?? "").isEmpty == false }
                let pick = cands.min { abs(($0["duration"] as? Double ?? 0) - dur) < abs(($1["duration"] as? Double ?? 0) - dur) }
                if let s = pick?["syncedLyrics"] as? String { best = MediaController.parseLRC(s) }
            }
            DispatchQueue.main.async {
                guard let self = self, self.trackKey == key else { return }
                if best.isEmpty { self.attemptLyrics(tries, n + 1, key, dur) } else { self.lyrics = best }
            }
        }.resume()
    }

    static func parseLRC(_ s: String) -> [(Double, String)] {
        var out: [(Double, String)] = []
        for line in s.components(separatedBy: "\n") {
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            let parts = stamp.components(separatedBy: ":")
            guard parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) else { continue }
            let text = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            out.append((m * 60 + sec, text))
        }
        return out
    }

    // MARK: Controls
    func playPause() { isPlaying.toggle(); send(2, "playpause") }
    func next() { send(4, "next track") }
    func previous() { send(5, "previous track") }
    func seek(_ frac: Double) {
        let s = max(0, min(1, frac)) * duration
        position = s
        send(100, "set player position to \(s)", seek: s)
    }
    func openSource() {
        if !sourceBundle.isEmpty, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: sourceBundle) {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        NSWorkspace.shared.launchApplication(source.isEmpty ? "Music" : source)
    }
    private func send(_ cmd: Int, _ script: String, seek: Double = 0) {
        if bridgeLive, let lib = bridgeLib {
            q.async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                p.arguments = ["-e", MediaController.perlScript, lib, "notchly_media_send"]
                var env = ProcessInfo.processInfo.environment
                env["NOTCHLY_CMD"] = String(cmd)
                env["NOTCHLY_SEEK"] = String(seek)
                p.environment = env
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
            }
            return
        }
        let app = source.isEmpty ? "Music" : source
        q.async { _ = MediaController.osa("tell application \"\(app)\" to \(script)") }
    }

    // MARK: Helpers
    static func osa(_ script: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func query(_ app: String) -> Info? {
        let artExpr = app == "Spotify" ? "(artwork url of current track)" : "\"\""
        let durExpr = "((duration of current track) as string)"
        let script = """
        tell application "\(app)"
        if player state is stopped then return "stopped"
        return (player state as string) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track) & "||" & (player position as string) & "||" & \(durExpr) & "||" & \(artExpr)
        end tell
        """
        guard let out = osa(script), out != "stopped" else { return nil }
        let p = out.components(separatedBy: "||")
        if p.count < 7 { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        var dur = num(p[5])
        if app == "Spotify" { dur /= 1000 }
        return Info(app: app, playing: p[0] == "playing", title: p[1], artist: p[2], album: p[3], pos: num(p[4]), dur: dur, art: p[6])
    }

    static func average(_ img: NSImage) -> Color {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        if !ok { return .white }
        var r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let mx = max(r, max(g, b))
        if mx < 0.6 && mx > 0.01 { let k = 0.6 / mx; r *= k; g *= k; b *= k }
        if mx <= 0.01 { return .white }
        return Color(red: min(r, 1), green: min(g, 1), blue: min(b, 1))
    }
}
