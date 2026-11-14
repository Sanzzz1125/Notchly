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

struct TrayTile: View {
    let url: URL
    @ObservedObject var tray = TrayStore.shared
    var body: some View {
        let sel = tray.selected.contains(url)
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 44, height: 44)
                if sel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Color.white, P.accent)
                        .offset(x: 6, y: -5)
                }
            }
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 80)
        .padding(.vertical, 7).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sel ? P.accent.opacity(0.28) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(sel ? P.accent : Color.clear, lineWidth: 1.5))
        .overlay(TileDrag(url: url))
        .help(url.lastPathComponent)
    }
}

struct TrayTab: View {
    @ObservedObject var tray = TrayStore.shared
    @AppStorage("trayRemove") var removeAfter = true

    private func chip(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                DropZone(symbol: "tray.and.arrow.down.fill", title: "Drop to hold") { tray.add($0) }
                DropZone(symbol: "airplayaudio", title: "AirDrop") { urls in
                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                }
            }
            .frame(width: 124)
            VStack(spacing: 6) {
                if !tray.files.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("All", "checkmark.circle") { tray.selectAll() }
                            if !tray.selected.isEmpty {
                                chip("None", "circle") { tray.deselect() }
                                chip("AirDrop", "airplayaudio") {
                                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: tray.selectedFiles)
                                }
                                chip("Remove", "minus.circle") { tray.remove(tray.selectedFiles) }
                            }
                            chip("Clear", "trash") { tray.clear() }
                            Toggle("Remove after drop", isOn: $removeAfter)
                                .toggleStyle(.checkbox).font(.system(size: 11))
                            Text(tray.selected.isEmpty ? "Click files to select · drag to move" : "\(tray.selected.count) selected · drag to move")
                                .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                    .frame(height: 24)
                    .onHover { NotchState.shared.blockSwipe = $0 }
                }
                ZStack {
                    if tray.files.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 22)).foregroundStyle(Color.white.opacity(0.35))
                            Text("Drop files here, then drag them anywhere").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                ForEach(tray.files, id: \.self) { u in TrayTile(url: u) }
                            }
                            .padding(8)
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
    }
}
