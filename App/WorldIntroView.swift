import SwiftUI

/// Launch intro (merged concept): pastel fragments fly together and
/// assemble the brand pin (logo-reveal by assembly), the pin then drops
/// with a spring onto the map, pulses, and draws a dotted route to a
/// destination dot (one motif connecting every beat) — then the
/// wordmark lands. Primitive shapes only; one `go` flag drives every
/// beat through animation delays. Tap-to-skip and auto-dismiss are
/// handled by the host (ContentView), as before.
struct WorldIntroView: View {
    @State private var go = false

    private let brand = Color(red: 0.996, green: 0.286, blue: 0.212) // #FE4936
    private let teal = Color(red: 0.04, green: 0.72, blue: 0.60)

    private struct Fragment {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let color: Color
    }

    private let fragments: [Fragment] = [
        Fragment(dx: -150, dy: -120, size: 13, color: Color(red: 0.85, green: 0.55, blue: 0.30)),
        Fragment(dx: 140, dy: -140, size: 10, color: Color(red: 0.25, green: 0.62, blue: 0.95)),
        Fragment(dx: -170, dy: 30, size: 9, color: Color(red: 0.24, green: 0.85, blue: 0.60)),
        Fragment(dx: 165, dy: 55, size: 12, color: Color(red: 0.996, green: 0.78, blue: 0.24)),
        Fragment(dx: -90, dy: 130, size: 10, color: Color(red: 0.55, green: 0.42, blue: 0.95)),
        Fragment(dx: 95, dy: 140, size: 9, color: Color(red: 0.25, green: 0.62, blue: 0.95)),
        Fragment(dx: -40, dy: -170, size: 8, color: Color(red: 0.24, green: 0.85, blue: 0.60)),
        Fragment(dx: 55, dy: -165, size: 11, color: Color(red: 0.996, green: 0.286, blue: 0.212)),
        Fragment(dx: 0, dy: 175, size: 8, color: Color(red: 0.85, green: 0.55, blue: 0.30)),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.914, green: 0.953, blue: 0.867),
                                    Color(red: 0.984, green: 0.965, blue: 0.918)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Circle().fill(Color(red: 0.725, green: 0.875, blue: 0.965).opacity(0.55))
                .frame(width: 300, height: 300).blur(radius: 60)
                .offset(x: -130, y: -260)
            Circle().fill(Color(red: 0.80, green: 0.93, blue: 0.72).opacity(0.55))
                .frame(width: 280, height: 280).blur(radius: 60)
                .offset(x: 140, y: 240)

            VStack(spacing: 16) {
                pinStage
                    .frame(height: 210)
                VStack(spacing: 8) {
                    Text("وجهتي")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(Color(red: 0.13, green: 0.16, blue: 0.13))
                    Capsule().fill(brand)
                        .frame(width: 64, height: 5)
                        .scaleEffect(x: go ? 1 : 0, anchor: .center)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(1.95), value: go)
                    Text("خرائط • ملاحة • ذكاء محلي")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.35))
                }
                .opacity(go ? 1 : 0)
                .offset(y: go ? 0 : 14)
                .animation(.easeOut(duration: 0.55).delay(1.75), value: go)
            }
        }
        .ignoresSafeArea()
        .onAppear { go = true }
    }

    private var pinStage: some View {
        ZStack {
            // Assembly fragments: scattered dots converge into the pin.
            ForEach(Array(fragments.enumerated()), id: \.offset) { i, f in
                Circle().fill(f.color)
                    .frame(width: f.size, height: f.size)
                    .offset(x: go ? 0 : f.dx, y: go ? -18 : f.dy)
                    .opacity(go ? 0 : 1)
                    .animation(.spring(response: 0.85, dampingFraction: 0.82).delay(0.10 + Double(i) * 0.05),
                               value: go)
            }
            // Pulse rings from the pin tip after it lands.
            ForEach(0..<2, id: \.self) { i in
                Circle().stroke(brand.opacity(0.45), lineWidth: 2.5)
                    .frame(width: 54, height: 54)
                    .scaleEffect(go ? 2.1 : 0.3)
                    .opacity(go ? 0 : 0.55)
                    .offset(y: 52)
                    .animation(.easeOut(duration: 0.95).delay(1.25 + Double(i) * 0.22), value: go)
            }
            // Dotted route drawn from the pin to a destination dot.
            Path { p in
                p.move(to: CGPoint(x: -6, y: 58))
                p.addLine(to: CGPoint(x: 52, y: 84))
                p.addLine(to: CGPoint(x: 118, y: 74))
                p.addLine(to: CGPoint(x: 168, y: 102))
            }
            .trim(from: 0, to: go ? 1 : 0)
            .stroke(brand, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 13]))
            .frame(width: 200, height: 130)
            .offset(x: 30, y: 6)
            .animation(.easeInOut(duration: 0.75).delay(1.35), value: go)
            Circle().fill(teal)
                .frame(width: 15, height: 15)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .offset(x: 196, y: 108)
                .scaleEffect(go ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(2.05), value: go)
            // The pin itself: brand-red disc + white core + line triangle.
            VStack(spacing: -5) {
                ZStack {
                    Circle().fill(brand).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 32, height: 32)
                }
                Path { p in
                    p.move(to: CGPoint(x: 6, y: 0))
                    p.addLine(to: CGPoint(x: 34, y: 0))
                    p.addLine(to: CGPoint(x: 20, y: 26))
                    p.closeSubpath()
                }
                .fill(brand)
                .frame(width: 40, height: 26)
            }
            .offset(y: go ? -18 : -190)
            .scaleEffect(go ? 1 : 0.55)
            .animation(.spring(response: 0.62, dampingFraction: 0.58).delay(0.60), value: go)
        }
    }
}
