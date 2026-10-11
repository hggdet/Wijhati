import SwiftUI

/// One shared Liquid Glass treatment for pills, cards, and circular map controls.
/// The tint is kept behind the content so labels remain crisp in both themes.
struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @Environment(\.colorScheme) private var scheme

    private var level: Double { min(max(glassLevel, 0), 1) }
    private var dark: Bool { scheme == .dark }
    private var tintOpacity: Double { (1 - level) * (dark ? 0.09 : 0.34) }

    private var wash: LinearGradient {
        let opacity = (1 - level) * (dark ? 0.075 : 0.30)
        let colors = dark
            ? [Color.white.opacity(opacity), Color.black.opacity(0.08)]
            : [Color.white.opacity(opacity), Color.white.opacity(opacity * 0.35)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var border: LinearGradient {
        let colors = dark
            ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
            : [Color.white.opacity(0.84), Color.black.opacity(0.07)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shadowOpacity: Double { dark ? 0.26 : 0.10 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if level < 0.03 {
            content
                .background(
                    dark ? Color(red: 0.12, green: 0.13, blue: 0.15) : Color.white,
                    in: shape
                )
                .overlay { shape.strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07), lineWidth: 1) }
                .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 3)
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.white.opacity(tintOpacity)).interactive(), in: shape)
                .overlay { shape.strokeBorder(border, lineWidth: 1) }
                .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 3)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(wash)
                    }
                }
                .overlay { shape.strokeBorder(border, lineWidth: 1) }
                .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 3)
        }
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
