//
//  Fonts, colours and button styles that Snag used from Lowtech.
//
//  Lowtech has no licence file, which blocks distributing a compiled binary. See
//  docs/independence-plan.md. Only the members Snag actually calls are here; Lowtech's colour
//  system alone is several hundred lines of named shades, of which this app touches four.
//

import Foundation
import SwiftUI
import System

// MARK: - Fonts

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func round(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func regular(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func medium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func semibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func bold(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func heavy(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static func black(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func light(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
    static func thin(_ size: CGFloat) -> Font { .system(size: size, weight: .thin) }
    static func ultraLight(_ size: CGFloat) -> Font { .system(size: size, weight: .ultraLight) }
}

extension Text {
    func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Text { font(.mono(size, weight: weight)) }
    func round(_ size: CGFloat, weight: Font.Weight = .medium) -> Text { font(.round(size, weight: weight)) }
    func regular(_ size: CGFloat) -> Text { font(.regular(size)) }
    func medium(_ size: CGFloat) -> Text { font(.medium(size)) }
    func semibold(_ size: CGFloat) -> Text { font(.semibold(size)) }
    func bold(_ size: CGFloat) -> Text { font(.bold(size)) }
    func heavy(_ size: CGFloat) -> Text { font(.heavy(size)) }
    func black(_ size: CGFloat) -> Text { font(.black(size)) }
    func light(_ size: CGFloat) -> Text { font(.light(size)) }
}

// MARK: - Colours

extension Color {
    /// Light/dark pair. SwiftUI has no literal for this, so it goes through NSColor's dynamic
    /// provider, which re-resolves whenever the system appearance changes.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }

    static let warmWhite = Color(hue: 0.06, saturation: 0.04, brightness: 0.97)
    static let warmBlack = Color(hue: 0.08, saturation: 0.15, brightness: 0.18)

    /// Flipped against the system appearance: white text on a dark background and vice versa.
    static let inverted = Color(light: .white, dark: .black)
    static let highContrast = Color(light: .black, dark: .white)

    /// Foreground and background namespaces, so a call site reads `.fg.warm` rather than
    /// picking the right one of two similarly named constants by hand.
    struct FG {
        /// Slightly warm off-black/off-white. Pure black on pure white vibrates; this does not.
        let warm = Color(light: .warmBlack, dark: .warmWhite)
        let primary = Color.primary
    }

    struct BG {
        let warm = Color(light: .warmWhite, dark: .warmBlack)
        let primary = Color(light: .white, dark: .black)
    }

    static let fg = FG()
    static let bg = BG()

    /// Perceived brightness, for deciding whether text on this colour should be black or white.
    /// Uses the Rec. 601 luma weights: the eye is far more sensitive to green than to blue, so
    /// a plain RGB average picks the wrong text colour on saturated hues.
    var isLight: Bool {
        let c = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        return (c.redComponent * 0.299 + c.greenComponent * 0.587 + c.blueComponent * 0.114) > 0.6
    }

    func textColor() -> Color { isLight ? .black : .white }
}

// MARK: - View helpers

extension View {
    /// Type-erase. Frequent enough in this codebase that `.any` earns its place over
    /// `AnyView(...)` wrapping the whole expression.
    var any: AnyView { AnyView(self) }

    /// Stretch to the full available width, aligned. Named for how often it appears: nearly
    /// every row in Settings ends with one.
    func hfill(_ alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    /// Apply a transform only when a condition holds, without breaking the view's type.
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, @ViewBuilder transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }

    /// Fill both axes.
    func fill(_ alignment: Alignment = .center) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    /// Vertical counterpart.
    func vfill(_ alignment: Alignment = .center) -> some View {
        frame(maxHeight: .infinity, alignment: alignment)
    }

    func roundbg(
        radius: CGFloat = 5,
        verticalPadding: CGFloat = 2.5,
        horizontalPadding: CGFloat = 6,
        color: Color = .inverted,
        shadowSize: CGFloat = 0
    ) -> some View {
        padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(color)
                    .shadow(color: .black.opacity(shadowSize > 0 ? 0.2 : 0), radius: shadowSize)
            )
    }
}

// MARK: - FlatButton

/// A filled, rounded button that reacts to hover and press.
///
/// Only the parameters Snag passes are kept. Lowtech's version also takes bindings for every
/// colour and a stretch flag; nothing here uses them.
struct FlatButton: ButtonStyle {
    init(
        color: Color? = nil,
        textColor: Color? = nil,
        hoverColor: Color? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        circle: Bool = false,
        radius: CGFloat = 8,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 4,
        shadowSize: CGFloat = 0
    ) {
        self.color = color ?? .primary
        self.textColor = textColor
        self.hoverColor = hoverColor
        self.width = width
        self.height = height
        self.circle = circle
        self.radius = radius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.shadowSize = shadowSize
    }

    func makeBody(configuration: Configuration) -> some View {
        let background = hovering ? (hoverColor ?? color.opacity(0.8)) : color
        return configuration.label
            .foregroundColor(textColor ?? color.textColor())
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: width, minHeight: height)
            .background(
                Group {
                    if circle {
                        Circle().fill(background)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(background)
                    }
                }
                .shadow(color: .black.opacity(shadowSize > 0 ? 0.2 : 0), radius: shadowSize)
            )
            // Pressed state reads as a slight shrink rather than a colour change, so it stays
            // legible on the translucent window backgrounds this app uses.
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private let color: Color
    private let textColor: Color?
    private let hoverColor: Color?
    private let width: CGFloat?
    private let height: CGFloat?
    private let circle: Bool
    private let radius: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let shadowSize: CGFloat
}

extension View {
    /// Apply a modifier only when an optional is present, without breaking the view's type at
    /// the call site.
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, @ViewBuilder transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Well-known paths

/// The user's home directory. Named to match the call sites, which read `HOME / "Library"`.
let HOME = FilePath(NSHomeDirectory())

// MARK: - Animations

extension Animation {
    /// The house spring: quick, lightly damped, interruptible. Used for toolbar rows appearing
    /// and disappearing as modifiers are held, where a slower curve reads as lag.
    static let fastSpring = Animation.interactiveSpring(dampingFraction: 0.7)
}
