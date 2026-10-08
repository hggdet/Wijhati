import SwiftUI

/// Liquid Glass surface with a graceful fallback for older systems.
struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    @AppStorage("wijhati.glassMode") private var glassMode = "glass"
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if glassMode == "solid" {
            content
                .background(scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.black.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.white.opacity(0.55)).interactive(),
                             in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.30))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1)
                )
        }
    }
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
