import SwiftUI

/// Lightweight translucent surface shared by pills, cards, and map controls.
/// Avoids blur, gradients, and shadows so stacked controls stay smooth.
struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var level: Double { min(max(glassLevel, 0), 1) }
    private var dark: Bool { scheme == .dark }

    private var surfaceFill: Color {
        if reduceTransparency { return dark ? Color.black : Color.white }
        let opacity = dark ? 0.92 - level * 0.20 : 0.97 - level * 0.18
        return (dark ? Color.black : Color.white).opacity(opacity)
    }

    private var border: Color {
        if reduceTransparency {
            return dark ? Color.white.opacity(0.42) : Color.black.opacity(0.26)
        }
        return dark ? Color.white.opacity(0.17) : Color.white.opacity(0.66)
    }

    func body(content: Content) -> some View {
        content
            .background(shape.fill(surfaceFill))
            .overlay { shape.strokeBorder(border, lineWidth: 0.75) }
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

/// Shared, restrained press feedback; opacity avoids costly scale compositing.
struct AppPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
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
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
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
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10),
                       value: configuration.isPressed)
    }
}
