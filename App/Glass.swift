import SwiftUI

/// One shared Liquid Glass treatment for pills, cards, and circular map controls.
/// The tint is kept behind the content so labels remain crisp in both themes.
struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var level: Double { min(max(glassLevel, 0), 1) }
    private var dark: Bool { scheme == .dark }
    private var surfaceFill: Color {
        if reduceTransparency { return dark ? Color.black : Color.white }
        return dark
            ? Color.black.opacity(0.78 - level * 0.25)
            : Color.white.opacity(0.94 - level * 0.34)
    }

    private var border: LinearGradient {
        let colors: [Color]
        if reduceTransparency {
            colors = dark
                ? [Color.white.opacity(0.48), Color.white.opacity(0.34)]
                : [Color.black.opacity(0.30), Color.black.opacity(0.20)]
        } else {
            colors = dark
                ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
                : [Color.white.opacity(0.84), Color.black.opacity(0.07)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shadowOpacity: Double { dark ? 0.18 : 0.06 }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(surfaceFill))
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .shadow(color: .black.opacity(shadowOpacity), radius: 4, y: 2)
    }
}

/// Dynamic app ink: pure near-black in light mode and near-white in dark mode.
var adaptiveInk: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.97, alpha: 1)
            : UIColor(white: 0.06, alpha: 1)
    })
}

/// Secondary hierarchy stays within the same black/white palette.
var adaptiveSecondaryInk: Color {
    Color(UIColor { traits in
        let base = traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
        return base.withAlphaComponent(0.68)
    })
}

extension View {
    func glass(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassSurfaceModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func glassCircle() -> some View {
        modifier(GlassSurfaceModifier(shape: Circle()))
    }
}

/// Shared, restrained press feedback for buttons throughout the app.
struct AppPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74),
                       value: configuration.isPressed)
    }
}

/// Compact glass chip used for the category strip.
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glass(cornerRadius: 17)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74),
                       value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(cornerRadius: 20)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.74),
                       value: configuration.isPressed)
    }
}
