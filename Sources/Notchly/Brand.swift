import AppKit

enum Brand {
    /// Menu bar glyph: a screen with the island hanging from the top edge. Template image, so macOS tints it.
    static func menuBarIcon() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let screen = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 1.75, width: 15, height: 11.5), xRadius: 3.4, yRadius: 3.4)
            screen.lineWidth = 1.4
            screen.stroke()
            // island: flat top fused with the screen edge, rounded bottom
            let w: CGFloat = 8.2, h: CGFloat = 5.2, x = 10 - w / 2, top: CGFloat = 13.4, r: CGFloat = 2.4
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: top))
            p.line(to: NSPoint(x: x, y: top - h + r))
            p.curve(to: NSPoint(x: x + r, y: top - h), controlPoint1: NSPoint(x: x, y: top - h + r * 0.45), controlPoint2: NSPoint(x: x + r * 0.45, y: top - h))
            p.line(to: NSPoint(x: x + w - r, y: top - h))
            p.curve(to: NSPoint(x: x + w, y: top - h + r), controlPoint1: NSPoint(x: x + w - r * 0.45, y: top - h), controlPoint2: NSPoint(x: x + w, y: top - h + r * 0.45))
            p.line(to: NSPoint(x: x + w, y: top))
            p.close()
            p.fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Notchly"
        return img
    }
}
