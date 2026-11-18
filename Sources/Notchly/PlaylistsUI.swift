import SwiftUI
import AppKit

// MARK: The bar on the music card (only while Spotify is playing)

struct SpotifyBar: View {
    @ObservedObject var svc = PlaylistService.shared
    @ObservedObject var stash = StashStore.shared
    @ObservedObject var auth = SpotifyAuth.shared
    @ObservedObject var st = NotchState.shared
    let compact: Bool

    private var canAdd: Bool { svc.current?.isAddable ?? true }
    private var added: Bool { svc.currentInDefault }
    private var stashed: Bool { svc.current.map { stash.contains($0.uri) } ?? false }

    private func round(_ symbol: String, tint: Color = DS.Ink.primary, fill: Color = Color.white.opacity(0.09), size: CGFloat) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .contentShape(Circle())
    }

    var body: some View {
        let size: CGFloat = compact ? 28 : 32
        VStack(spacing: compact ? 6 : 9) {
            if !auth.signedIn {
                Button { SettingsWindow.show(.playlists) } label: { round("person.crop.circle.badge.plus", size: size) }
                    .buttonStyle(PressStyle(radius: size / 2, scale: 0.9, fill: false)).help("Connect Spotify to add songs to playlists")
            } else {
                // 1. default playlist
                Button { svc.addToDefault() } label: {
                    round(added ? "checkmark" : "plus", tint: added ? Color.black : Color.white, fill: added ? Color.green : P.accent, size: size)
                        .opacity(canAdd ? 1 : 0.4)
                }
                .buttonStyle(PressStyle(radius: size / 2, scale: 0.88, fill: false))
                .disabled(!canAdd || svc.busy)
                .help(!canAdd ? "This can't be added (an ad or a local file)" : (added ? "Already in \(svc.defaultName)" : "Add to \(svc.defaultName)"))
                // 2. another playlist
                Button {
                    withAnimation(Motion.open) { st.pickerOpen = true }
                } label: { round("text.badge.plus", size: size).opacity(canAdd ? 1 : 0.4) }
                    .buttonStyle(PressStyle(radius: size / 2, scale: 0.9, fill: false))
                    .disabled(!canAdd).help("Add to another playlist…")
                // 3. stash
                Button { svc.stashCurrent() } label: {
                    round(stashed ? "tray.full.fill" : "tray.full", tint: stashed ? P.accent : DS.Ink.primary, size: size)
                        .overlay(alignment: .topTrailing) {
                            if !stash.items.isEmpty {
                                Text(stash.items.count > 99 ? "99+" : "\(stash.items.count)")
                                    .font(.system(size: 8.5, weight: .bold)).foregroundStyle(Color.white)
                                    .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                                    .background(Capsule().fill(P.accent)).offset(x: 5, y: -4)
                            }
                        }
                        .opacity(canAdd ? 1 : 0.4)
                }
                .buttonStyle(PressStyle(radius: size / 2, scale: 0.9, fill: false))
                .disabled(!canAdd)
                .help(stashed ? "In your Stash. Right-click to open it" : "Send to Stash (collect songs, make a playlist later). Right-click to open it")
                .contextMenu {
                    Button("Open Stash") { st.go(.stash) }
                    Button("Open Stash manager in the app window") { SettingsWindow.show(.stash) }
                }
            }
        }
        .frame(width: size + 6)
    }
}

// MARK: Picker (slides over the music card)

struct PlaylistPicker: View {
    let track: SpotifyTrack?
    let onClose: () -> Void
    @ObservedObject var svc = PlaylistService.shared
    @StateObject private var query = Box<String>("")
    @StateObject private var creating = Box<Bool>(false)
    @StateObject private var newName = Box<String>("")

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add to…").font(DS.Typo.headline)
                    if let t = track { Text("“\(t.title)”").font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                DSField(placeholder: "Search", text: $query.v, symbol: "magnifyingglass").frame(maxWidth: 170)
                IconButton(symbol: "xmark", size: 26, icon: 10, help: "Close (Esc)") { onClose() }
            }
            if track == nil || track?.isAddable == false {
                EmptyState(symbol: "music.note", title: "Nothing to add", subtitle: "Play a normal song in Spotify first")
            } else if svc.playlists.isEmpty && svc.loading {
                VStack { ProgressView().controlSize(.small); Text("Loading your playlists…").font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        newRow
                        ForEach(svc.ordered(query.v)) { p in row(p) }
                        if !query.v.isEmpty && svc.ordered(query.v).isEmpty {
                            Text("No playlist matches “\(query.v)”").font(DS.Typo.caption).foregroundStyle(DS.Ink.tertiary).padding(.top, 10)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .edgeFade()
            }
        }
        .padding(DS.Space.m)
        .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(Color(white: 0.07)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .task { await svc.loadPlaylists() }
    }

    private var newRow: some View {
        Group {
            if creating.v {
                HStack(spacing: 6) {
                    DSField(placeholder: "New playlist name", text: $newName.v, symbol: "plus") { create() }
                    Chip(title: "Create", prominent: true) { create() }
                    Chip(title: "Cancel") { creating.v = false; newName.v = "" }
                }
            } else {
                Button { creating.v = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(P.accent).frame(width: 18)
                        Text("New playlist…").font(DS.Typo.bodyEm)
                        Spacer()
                    }
                    .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(radius: DS.Radius.m, scale: 0.98))
            }
        }
    }

    private func create() {
        let n = newName.v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        svc.createAndAdd(name: n, track: track)
        onClose()
    }

    private func row(_ p: SPPlaylist) -> some View {
        PickerRow(p: p, isDefault: p.id == svc.defaultID) {
            svc.add(to: p, track: track)
            onClose()
        } makeDefault: { svc.setDefault(p) }
    }
}

private struct PickerRow: View {
    let p: SPPlaylist
    let isDefault: Bool
    let pick: () -> Void
    let makeDefault: () -> Void
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isDefault ? "star.fill" : "music.note.list").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDefault ? Color.yellow : DS.Ink.tertiary).frame(width: 18)
            Text(p.name).font(DS.Typo.bodyEm).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            if hover.v && !isDefault {
                Button { makeDefault() } label: {
                    Text("Make default").font(DS.Typo.micro).foregroundStyle(DS.Ink.secondary)
                        .padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(Color.white.opacity(0.1)))
                }.buttonStyle(.plain)
            }
            if p.tracks > 0 { Text("\(p.tracks)").font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary).monospacedDigit() }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(hover.v ? DS.Fill.hover : (isDefault ? P.accent.opacity(0.14) : Color.clear)))
        .contentShape(Rectangle())
        .onTapGesture { pick() }
        .onHover { h in withAnimation(DS.hoverAnim) { hover.v = h } }
    }
}

/// Small error line that floats at the bottom of the music card. Successful adds are silent.
struct PlaylistToast: View {
    @ObservedObject var svc = PlaylistService.shared
    var body: some View {
        if let m = svc.toast {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Color.orange)
                Text(m).font(DS.Typo.caption).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color(white: 0.16)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
            .padding(.bottom, 6).padding(.horizontal, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: Stash manager (notch tab and app window share this)

struct StashManager: View {
    let compact: Bool
    @ObservedObject var stash = StashStore.shared
    @ObservedObject var svc = PlaylistService.shared
    @ObservedObject var auth = SpotifyAuth.shared
    @StateObject private var selected = Box<Set<UUID>>([])
    @StateObject private var query = Box<String>("")
    @StateObject private var mode = Box<Int>(0)          // 0 list, 1 create form, 2 add-to picker
    @StateObject private var newName = Box<String>("")
    @StateObject private var isPublic = Box<Bool>(false)
    @StateObject private var removeAfter = Box<Bool>(true)
    @StateObject private var working = Box<Bool>(false)
    @StateObject private var message = Box<String>("")
    @StateObject private var newestFirst = Box<Bool>(true)

    private var shown: [StashItem] {
        var l = stash.items
        let q = query.v.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { l = l.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) } }
        return newestFirst.v ? l : l.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
    private var chosen: [StashItem] { stash.items.filter { selected.v.contains($0.id) } }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            toolbar
            if mode.v == 1 { createForm }
            if !message.v.isEmpty { messageBar }
            if !stash.undoBatch.isEmpty { undoBar }
            if mode.v == 2 {
                PlaylistChooser(title: "Add \(chosen.count) song\(chosen.count == 1 ? "" : "s") to…", onClose: { mode.v = 0 }) { p in addSelected(to: p) }
            } else if stash.items.isEmpty {
                EmptyState(symbol: "tray", title: "Your Stash is empty",
                           subtitle: "While Spotify plays, press the tray button on the music card to collect songs here. Then turn a pick into a playlist.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 3) { ForEach(shown) { it in row(it) } }.padding(.vertical, 2)
                }
                .edgeFade()
            }
        }
        .onChange(of: stash.items) { _, new in selected.v = selected.v.intersection(Set(new.map { $0.id })) }
    }

    // MARK: toolbar

    private var chips: some View {
        let n = selected.v.count
        return HStack(spacing: DS.Space.xs) {
            Chip(title: n == stash.items.count && n > 0 ? "None" : "All", symbol: "checkmark.circle") {
                selected.v = (n == stash.items.count) ? [] : Set(stash.items.map { $0.id })
            }.disabled(stash.items.isEmpty)
            if n > 0 {
                Chip(title: "Create playlist", symbol: "plus.rectangle.on.rectangle", prominent: true) {
                    newName.v = "Stash · " + Date().formatted(.dateTime.day().month(.abbreviated)); mode.v = mode.v == 1 ? 0 : 1; message.v = ""
                }.disabled(!auth.signedIn)
                Chip(title: "Add to…", symbol: "text.badge.plus") { mode.v = mode.v == 2 ? 0 : 2; message.v = "" }.disabled(!auth.signedIn)
                Chip(title: "Delete \(n)", symbol: "trash") { stash.remove(selected.v); selected.v = [] }
            } else if !stash.items.isEmpty {
                Chip(title: newestFirst.v ? "Newest" : "A–Z", symbol: "arrow.up.arrow.down") { newestFirst.v.toggle() }
                Chip(title: "Clear all", symbol: "trash") { stash.clear(); selected.v = [] }
            }
        }
    }

    private var count: some View {
        Text("\(stash.items.count) song\(stash.items.count == 1 ? "" : "s")").font(DS.Typo.bodyEm).foregroundStyle(DS.Ink.secondary).fixedSize()
    }

    /// Everything stays visible: one row in the notch, two rows in the roomy window (a mouse can't scroll sideways).
    @ViewBuilder private var toolbar: some View {
        if compact {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s) { count; chips; Spacer(minLength: 0) }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: DS.Space.s) { count; chips } }
            }
            .frame(height: 28)
            .onHover { NotchState.shared.blockSwipe = $0 }
        } else {
            VStack(spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.s) { count; DSField(placeholder: "Search songs", text: $query.v, symbol: "magnifyingglass"); }
                HStack(spacing: DS.Space.xs) { chips; Spacer(minLength: 0) }
            }
        }
    }

    // MARK: rows

    private func row(_ it: StashItem) -> some View {
        StashRow(item: it, selected: selected.v.contains(it.id), compact: compact) {
            if selected.v.contains(it.id) { selected.v.remove(it.id) } else { selected.v.insert(it.id) }
        } remove: { stash.remove([it.id]) }
    }

    // MARK: create / add

    private var createForm: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                DSField(placeholder: "Playlist name", text: $newName.v, symbol: "music.note.list") { createPlaylist() }
                Segmented(items: [(false, "Private"), (true, "Public")], selection: $isPublic.v).frame(width: 150)
            }
            HStack(spacing: 8) {
                Toggle("Remove these songs from the Stash afterwards", isOn: $removeAfter.v).toggleStyle(.checkbox).font(DS.Typo.caption)
                Spacer()
                if working.v { ProgressView().controlSize(.small) }
                Chip(title: "Cancel") { mode.v = 0 }
                Chip(title: "Create with \(selected.v.count)", prominent: true) { createPlaylist() }.disabled(working.v || newName.v.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10).card(DS.Radius.m)
    }

    private func createPlaylist() {
        let name = newName.v.trimmingCharacters(in: .whitespacesAndNewlines)
        let songs = chosen
        guard !name.isEmpty, !songs.isEmpty, !working.v else { return }
        working.v = true; message.v = ""
        Task {
            do {
                if Demo.on { try? await Task.sleep(nanoseconds: 400_000_000) }
                else {
                    let p = try await SpotifyAPI.shared.createPlaylist(name: name, isPublic: isPublic.v)
                    try await SpotifyAPI.shared.add(songs.map { $0.uri }, to: p.id)
                    await svc.loadPlaylists(force: true)
                }
                await MainActor.run {
                    message.v = "✓ Created “\(name)” with \(songs.count) song\(songs.count == 1 ? "" : "s")"
                    if removeAfter.v { stash.remove(Set(songs.map { $0.id })); stash.undoBatch = [] }
                    selected.v = []; mode.v = 0; working.v = false
                }
            } catch let e as SpotifyError { await MainActor.run { message.v = "✗ " + e.message; working.v = false } }
            catch { await MainActor.run { message.v = "✗ Couldn't create the playlist"; working.v = false } }
        }
    }

    private func addSelected(to p: SPPlaylist) {
        let songs = chosen
        mode.v = 0; working.v = true
        Task {
            do {
                if Demo.on { try? await Task.sleep(nanoseconds: 300_000_000) } else { try await SpotifyAPI.shared.add(songs.map { $0.uri }, to: p.id) }
                await MainActor.run { message.v = "✓ Added \(songs.count) song\(songs.count == 1 ? "" : "s") to “\(p.name)”"; working.v = false }
            } catch let e as SpotifyError { await MainActor.run { message.v = "✗ " + e.message; working.v = false } }
            catch { await MainActor.run { message.v = "✗ Couldn't add the songs"; working.v = false } }
        }
    }

    private var messageBar: some View {
        HStack {
            Text(message.v).font(DS.Typo.caption).lineLimit(2)
            Spacer()
            IconButton(symbol: "xmark", size: 20, icon: 8) { message.v = "" }
        }
        .padding(.horizontal, 10).frame(minHeight: 28)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(message.v.hasPrefix("✗") ? Color.red.opacity(0.18) : Color.green.opacity(0.16)))
    }

    private var undoBar: some View {
        HStack {
            Text("Deleted \(stash.undoBatch.count) song\(stash.undoBatch.count == 1 ? "" : "s")").font(DS.Typo.caption)
            Spacer()
            Chip(title: "Undo", symbol: "arrow.uturn.backward", prominent: true) { stash.undo() }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(Color.white.opacity(0.08)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct StashRow: View {
    let item: StashItem
    let selected: Bool
    let compact: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 15))
                .foregroundStyle(selected ? P.accent : DS.Ink.tertiary)
            art
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(DS.Typo.bodyEm).lineLimit(1)
                Text(item.artist).font(DS.Typo.caption).foregroundStyle(DS.Ink.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if hover.v {
                IconButton(symbol: "arrow.up.forward.app", size: 24, icon: 10, help: "Open in Spotify") {
                    if let u = URL(string: item.uri) { NSWorkspace.shared.open(u) }
                }
                IconButton(symbol: "xmark", size: 24, icon: 9, help: "Remove from Stash") { remove() }
            } else if !compact {
                Text(item.added.formatted(.relative(presentation: .named))).font(DS.Typo.micro).foregroundStyle(DS.Ink.tertiary)
            }
        }
        .padding(.horizontal, 10).frame(height: compact ? 38 : 44)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(selected ? P.accent.opacity(0.16) : (hover.v ? DS.Fill.hover : DS.Fill.base)))
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .onHover { h in withAnimation(DS.hoverAnim) { hover.v = h } }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
    private var art: some View {
        Group {
            if !item.art.isEmpty, P.bool("allowNetwork"), let u = URL(string: item.art) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.08) }
            } else {
                ZStack { Color.white.opacity(0.08); Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(DS.Ink.tertiary) }
            }
        }
        .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Playlist chooser for the Stash ("Add to…"): same list as the picker, without a song header.
struct PlaylistChooser: View {
    let title: String
    let onClose: () -> Void
    let pick: (SPPlaylist) -> Void
    @ObservedObject var svc = PlaylistService.shared
    @StateObject private var query = Box<String>("")
    var body: some View {
        VStack(spacing: DS.Space.xs) {
            HStack {
                Text(title).font(DS.Typo.headline)
                Spacer()
                DSField(placeholder: "Search", text: $query.v, symbol: "magnifyingglass").frame(maxWidth: 170)
                IconButton(symbol: "xmark", size: 24, icon: 10) { onClose() }
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(svc.ordered(query.v)) { p in
                        PickerRow(p: p, isDefault: p.id == svc.defaultID) { pick(p) } makeDefault: { svc.setDefault(p) }
                    }
                }
            }
            .edgeFade()
        }
        .padding(DS.Space.s)
        .task { await svc.loadPlaylists() }
    }
}

struct StashTab: View {
    var body: some View {
        StashManager(compact: true).padding(DS.Space.m).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).card()
    }
}

/// The Stash in the app window: a roomy place to review, select, delete and build playlists.
struct StashPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Stash").font(.title2.bold())
            Text("Songs you sent to the Stash from the music card. Select some to make a new playlist, add them to an existing one, or delete them. They are stored only on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            StashManager(compact: false)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
}
