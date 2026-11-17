import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// AppKit tile overlay: click = select/unselect, drag = drag all selected files out (multi-file).
final class TileView: NSView, NSDraggingSource {
    var urls: () -> [URL] = { [] }
    var onClick: () -> Void = {}
    var onDragEnd: ([URL]) -> Void = { _ in }
    private var down = NSPoint.zero
    private var dragging = false
    private var dragged: [URL] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        down = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        if dragging { return }
        let dx = event.locationInWindow.x - down.x
        let dy = event.locationInWindow.y - down.y
        if hypot(dx, dy) < 4 { return }
        dragging = true
        let list = urls()
        if list.isEmpty { return }
        dragged = list
        let p = convert(event.locationInWindow, from: nil)
        var items: [NSDraggingItem] = []
        for (i, u) in list.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: u as NSURL)
            let o = CGFloat(min(i, 5)) * 7
            let icon = NSWorkspace.shared.icon(forFile: u.path)
            item.setDraggingFrame(NSRect(x: p.x - 24 + o, y: p.y - 24 - o, width: 48, height: 48), contents: icon)
            items.append(item)
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging { onClick() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let a = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: ""); a.target = self; m.addItem(a)
        let b = NSMenuItem(title: "AirDrop", action: #selector(airdrop), keyEquivalent: ""); b.target = self; m.addItem(b)
        m.addItem(.separator())
        let c = NSMenuItem(title: "Remove from Tray", action: #selector(remove), keyEquivalent: ""); c.target = self; m.addItem(c)
        return m
    }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting(urls()) }
    @objc private func airdrop() { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls()) }
    @objc private func remove() { TrayStore.shared.remove(urls()) }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onDragEnd(dragged) }
        dragged = []
    }
}

struct TileDrag: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> TileView {
        let v = TileView()
        configure(v)
        return v
    }
    func updateNSView(_ v: TileView, context: Context) { configure(v) }
    private func configure(_ v: TileView) {
        let u = url
        v.urls = {
            let t = TrayStore.shared
            return t.selected.contains(u) ? t.files.filter { t.selected.contains($0) } : [u]
        }
        v.onClick = { TrayStore.shared.toggle(u) }
        v.onDragEnd = { list in
            if P.bool("trayRemove") { TrayStore.shared.remove(list) }
        }
    }
}

struct DropZone: View {
    let symbol: String
    let title: String
    let action: ([URL]) -> Void
    @StateObject private var hot = Box<Bool>(false)
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
            Text(title).font(DS.Typo.caption)
        }
        .foregroundStyle(hot.v ? P.accent : DS.Ink.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(hot.v ? P.accent.opacity(0.18) : DS.Fill.base))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
            .strokeBorder(hot.v ? P.accent : Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])))
        .scaleEffect(hot.v ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hot.v)
        .onDrop(of: [UTType.fileURL], isTargeted: $hot.v) { providers in
            loadFileURLs(providers, action)
            return true
        }
    }
}

struct TrayTile: View {
    let url: URL
    @ObservedObject var tray = TrayStore.shared
    @StateObject private var hover = Box<Bool>(false)
    var body: some View {
        let sel = tray.selected.contains(url)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 42, height: 42)
                if sel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Color.white, P.accent)
                        .offset(x: 6, y: -5).transition(.scale.combined(with: .opacity))
                }
            }
            Text(url.lastPathComponent).font(DS.Typo.caption).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 80)
        .padding(.vertical, 7).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(sel ? P.accent.opacity(0.28) : (hover.v ? DS.Fill.hover : DS.Fill.base)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(sel ? P.accent : Color.clear, lineWidth: 1.5))
        .overlay(TileDrag(url: url))
        .onHover { h in withAnimation(DS.hoverAnim) { hover.v = h } }
        .animation(DS.press, value: sel)
        .help(url.lastPathComponent)
    }
}

struct TrayTab: View {
    @ObservedObject var tray = TrayStore.shared
    @AppStorage("trayRemove") var removeAfter = true

    var body: some View {
        GeometryReader { g in
            let side: CGFloat = g.size.width > 520 ? 124 : 96
            HStack(spacing: DS.Space.s + 2) {
                VStack(spacing: DS.Space.s) {
                    DropZone(symbol: "tray.and.arrow.down.fill", title: "Drop to hold") { tray.add($0) }
                    DropZone(symbol: "airplayaudio", title: "AirDrop") { urls in
                        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                    }
                }
                .frame(width: side)
                VStack(spacing: DS.Space.xs) {
                    if !tray.files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.xs) {
                                Chip(title: "All", symbol: "checkmark.circle") { tray.selectAll() }
                                if !tray.selected.isEmpty {
                                    Chip(title: "None", symbol: "circle") { tray.deselect() }
                                    Chip(title: "AirDrop", symbol: "airplayaudio", prominent: true) {
                                        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: tray.selectedFiles)
                                    }
                                    Chip(title: "Remove", symbol: "minus.circle") { tray.remove(tray.selectedFiles) }
                                }
                                Chip(title: "Clear", symbol: "trash") { tray.clear() }
                                Toggle("Remove after drop", isOn: $removeAfter)
                                    .toggleStyle(.checkbox).font(DS.Typo.caption)
                                Text(tray.selected.isEmpty ? "Click to select · drag to move" : "\(tray.selected.count) selected · drag to move")
                                    .font(DS.Typo.caption).foregroundStyle(DS.Ink.tertiary)
                            }
                        }
                        .frame(height: 24)
                        .onHover { NotchState.shared.blockSwipe = $0 }
                    }
                    ZStack {
                        if tray.files.isEmpty {
                            EmptyState(symbol: "square.stack.3d.up", title: "Drop files here", subtitle: "Then drag them anywhere. Select several to move them together.")
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: DS.Space.s)], spacing: DS.Space.s) {
                                    ForEach(tray.files, id: \.self) { u in TrayTile(url: u) }
                                }
                                .padding(DS.Space.s)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .card()
                    .onHover { NotchState.shared.blockSwipe = $0 }
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        loadFileURLs(providers) { tray.add($0) }
                        return true
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
