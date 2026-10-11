import SwiftUI

/// A quiet, branded launch screen: a miniature route map, a short promise,
/// and one clear action. The host also dismisses it automatically.
struct WorldIntroView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false

    private let brand = Color(red: 0.96, green: 0.31, blue: 0.22)
    private let teal = Color(red: 0.06, green: 0.66, blue: 0.54)
    private let ink = Color(red: 0.13, green: 0.17, blue: 0.15)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 0.92),
                         Color(red: 0.99, green: 0.97, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.72, green: 0.86, blue: 0.80).opacity(0.45))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -150, y: -250)
            Circle()
                .fill(Color(red: 0.98, green: 0.78, blue: 0.57).opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 155, y: 250)

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                mapIllustration
                    .frame(maxWidth: 330)
                    .frame(height: 250)

                VStack(spacing: 9) {
                    Text("وجهتي")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .tracking(-1)
                        .foregroundStyle(ink)

                    Text("خرائط وملاحة عربية للعالم كله".loc)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.top, 28)
                .opacity(reveal ? 1 : 0)
                .offset(y: reveal ? 0 : 12)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.16), value: reveal)

                Spacer(minLength: 30)

                Button(action: onContinue) {
                    HStack(spacing: 10) {
                        Text("ابدأ رحلتك".loc)
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [brand, Color(red: 0.86, green: 0.24, blue: 0.19)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                    )
                    .shadow(color: brand.opacity(0.23), radius: 18, y: 8)
                }
                .buttonStyle(IntroButtonPressStyle())
                .accessibilityLabel("ابدأ رحلتك".loc)
                .padding(.horizontal, 16)
                .opacity(reveal ? 1 : 0)
                .offset(y: reveal ? 0 : 14)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.28), value: reveal)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                reveal = true
            } else {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.84)) {
                    reveal = true
                }
            }
        }
    }

    private var mapIllustration: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.86, green: 0.92, blue: 0.81),
                             Color(red: 0.91, green: 0.95, blue: 0.87)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    path.move(to: CGPoint(x: -size.width * 0.12, y: size.height * 0.66))
                    path.addCurve(to: CGPoint(x: size.width * 0.55, y: size.height * 0.24),
                                  control1: CGPoint(x: size.width * 0.12, y: size.height * 0.54),
                                  control2: CGPoint(x: size.width * 0.18, y: size.height * 0.10))
                    path.addCurve(to: CGPoint(x: size.width * 1.12, y: size.height * 0.45),
                                  control1: CGPoint(x: size.width * 0.79, y: size.height * 0.35),
                                  control2: CGPoint(x: size.width * 0.93, y: size.height * 0.61))
                }
                .stroke(Color.white.opacity(0.82),
                        style: StrokeStyle(lineWidth: 25, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.16, y: -size.height * 0.08))
                    path.addCurve(to: CGPoint(x: size.width * 0.78, y: size.height * 1.08),
                                  control1: CGPoint(x: size.width * 0.27, y: size.height * 0.34),
                                  control2: CGPoint(x: size.width * 0.75, y: size.height * 0.57))
                }
                .stroke(Color.white.opacity(0.58),
                        style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.13, y: size.height * 0.83))
                    path.addCurve(to: CGPoint(x: size.width * 0.82, y: size.height * 0.29),
                                  control1: CGPoint(x: size.width * 0.26, y: size.height * 0.51),
                                  control2: CGPoint(x: size.width * 0.61, y: size.height * 0.77))
                }
                .trim(from: 0, to: reveal ? 1 : 0)
                .stroke(brand, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 10]))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.95).delay(0.2), value: reveal)

                Circle()
                    .fill(teal)
                    .frame(width: 17, height: 17)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: teal.opacity(0.25), radius: 6, y: 3)
                    .position(x: size.width * 0.82, y: size.height * 0.29)

                ZStack {
                    Circle().fill(brand)
                    Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                    Image(systemName: "location.fill")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)
                .shadow(color: brand.opacity(0.27), radius: 12, y: 6)
                .scaleEffect(reveal ? 1 : 0.58)
                .opacity(reveal ? 1 : 0)
                .position(x: size.width * 0.42, y: size.height * 0.54)
                .animation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.62).delay(0.25), value: reveal)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.24, green: 0.36, blue: 0.28).opacity(0.14), radius: 28, y: 14)
            .scaleEffect(reveal ? 1 : 0.95)
            .offset(y: reveal ? 0 : 16)
            .opacity(reveal ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.82), value: reveal)
        }
    }
}

private struct IntroButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58),
                       value: configuration.isPressed)
    }
}
