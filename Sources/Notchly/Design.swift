import SwiftUI
import AppKit

/// Notchly design system: one set of spacing, radii, type, ink and interaction states.
enum DS {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
    }
    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 22
    }
    enum Typo {
        static let title = Font.system(size: 15, weight: .bold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let bodyEm = Font.system(size: 12, weight: .semibold)
        static let caption = Font.system(size: 10.5, weight: .medium)
        static let micro = Font.system(size: 9.5, weight: .semibold)
        static let digits = Font.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
    }
    enum Ink {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.62)
        static let tertiary = Color.white.opacity(0.40)
    }
    enum Fill {
        static let base = Color.white.opacity(0.06)
        static let hover = Color.white.opacity(0.11)
        static let press = Color.white.opacity(0.17)
        static let stroke = Color.white.opacity(0.07)
    }
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.72)
    static let hoverAnim = Animation.easeOut(duration: 0.14)
}

// MARK: Button styles

/// Hover + press feedback for every clickable control in the island.
struct PressStyle: ButtonStyle {
    var radius: CGFloat = DS.Radius.s
    var scale: CGFloat = 0.94
    var fill: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, radius: radius, scale: scale, fill: fill)
    }
}

private struct PressBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    let scale: CGFloat
    let fill: Bool
    @StateObject private var hover = Box<Bool>(false)
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(!fill ? Color.clear : (configuration.isPressed ? DS.Fill.press : (hover.v ? DS.Fill.hover : Color.clear)))
            )
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(enabled ? 1 : 0.4)
            .animation(DS.press, value: configuration.isPressed)
            .animation(DS.hoverAnim, value: hover.v)
            .onHover { hover.v = $0 }
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
    static func press(radius: CGFloat, scale: CGFloat = 0.94, fill: Bool = true) -> PressStyle {
        PressStyle(radius: radius, scale: scale, fill: fill)
    }
}

/// Round icon button (transport controls, header buttons).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var icon: CGFloat = 12
    var tint: Color = DS.Ink.secondary
    var help: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: icon, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: size / 2))
        .help(help)
    }
}

/// Pill-shaped action (replaces the stock bordered buttons).
struct Chip: View {
    let title: String
    var symbol: String? = nil
    var prominent = false
    var tint: Color = P.accent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let s = symbol { Image(systemName: s).font(.system(size: 10, weight: .bold)) }
                Text(title).font(DS.Typo.caption)
            }
            .foregroundStyle(prominent ? Color.white : DS.Ink.primary.opacity(0.9))
            .padding(.horizontal, 10).frame(height: 24)
            .background(Capsule().fill(prominent ? tint : Color.white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12, scale: 0.93, fill: false))
    }
}

/// Dark-theme segmented control with a sliding selection.
struct Segmented<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let it = items[i]
                Button { withAnimation(Motion.tab) { selection = it.0 } } label: {
                    Text(it.1).font(DS.Typo.caption)
                        .foregroundStyle(selection == it.0 ? Color.white : DS.Ink.secondary)
                        .frame(maxWidth: .infinity).frame(height: 22)
                        .background {
                            if selection == it.0 {
                                Capsule().fill(Color.white.opacity(0.16)).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(radius: 11, scale: 0.96, fill: false))
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// Rounded text field used inside the island.
struct DSField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 7) {
            if let s = symbol { Image(systemName: s).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.Ink.tertiary) }
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(DS.Typo.body).onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(DS.Ink.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(DS.Fill.stroke, lineWidth: 1))
    }
}

/// Thin progress / level bar.
struct Meter: View {
    let value: Double
    var tint: Color = P.accent
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(tint).frame(width: max(height, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: height)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String = ""
    var actionTitle: String = ""
    var action: () -> Void = {}
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(DS.Ink.tertiary)
            Text(title).font(DS.Typo.bodyEm).foregroundStyle(DS.Ink.secondary).multilineTextAlignment(.center)
            if !subtitle.isEmpty { Text(subtitle).font(DS.Typo.caption).foregroundStyle(DS.Ink.tertiary).multilineTextAlignment(.center) }
            if !actionTitle.isEmpty { Chip(title: actionTitle, action: action).padding(.top, 2) }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Surfaces

extension View {
    /// Standard card surface. `style` follows Settings → Appearance → Cards.
    func card(_ r: CGFloat = DS.Radius.l) -> some View {
        let style = P.int("cardStyle")
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        return background(
            ZStack {
                shape.fill(Color.white.opacity(style == 1 ? 0.02 : 0.06))
                if style == 2 { shape.fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.clear], startPoint: .top, endPoint: .center)) }
                shape.strokeBorder(Color.white.opacity(style == 0 ? 0.04 : 0.10), lineWidth: 1)
            }
        )
    }

    /// Softly fades the bottom (and optionally top) edge of scrolling content instead of a hard cut.
    func edgeFade(_ axis: Axis = .vertical, length: CGFloat = 10, leading: Bool = false) -> some View {
        mask(
            LinearGradient(stops: [.init(color: leading ? .clear : .black, location: 0), .init(color: .black, location: leading ? length / 100 : 0),
                                   .init(color: .black, location: 1 - length / 100), .init(color: .clear, location: 1)],
                           startPoint: axis == .vertical ? .top : .leading,
                           endPoint: axis == .vertical ? .bottom : .trailing)
        )
    }
}

/// Section label used above groups inside a tab.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(DS.Typo.micro).tracking(0.6).foregroundStyle(DS.Ink.tertiary)
    }
}
