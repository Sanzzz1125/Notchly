// Captures one on-screen window of an app (alpha preserved, no shadow, nothing else on screen).
// usage: winshot <OwnerName> <out.png> [title-contains]
import AppKit
let a = CommandLine.arguments
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, CGFloat)?
for w in list {
    guard (w[kCGWindowOwnerName as String] as? String) == a[1], let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    // Title filter (window names are only readable with Screen Recording permission; if unreadable, don't filter).
    if a.count > 3, !a[3].isEmpty, let name = w[kCGWindowName as String] as? String, !name.contains(a[3]) { continue }
    if best == nil || area > best!.1 { best = (id, area) }
}
guard let b = best else { print("no window"); exit(1) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", String(b.0), a[2]]
try! p.run(); p.waitUntilExit()
