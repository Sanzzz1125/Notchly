import SwiftUI
import AppKit
import CryptoKit
import Security

// Spotify playlists. Opt-in (Settings → Privacy / Playlists), off by default.
// Talks only to accounts.spotify.com and api.spotify.com, only when you click, open the picker or sign in.

enum SpotifyError: Error {
    case notEnabled, noClientID, notSignedIn, offline, cancelled
    case rateLimited(Int)
    case http(Int, String)
    case badResponse

    var message: String {
        switch self {
        case .notEnabled: return "Turn on Spotify playlists in Settings → Playlists"
        case .noClientID: return "Paste your Spotify Client ID in Settings → Playlists"
        case .notSignedIn: return "Sign in to Spotify in Settings → Playlists"
        case .offline: return "No internet connection"
        case .cancelled: return "Sign-in cancelled"
        case .rateLimited(let s): return "Spotify is busy, try again in \(max(1, s))s"
        case .badResponse: return "Unexpected answer from Spotify"
        case .http(let code, let msg):
            switch code {
            case 401: return "Spotify sign-in expired. Sign in again"
            case 403: return msg.isEmpty ? "Spotify refused this (is Premium active on the app owner's account?)" : "Spotify refused: \(msg)"
            case 404: return "Playlist not found"
            default: return msg.isEmpty ? "Spotify error \(code)" : "Spotify: \(msg)"
            }
        }
    }
}

struct SPPlaylist: Identifiable, Hashable {
    let id: String
    var name: String
    var tracks: Int
    var imageURL: String
    var isPublic: Bool
}

enum Keychain {
    /// Test harness (-spotifyAPI override) keeps tokens in memory: no Keychain prompts, nothing real is touched.
    private static var testMode: Bool { !P.str("spotifyAPI").isEmpty }
    private static var memory: [String: Data] = [:]
    static var service: String { P.str("spotifyAPI").isEmpty ? "com.sanketh.Notchly.spotify" : "com.sanketh.Notchly.spotify.test" }
    static func set(_ data: Data, _ account: String) {
        if testMode { memory[account] = data; return }
        delete(account)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: data]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func get(_ account: String) -> Data? {
        if testMode { return memory[account] }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func delete(_ account: String) {
        if testMode { memory[account] = nil; return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

private struct Tokens: Codable { var access: String; var refresh: String; var expires: Date }

final class SpotifyAuth: ObservableObject {
    static let shared = SpotifyAuth()
    static let redirect = "notchly://callback"
    static let scopes = "playlist-read-private playlist-read-collaborative playlist-modify-private playlist-modify-public"

    @Published var signedIn = false
    @Published var userName = ""
    @Published var userID = ""
    @Published var busy = false
    @Published var status = ""
    private var tokens: Tokens?
    private var verifier = ""
    private var state = ""

    var enabled: Bool { P.bool("spotifyEnabled") && P.bool("allowNetwork") }
    var clientID: String { P.str("spotifyClientID").trimmingCharacters(in: .whitespacesAndNewlines) }
    var apiBase: String { let o = P.str("spotifyAPI"); return o.isEmpty ? "https://api.spotify.com/v1" : o }
    var accountsBase: String { let o = P.str("spotifyAccounts"); return o.isEmpty ? "https://accounts.spotify.com" : o }

    // MARK: Start-up

    /// Reading the Keychain can pop up a macOS permission dialog (after every rebuild of an ad-hoc signed app),
    /// and that call blocks until you answer. So it never runs on the main thread: Notchly always starts.
    @Published var keychainPending = false
    func start() {
        if Demo.on { signedIn = true; userName = "Demo"; userID = "demo"; return }
        guard P.bool("spotifyEnabled") || UserDefaults.standard.string(forKey: "spotifyUserID") != nil else { return }
        keychainPending = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let d = Keychain.get("tokens")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.keychainPending = false
                if let d = d, let t = try? JSONDecoder().decode(Tokens.self, from: d) {
                    self.tokens = t
                    self.signedIn = true
                    self.userName = UserDefaults.standard.string(forKey: "spotifyUserName") ?? ""
                    self.userID = UserDefaults.standard.string(forKey: "spotifyUserID") ?? ""
                }
            }
        }
    }

    // MARK: PKCE sign-in

    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func random(_ n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func signIn() {
        guard P.bool("spotifyEnabled") else { fail(.notEnabled); return }
        guard P.bool("allowNetwork") else { status = "Internet access is off (Settings → Privacy)"; return }
        guard !clientID.isEmpty else { fail(.noClientID); return }
        verifier = SpotifyAuth.random(64)
        state = SpotifyAuth.random(16)
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let params: [(String, String)] = [
            ("response_type", "code"), ("client_id", clientID), ("redirect_uri", SpotifyAuth.redirect), ("scope", SpotifyAuth.scopes),
            ("code_challenge_method", "S256"), ("code_challenge", SpotifyAuth.challenge(for: verifier)), ("state", state),
        ]
        let query = params.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        guard let authURL = URL(string: accountsBase + "/authorize?" + query) else { fail(.badResponse); return }
        busy = true
        status = "Waiting for you to approve in the browser…"
        if P.bool("spotifyNoBrowser") { print("SPOTIFY_AUTH_URL \(authURL.absoluteString)"); fflush(stdout) }   // test harness only
        else { NSWorkspace.shared.open(authURL) }
        // give up waiting after 5 minutes
        let s = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            if let self = self, self.busy, self.state == s { self.busy = false; self.state = ""; self.status = "Sign-in timed out" }
        }
    }

    /// Called by AppDelegate for notchly://callback?code=…&state=…
    func handle(_ url: URL) {
        guard url.scheme == "notchly", url.host == "callback" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String? { items.first { $0.name == k }?.value }
        guard !state.isEmpty, v("state") == state else { fail(.http(400, "unexpected sign-in response")); return }
        state = ""
        if let e = v("error") { busy = false; status = e == "access_denied" ? SpotifyError.cancelled.message : "Spotify: \(e)"; return }
        guard let code = v("code") else { fail(.badResponse); return }
        Task { await exchange(code) }
    }

    private func exchange(_ code: String) async {
        do {
            let r = try await form("/api/token", ["grant_type": "authorization_code", "code": code, "redirect_uri": SpotifyAuth.redirect,
                                                  "client_id": clientID, "code_verifier": verifier])
            try store(r, keepRefresh: nil)
            verifier = ""
            SpotifyAPI.shared.resetUser()
            let me = try await SpotifyAPI.shared.me()
            await MainActor.run {
                userName = me.name; userID = me.id
                UserDefaults.standard.set(me.name, forKey: "spotifyUserName"); UserDefaults.standard.set(me.id, forKey: "spotifyUserID")
                signedIn = true; busy = false; status = "Signed in as \(me.name)"
            }
        } catch let e as SpotifyError { await MainActor.run { fail(e) } }
        catch { await MainActor.run { fail(.offline) } }
    }

    /// The refresh token is dead (revoked, expired or app removed in Spotify): sign out so the UI tells the truth.
    func expireSession() {
        guard signedIn else { return }
        signOut()
        status = SpotifyError.http(401, "").message
    }

    func signOut() {
        tokens = nil
        DispatchQueue.global(qos: .utility).async { Keychain.delete("tokens") }
        signedIn = false; userName = ""; userID = ""; busy = false; status = "Signed out"
        UserDefaults.standard.removeObject(forKey: "spotifyUserName"); UserDefaults.standard.removeObject(forKey: "spotifyUserID")
    }

    private func fail(_ e: SpotifyError) {
        busy = false; status = e.message
        if case .http(401, _) = e { signOut(); status = e.message }
    }

    // MARK: Tokens

    private func store(_ json: [String: Any], keepRefresh: String?) throws {
        guard let access = json["access_token"] as? String else { throw SpotifyError.badResponse }
        let refresh = (json["refresh_token"] as? String) ?? keepRefresh ?? ""
        let ttl = (json["expires_in"] as? Double) ?? 3600
        let t = Tokens(access: access, refresh: refresh, expires: Date().addingTimeInterval(ttl))
        tokens = t
        if let d = try? JSONEncoder().encode(t) { Keychain.set(d, "tokens") }
    }

    /// A valid access token, refreshing silently when it is about to expire.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let t = tokens else { throw SpotifyError.notSignedIn }
        if !forceRefresh && t.expires.timeIntervalSinceNow > 60 { return t.access }
        guard !t.refresh.isEmpty else { throw SpotifyError.http(401, "") }
        let r = try await form("/api/token", ["grant_type": "refresh_token", "refresh_token": t.refresh, "client_id": clientID])
        try store(r, keepRefresh: t.refresh)
        return tokens?.access ?? ""
    }

    private func form(_ path: String, _ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: accountsBase + path)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        req.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw SpotifyError.offline }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code == 400, (json["error"] as? String) == "invalid_grant" { throw SpotifyError.http(401, "") }
        if code != 200 { throw SpotifyError.http(code, (json["error_description"] as? String) ?? "") }
        return json
    }
}

final class SpotifyAPI {
    static let shared = SpotifyAPI()
    private var auth: SpotifyAuth { SpotifyAuth.shared }

    private func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> (Int, Any?) {
        do { return try await perform(method, path, query: query, body: body) }
        catch SpotifyError.http(let code, let msg) where code == 401 {
            await MainActor.run { auth.expireSession() }
            throw SpotifyError.http(code, msg)
        }
    }

    /// One authorised request. Refreshes the token once on 401, waits out a short 429.
    private func perform(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> (Int, Any?) {
        guard auth.enabled else { throw SpotifyError.notEnabled }
        var attempt = 0
        var force = false
        while true {
            attempt += 1
            var c = URLComponents(string: auth.apiBase + path)!
            if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: c.url!)
            req.httpMethod = method
            req.timeoutInterval = 15
            req.setValue("Bearer \(try await auth.accessToken(forceRefresh: force))", forHTTPHeaderField: "Authorization")
            if let b = body { req.httpBody = try? JSONSerialization.data(withJSONObject: b); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, resp): (Data, URLResponse)
            do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw SpotifyError.offline }
            let h = resp as? HTTPURLResponse
            let code = h?.statusCode ?? 0
            let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
            switch code {
            case 200...299: return (code, json)
            case 401 where attempt == 1: force = true; continue
            case 429:
                let wait = Int(h?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                if attempt == 1 && wait <= 5 { try? await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000); continue }
                throw SpotifyError.rateLimited(wait)
            default:
                let msg = ((json as? [String: Any])?["error"] as? [String: Any])?["message"] as? String ?? ""
                throw SpotifyError.http(code, msg)
            }
        }
    }

    /// For extensions in other files.
    func callPublic(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> (Int, Any?) {
        try await call(method, path, query: query, body: body)
    }

    func me() async throws -> (id: String, name: String) {
        let (_, j) = try await call("GET", "/me")
        guard let d = j as? [String: Any], let id = d["id"] as? String else { throw SpotifyError.badResponse }
        return (id, (d["display_name"] as? String) ?? id)
    }

    private var verifiedUser = false
    /// Who is signed in, checked once per session (never trust a cached id: it decides which playlists are yours).
    func ensureUser() async throws -> String {
        if verifiedUser && !auth.userID.isEmpty { return auth.userID }
        let me = try await me()
        await MainActor.run {
            auth.userID = me.id; auth.userName = me.name
            UserDefaults.standard.set(me.id, forKey: "spotifyUserID"); UserDefaults.standard.set(me.name, forKey: "spotifyUserName")
        }
        verifiedUser = true
        return me.id
    }
    func resetUser() { verifiedUser = false }

    /// Playlists you can add to (ones you own or collaborate on).
    func playlists() async throws -> [SPPlaylist] {
        var out: [SPPlaylist] = []
        var offset = 0
        let myID = try await ensureUser()
        while offset < 1000 {
            let (_, j) = try await call("GET", "/me/playlists", query: ["limit": "50", "offset": String(offset)])
            guard let d = j as? [String: Any], let items = d["items"] as? [[String: Any]] else { throw SpotifyError.badResponse }
            for p in items {
                guard let id = p["id"] as? String, let name = p["name"] as? String else { continue }
                let owner = (p["owner"] as? [String: Any])?["id"] as? String ?? ""
                let collab = p["collaborative"] as? Bool ?? false
                guard owner == myID || collab else { continue }
                let total = ((p["items"] as? [String: Any]) ?? (p["tracks"] as? [String: Any]))?["total"] as? Int ?? 0
                let img = ((p["images"] as? [[String: Any]])?.last?["url"] as? String) ?? ""
                out.append(SPPlaylist(id: id, name: name, tracks: total, imageURL: img, isPublic: p["public"] as? Bool ?? false))
            }
            if d["next"] is NSNull || d["next"] == nil || items.isEmpty { break }
            offset += 50
        }
        return out
    }

    /// Adds tracks (in batches of 100, as Spotify requires).
    func add(_ uris: [String], to playlistID: String) async throws {
        var i = 0
        while i < uris.count {
            let batch = Array(uris[i..<min(i + 100, uris.count)])
            _ = try await call("POST", "/playlists/\(playlistID)/items", body: ["uris": batch])
            i += 100
        }
    }

    func createPlaylist(name: String, isPublic: Bool) async throws -> SPPlaylist {
        let body: [String: Any] = ["name": name, "public": isPublic, "description": "Created with Notchly"]
        var res: Any?
        do { (_, res) = try await call("POST", "/me/playlists", body: body) }
        catch SpotifyError.http(let c, _) where c == 404 || c == 405 {     // older route
            (_, res) = try await call("POST", "/users/\(auth.userID)/playlists", body: body)
        }
        guard let d = res as? [String: Any], let id = d["id"] as? String else { throw SpotifyError.badResponse }
        return SPPlaylist(id: id, name: name, tracks: 0, imageURL: "", isPublic: isPublic)
    }
}

/// The song playing in the Spotify app right now (read at click time, so it is the song you saw).
struct SpotifyTrack: Equatable, Hashable {
    var uri: String
    var title: String
    var artist: String
    var art: String
    var isAddable: Bool { uri.hasPrefix("spotify:track:") || uri.hasPrefix("spotify:episode:") }

    enum Problem: Error {
        case notRunning, stopped, notAllowed, other(String)
        var message: String {
            switch self {
            case .notRunning: return "Spotify isn't open"
            case .stopped: return "Nothing is playing in Spotify"
            case .notAllowed: return "Allow Notchly to control Spotify: System Settings → Privacy & Security → Automation → Notchly → Spotify"
            case .other(let m): return "Couldn't read the song from Spotify (\(m))"
            }
        }
    }

    static func read() -> Result<SpotifyTrack, Problem> {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) else { return .failure(.notRunning) }
        let script = """
        tell application "Spotify"
        if player state is stopped then return "STOPPED"
        return (spotify url of current track) & "||" & (name of current track) & "||" & (artist of current track) & "||" & (artwork url of current track)
        end tell
        """
        let r = MediaController.osaDetailed(script)
        if r.status != 0 {
            if r.err.contains("-1743") || r.err.lowercased().contains("not authorized") { return .failure(.notAllowed) }
            return .failure(.other(String(r.err.prefix(120))))
        }
        if r.out == "STOPPED" || r.out.isEmpty { return .failure(.stopped) }
        let p = r.out.components(separatedBy: "||")
        guard p.count >= 4 else { return .failure(.other("unexpected answer: \(r.out.prefix(80))")) }
        return .success(SpotifyTrack(uri: p[0], title: p[1], artist: p[2], art: p[3]))
    }

    static func current() -> SpotifyTrack? {
        if case .success(let t) = read() { return t }
        return nil
    }
}
