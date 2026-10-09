import SwiftUI

/// The TOON design system (1.48): the whole app wears a bold cartoon
/// identity — paper-white surfaces, thick ink borders and hard offset
/// shadows. Surfaces are always "paper", so their content is pinned
/// to the light scheme (dark text) whatever the device appearance is.
enum Toon {
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let paper = Color.white
    static let coral = Color(red: 0.996, green: 0.286, blue: 0.212)
    static let sun = Color(red: 1.0, green: 0.788, blue: 0.235)
    static let sky = Color(red: 0.243, green: 0.608, blue: 1.0)
    static let mint = Color(red: 0.243, green: 0.835, blue: 0.596)
    static let grape = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let tile = Color(red: 0.93, green: 0.93, blue: 0.96)
}

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(Toon.paper,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Toon.ink, lineWidth: 2)
            )
            .shadow(color: .black, radius: 0, x: 0, y: 4)
            .environment(\.colorScheme, .light)
    }
}

/// Ink for text and icons: near-black in light mode, near-white in dark
/// mode — keeps the user's bold black look readable on dark surfaces.
var adaptiveInk: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.97, alpha: 1)
            : UIColor(white: 0.06, alpha: 1)
    })
}

extension View {
    func glass(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius))
    }
}

/// Compact glass chip used for the category strip.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glass(cornerRadius: 17)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(cornerRadius: 20)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
