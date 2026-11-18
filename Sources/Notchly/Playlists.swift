import SwiftUI
import AppKit
import Combine

// MARK: Stash (songs you collected, kept on this Mac only)

struct StashItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var uri: String
    var title: String
    var artist: String
    var art: String
    var added = Date()
}

final class StashStore: ObservableObject {
    static let shared = StashStore()
    @Published var items: [StashItem] = []
    /// Last deleted batch, so Delete can be undone for a few seconds.
    @Published var undoBatch: [StashItem] = []
    private var undoWork: DispatchWorkItem?

    private var fileURL: URL {
        if !P.str("spotifyAPI").isEmpty { return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("notchly-test-stash.json") }   // tests never touch your real Stash
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Notchly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stash.json")
    }

    init() {
        if Demo.on {
            if Demo.empty { return }
            let names = [("Golden Hour", "Neon Harbor"), ("Paper Planes", "The Aurora Club"), ("Slow Burn", "Mara Vale"), ("Night Drive", "Kite & Compass"),
                         ("Late Bloom", "Juno Fields"), ("Static Hearts", "Velvet Room")]
            items = names.enumerated().map { StashItem(uri: "spotify:track:DEMO\($0.offset)", title: $0.element.0, artist: $0.element.1, art: "",
                                                        added: Date().addingTimeInterval(-Double($0.offset) * 3600)) }
            return
        }
        if !P.str("spotifyAPI").isEmpty { try? FileManager.default.removeItem(at: fileURL) }
        if let d = try? Data(contentsOf: fileURL), let a = try? JSONDecoder().decode([StashItem].self, from: d) { items = a }
    }

    private func save() {
        if Demo.on { return }
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: fileURL, options: .atomic) }
    }

    func contains(_ uri: String) -> Bool { items.contains { $0.uri == uri } }

    /// Returns false if it was already there.
    @discardableResult
    func add(_ t: SpotifyTrack) -> Bool {
        guard !contains(t.uri) else { return false }
        withAnimation(Motion.tab) { items.insert(StashItem(uri: t.uri, title: t.title, artist: t.artist, art: t.art), at: 0) }
        if items.count > 500 { items = Array(items.prefix(500)) }
        save()
        return true
    }

    func remove(_ ids: Set<UUID>) {
        let gone = items.filter { ids.contains($0.id) }
        guard !gone.isEmpty else { return }
        withAnimation(Motion.tab) { items.removeAll { ids.contains($0.id) } }
        undoBatch = gone
        save()
        undoWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.undoBatch = [] } }
        undoWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }

    func undo() {
        guard !undoBatch.isEmpty else { return }
        withAnimation(Motion.tab) {
            items.append(contentsOf: undoBatch.filter { b in !items.contains { $0.uri == b.uri } })
            items.sort { $0.added > $1.added }
            undoBatch = []
        }
        save()
    }

    func clear() { remove(Set(items.map { $0.id })) }
}

// MARK: Playlist service

@MainActor
final class PlaylistService: ObservableObject {
    static let shared = PlaylistService()

    nonisolated(unsafe) static var testTrack: SpotifyTrack?
    @Published var playlists: [SPPlaylist] = []
    @Published var loading = false
    @Published var current: SpotifyTrack?
    @Published var currentInDefault = false
    @Published var busy = false
    @Published var toast: String?
    private var loadedAt = Date.distantPast
    private var known: [String: (uris: Set<String>, at: Date)] = [:]
    private var toastWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    var featureOn: Bool { SpotifyAuth.shared.enabled }
    var available: Bool { featureOn && SpotifyAuth.shared.signedIn }
    var defaultID: String { P.str("spotifyDefaultID") }
    var defaultName: String { let n = P.str("spotifyDefaultName"); return n.isEmpty ? "your playlist" : n }

    /// Follow the playing song so the ✓ state and the song we add are always the one on screen.
    func start() {
        let m = MediaController.shared
        Publishers.CombineLatest(m.$title.removeDuplicates(), m.$sourceBundle.removeDuplicates())
            .debounce(for: .milliseconds(450), scheduler: DispatchQueue.main)
            .sink { [weak self] _, bundle in
                guard let self = self, bundle == "com.spotify.client" || Demo.on else { return }
                Task { await self.refreshCurrent() }
            }.store(in: &bag)
    }

    // MARK: Current song

    func captureTrack() async -> SpotifyTrack? {
        if Demo.on { return SpotifyTrack(uri: "spotify:track:DEMOCURRENT", title: MediaController.shared.title, artist: MediaController.shared.artist, art: "") }
        if let t = PlaylistService.testTrack { return t }          // test harness only (scripts/test-spotify.py)
        return await Task.detached { SpotifyTrack.current() }.value
    }

    func refreshCurrent() async {
        guard available else { return }
        if defaultID.isEmpty { await loadPlaylists() }      // first run: picks the playlist starting with "Movzzz" automatically
        current = await captureTrack()
        updateInDefault()
        if !defaultID.isEmpty, let c = current, c.isAddable { await ensureKnown(defaultID) }
    }

    private func updateInDefault() {
        guard let c = current, !defaultID.isEmpty else { currentInDefault = false; return }
        currentInDefault = known[defaultID]?.uris.contains(c.uri) ?? false
    }

    // MARK: Playlist list

    func loadPlaylists(force: Bool = false) async {
        guard available, !loading else { return }
        if Demo.on { playlists = PlaylistService.demoLists(); return }
        if !force && !playlists.isEmpty && Date().timeIntervalSince(loadedAt) < 600 { return }
        loading = true
        defer { loading = false }
        do {
            playlists = try await SpotifyAPI.shared.playlists()
            loadedAt = Date()
            if defaultID.isEmpty, let m = playlists.first(where: { $0.name.lowercased().hasPrefix("movzzz") }) {
                UserDefaults.standard.set(m.id, forKey: "spotifyDefaultID"); UserDefaults.standard.set(m.name, forKey: "spotifyDefaultName")
            }
        } catch let e as SpotifyError { show(e.message) } catch { show("Couldn't load playlists") }
    }

    static func demoLists() -> [SPPlaylist] {
        ["Movzzzzzz", "Gym", "Chill evenings", "Road trip", "Focus", "Throwbacks", "Sunday morning", "Party", "Discover", "Jazz nights", "Workout 2", "Study", "Rainy day", "Hits", "Indie"].enumerated()
            .map { SPPlaylist(id: "demo\($0.offset)", name: $0.element, tracks: 12 + $0.offset * 7, imageURL: "", isPublic: false) }
    }

    /// Songs already in a playlist, so we never add a duplicate. Cached for 5 minutes; adds update it.
    private func ensureKnown(_ id: String) async {
        if Demo.on { if known[id] == nil { known[id] = ([], Date()) }; return }
        if let k = known[id], Date().timeIntervalSince(k.at) < 300 { return }
        if let u = try? await SpotifyAPI.shared.trackURIs(in: id) { known[id] = (u, Date()); updateInDefault() }
    }

    // MARK: Adding

    func addToDefault() {
        guard available, !busy else { return }
        if defaultID.isEmpty {
            Task {
                await loadPlaylists(force: true)
                guard !defaultID.isEmpty else { show("Choose a default playlist in Settings → Music → Playlists"); return }
                add(to: SPPlaylist(id: defaultID, name: defaultName, tracks: 0, imageURL: "", isPublic: false), track: nil)
            }
            return
        }
        add(to: SPPlaylist(id: defaultID, name: defaultName, tracks: 0, imageURL: "", isPublic: false), track: nil)
    }

    /// `track` is the song captured when you opened the picker; nil = capture right now.
    func add(to p: SPPlaylist, track: SpotifyTrack?) {
        guard available, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            var found = track
            if found == nil { found = await captureTrack() }
            guard let t = found, t.isAddable else {
                show("Nothing to add: play a normal song in Spotify first (ads and local files can't be added)"); return
            }
            await ensureKnown(p.id)
            if known[p.id]?.uris.contains(t.uri) == true { updateInDefault(); return }     // already there: silently skip
            do {
                if !Demo.on { try await SpotifyAPI.shared.add([t.uri], to: p.id) } else { try? await Task.sleep(nanoseconds: 250_000_000) }
                var k = known[p.id] ?? ([], Date())
                k.uris.insert(t.uri); known[p.id] = k
                if current?.uri == t.uri { updateInDefault() }
                touchRecent(p.id)
            } catch let e as SpotifyError { show(e.message) } catch { show("Couldn't add the song") }
        }
    }

    func stashCurrent() {
        Task {
            guard let t = await captureTrack(), t.isAddable else { show("Nothing to stash: play a normal song in Spotify first"); return }
            StashStore.shared.add(t)
        }
    }

    /// New playlist, then the song into it.
    func createAndAdd(name: String, track: SpotifyTrack?) {
        guard available, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            var found = track
            if found == nil { found = await captureTrack() }
            guard let t = found, t.isAddable else { show("Nothing to add: play a normal song first"); return }
            do {
                let p: SPPlaylist
                if Demo.on { p = SPPlaylist(id: "demonew", name: name, tracks: 1, imageURL: "", isPublic: false) }
                else { p = try await SpotifyAPI.shared.createPlaylist(name: name, isPublic: false); try await SpotifyAPI.shared.add([t.uri], to: p.id) }
                playlists.insert(p, at: 0); known[p.id] = ([t.uri], Date()); touchRecent(p.id)
            } catch let e as SpotifyError { show(e.message) } catch { show("Couldn't create the playlist") }
        }
    }

    func setDefault(_ p: SPPlaylist) {
        UserDefaults.standard.set(p.id, forKey: "spotifyDefaultID"); UserDefaults.standard.set(p.name, forKey: "spotifyDefaultName")
        objectWillChange.send()
        updateInDefault()
        Task { await ensureKnown(p.id); updateInDefault() }
    }

    // MARK: Recents + errors

    var recent: [String] { UserDefaults.standard.stringArray(forKey: "spotifyRecent") ?? [] }
    private func touchRecent(_ id: String) {
        var r = recent.filter { $0 != id }; r.insert(id, at: 0)
        UserDefaults.standard.set(Array(r.prefix(8)), forKey: "spotifyRecent")
    }

    /// Orders playlists: default first, then recently used, then the rest in Spotify's order.
    func ordered(_ query: String = "") -> [SPPlaylist] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = playlists
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) } }
        let rec = recent
        let did = defaultID
        func rank(_ p: SPPlaylist) -> Int { p.id == did ? 0 : (rec.firstIndex(of: p.id).map { $0 + 1 } ?? 100) }
        return list.sorted { rank($0) < rank($1) }
    }

    /// Errors are the only thing we announce: successful adds stay quiet.
    func show(_ msg: String) {
        withAnimation(Motion.alert) { toast = msg }
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation(Motion.close) { self?.toast = nil } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }
}

extension SpotifyAPI {
    /// Track URIs in a playlist (up to ~3000), for duplicate detection. Accepts both the old and new response shapes.
    func trackURIs(in playlistID: String) async throws -> Set<String> {
        var out = Set<String>()
        var offset = 0
        while offset < 3000 {
            let (_, j) = try await callPublic("GET", "/playlists/\(playlistID)/items", query: ["limit": "100", "offset": String(offset)])
            guard let d = j as? [String: Any], let items = d["items"] as? [[String: Any]] else { break }
            for it in items {
                let t = (it["item"] as? [String: Any]) ?? (it["track"] as? [String: Any])
                if let u = t?["uri"] as? String { out.insert(u) }
            }
            if items.count < 100 || d["next"] == nil || d["next"] is NSNull { break }
            offset += 100
        }
        return out
    }
}
