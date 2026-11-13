import SwiftUI
import AppKit

struct NotchShape: Shape {
    var t: CGFloat
    var b: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(t, b) }
        set { t = newValue.first; b = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let tt = min(t, h / 2)
        let bb = max(0, min(b, h / 2, (w - 2 * tt) / 2))
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: tt, y: tt), control: CGPoint(x: tt, y: 0))
        p.addLine(to: CGPoint(x: tt, y: h - bb))
        p.addQuadCurve(to: CGPoint(x: tt + bb, y: h), control: CGPoint(x: tt, y: h))
        p.addLine(to: CGPoint(x: w - tt - bb, y: h))
        p.addQuadCurve(to: CGPoint(x: w - tt, y: h - bb), control: CGPoint(x: w - tt, y: h))
        p.addLine(to: CGPoint(x: w - tt, y: tt))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - tt, y: 0))
        p.closeSubpath()
        return p
    }
}

struct GlassBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Surface: View {
    let t: CGFloat
    let b: CGFloat
    let theme: Int
    let accent: Color
    let tint: Double
    let expanded: Bool
    var artTint: Color = .white

    var body: some View {
        let shape = NotchShape(t: t, b: b)
        ZStack {
            shape.fill(Color.black)
            if expanded && theme == 1 { glass(shape) }
            if expanded, theme >= 4, let th = NotchTheme.find(theme) {
                shape.fill(LinearGradient(colors: [th.top, th.bottom], startPoint: .top, endPoint: .bottom))
                shape.fill(RadialGradient(colors: [accent.opacity(0.16), Color.clear], center: .bottom, startRadius: 0, endRadius: 320))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.clear], startPoint: .top, endPoint: .center))
            }
            if expanded && theme == 3 { shape.fill(LinearGradient(colors: [artTint.opacity(0.55), artTint.opacity(0.12), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)).animation(.easeInOut(duration: 0.6), value: artTint) }
            if expanded {
                shape.stroke(LinearGradient(colors: [Color.white.opacity(0.0), Color.white.opacity(theme == 1 ? 0.28 : 0.08)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
    }

    @ViewBuilder private func glass(_ shape: NotchShape) -> some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                GlassBlur().clipShape(shape)
            }
            shape.fill(Color.black.opacity(0.97 - 0.45 * tint))
            shape.fill(LinearGradient(colors: [accent.opacity(0.07), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.clear],
                                      startPoint: .top, endPoint: .center))
        }
    }
}

struct NotchTheme: Identifiable {
    let id: Int
    let name: String
    let top: Color
    let bottom: Color
    static let all: [NotchTheme] = [
        NotchTheme(id: 0, name: "Pitch Black", top: Color(hex: "#000000"), bottom: Color(hex: "#000000")),
        NotchTheme(id: 1, name: "Glass", top: Color(hex: "#34343E"), bottom: Color(hex: "#0C0C12")),
        NotchTheme(id: 3, name: "Album", top: Color(hex: "#8A5CF6"), bottom: Color(hex: "#111118")),
        NotchTheme(id: 4, name: "Midnight", top: Color(hex: "#1A2260"), bottom: Color(hex: "#06071A")),
        NotchTheme(id: 5, name: "Sunset", top: Color(hex: "#3A0F2A"), bottom: Color(hex: "#A83A4C")),
        NotchTheme(id: 6, name: "Ocean", top: Color(hex: "#063447"), bottom: Color(hex: "#031018")),
        NotchTheme(id: 7, name: "Forest", top: Color(hex: "#0B2A1C"), bottom: Color(hex: "#030A06")),
        NotchTheme(id: 8, name: "Ember", top: Color(hex: "#2A0E05"), bottom: Color(hex: "#9A3E0E")),
        NotchTheme(id: 9, name: "Rose", top: Color(hex: "#2A0F1E"), bottom: Color(hex: "#7A2F55")),
        NotchTheme(id: 10, name: "Graphite", top: Color(hex: "#25262B"), bottom: Color(hex: "#0A0A0C")),
        NotchTheme(id: 11, name: "Violet", top: Color(hex: "#24104A"), bottom: Color(hex: "#0A0516")),
        NotchTheme(id: 12, name: "Mint", top: Color(hex: "#0C3A3A"), bottom: Color(hex: "#041212")),
    ]
    static func find(_ id: Int) -> NotchTheme? { all.first { $0.id == id } }
}
