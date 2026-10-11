import SwiftUI

/// Short, skippable launch moment. The live map is already loading underneath it.
struct WorldIntroView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var reveal = false
    @State private var routeProgress: CGFloat = 0
    @State private var pulse = false
    @State private var continued = false

    private let accent = Color(red: 0.08, green: 0.53, blue: 0.96)
    private let brand = Color(red: 0.96, green: 0.31, blue: 0.22)
    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.035, green: 0.055, blue: 0.10), Color(red: 0.07, green: 0.095, blue: 0.15)]
                        : [Color(red: 0.91, green: 0.96, blue: 1.0), Color(red: 0.99, green: 0.98, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(accent.opacity(dark ? 0.18 : 0.14))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: -170, y: -250)
                Circle()
                    .fill(brand.opacity(dark ? 0.13 : 0.10))
                    .frame(width: 280, height: 280)
                    .blur(radius: 85)
                    .offset(x: 170, y: 260)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, max(proxy.safeAreaInsets.top, 22) + 10)

                    Spacer(minLength: 12)

                    mapIllustration
                        .frame(maxWidth: 360)
                        .frame(height: min(max(proxy.size.height * 0.40, 220), 330))
                        .padding(.horizontal, 22)

                    VStack(spacing: 9) {
                        Text("وجهتي")
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .tracking(-0.8)
                            .foregroundStyle(adaptiveInk)

                        Text("خرائط وملاحة عربية أنيقة".loc)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(adaptiveSecondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .opacity(reveal ? 1 : 0)
                    .offset(y: reveal ? 0 : 16)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.46).delay(0.16), value: reveal)

                    Spacer(minLength: 24)

                    Button(action: continueOnce) {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("ابدأ رحلتك".loc)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(colors: [brand, Color(red: 0.83, green: 0.22, blue: 0.19)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .shadow(color: brand.opacity(0.28), radius: 20, y: 9)
                    }
                    .buttonStyle(AppPressStyle())
                    .padding(.horizontal, 24)
                    .opacity(reveal ? 1 : 0)
                    .offset(y: reveal ? 0 : 14)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.42).delay(0.28), value: reveal)

                    Spacer(minLength: max(proxy.safeAreaInsets.bottom, 18) + 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            guard !Task.isCancelled else { return }
            continueOnce()
        }
        .onAppear {
            if reduceMotion {
                reveal = true
                routeProgress = 1
                pulse = true
                return
            }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) { reveal = true }
            withAnimation(.easeInOut(duration: 1.15).delay(0.12)) { routeProgress = 1 }
            withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [accent, Color(red: 0.03, green: 0.38, blue: 0.78)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: accent.opacity(0.24), radius: 10, y: 4)

            Text("وجهتي")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(adaptiveInk)

            Spacer()

            Button(action: continueOnce) {
                Text("تخطي".loc)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(adaptiveInk)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .glass(cornerRadius: 19)
            }
            .buttonStyle(AppPressStyle())
        }
        .opacity(reveal ? 1 : 0)
        .offset(y: reveal ? 0 : -10)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.38), value: reveal)
    }

    private var mapIllustration: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let path = routePath(in: size)

            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(dark
                          ? LinearGradient(colors: [Color(red: 0.11, green: 0.15, blue: 0.22), Color(red: 0.08, green: 0.11, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color(red: 0.87, green: 0.93, blue: 0.88), Color(red: 0.91, green: 0.96, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))

                Path { roads in
                    for index in 0...6 {
                        let x = size.width * CGFloat(index) / 6
                        roads.move(to: CGPoint(x: x - 18, y: -8))
                        roads.addLine(to: CGPoint(x: x + 24, y: size.height + 8))
                    }
                    for index in 0...5 {
                        let y = size.height * CGFloat(index) / 5
                        roads.move(to: CGPoint(x: -8, y: y + 14))
                        roads.addLine(to: CGPoint(x: size.width + 8, y: y - 18))
                    }
                }
                .stroke(dark ? Color.white.opacity(0.09) : Color(red: 0.37, green: 0.47, blue: 0.41).opacity(0.11), lineWidth: 1)

                path.stroke(dark ? Color.white.opacity(0.10) : Color.white.opacity(0.92),
                            style: StrokeStyle(lineWidth: 29, lineCap: .round, lineJoin: .round))

                path.stroke(accent.opacity(dark ? 0.22 : 0.16),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                path.trim(from: 0, to: routeProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                Circle()
                    .stroke(accent.opacity(pulse ? 0.18 : 0.52), lineWidth: 1.5)
                    .frame(width: pulse ? 58 : 34, height: pulse ? 58 : 34)
                    .position(x: size.width * 0.18, y: size.height * 0.76)

                Circle()
                    .fill(accent)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: accent.opacity(0.45), radius: 12, y: 3)
                    .position(x: size.width * 0.18, y: size.height * 0.76)

                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(brand)
                    .shadow(color: brand.opacity(0.28), radius: 8, y: 3)
                    .position(x: size.width * 0.82, y: size.height * 0.24)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(adaptiveInk)
                    .frame(width: 42, height: 42)
                    .glassCircle()
                    .rotationEffect(.degrees(reveal ? 0 : -38))
                    .position(x: size.width * 0.83, y: size.height * 0.78)
                    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.72), value: reveal)
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.16) : Color.white.opacity(0.86), lineWidth: 1)
            }
            .shadow(color: .black.opacity(dark ? 0.30 : 0.13), radius: 28, y: 15)
            .scaleEffect(reveal ? 1 : 0.91)
            .rotation3DEffect(.degrees(reveal ? 0 : 8), axis: (x: 1, y: 0, z: 0))
            .opacity(reveal ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.80), value: reveal)
        }
    }

    private func routePath(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.82))
            path.addCurve(to: CGPoint(x: size.width * 0.82, y: size.height * 0.22),
                          control1: CGPoint(x: size.width * 0.38, y: size.height * 0.68),
                          control2: CGPoint(x: size.width * 0.49, y: size.height * 0.20))
        }
    }

    private func continueOnce() {
        guard !continued else { return }
        continued = true
        onContinue()
    }
}
