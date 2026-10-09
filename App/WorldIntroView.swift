import SwiftUI

/// Cartoon launch intro (1.49): the user's dotted world map rains in —
/// now in full cartoon colours — then a chunky sticker pin bounces in
/// underneath it and the wordmark pops with a sunny underline. The
/// parent dismisses it (or a tap skips).
struct WorldIntroView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var assembled = false
    @State private var showTitle = false
    @State private var pinIn = false
    @State private var rings = false

    private struct Dot {
        let col: Int
        let row: Int
        let edge: Int
        let frac: CGFloat
        let delay: Double
        let color: Color
    }

    private static let palette: [Color] = [Toon.coral, Toon.sun, Toon.sky, Toon.mint, Toon.grape]
    private static let cols = 88
    private static let rows = 44
    private static let mask: [String] = [
        ".......................######....#####..................................................",
        "..................#..####..############........##..................#....................",
        "...............###.#.#.......##########...................##.......#####......#.........",
        ".............####..#..##.......########..................#...#..############..#.........",
        "....######.####.###.##.#.###....######..........####.......#.########################.##",
        "##.####################...#.#..####...##.......#####..##################################",
        "....#################......#....##............##.#######################################",
        "....##....###########....##..................###..##############################.#.#....",
        "............###########..####.................##.#############################....##....",
        "............############.#####.............#.##################################...#.....",
        "..............###############...............##################################..........",
        "..............###############...............#######.####.#####################..........",
        "..............#############...............###...###...##.####################.#.........",
        "..............############................##.....#######.################.#...#.........",
        "..............###########.................#.###..#...#####################.#.#..........",
        "...............##########.................#####......#####################..#...........",
        "................######.#..................################################..............",
        "................####.....................###########.###.################...............",
        "..................##....................##################...#############..............",
        "..................##..#..#..............#############.####....###..###..................",
        "....................##..................#################.....##...###...#..............",
        "......................##................##############.#......##....###.................",
        ".......................#...##...........################.......#........................",
        ".........................#####...........###############............#.....#.............",
        ".........................######...............##########................#...............",
        "........................########..............#########.............#..###..............",
        "........................##########............########...............#.#.#..###.........",
        "........................###########............######.........................###.......",
        ".........................##########............#######....................#.............",
        ".........................##########............#######......................#...........",
        "..........................########.............#######.#..................###..#........",
        "...........................#######.............######..#..................######........",
        "...........................#######.............######..#................#########.......",
        "...........................#####................####....................#########.......",
        "...........................#####................####....................##########......",
        "...........................####.................###.....................###..####.......",
        "..........................####................................................###.....#.",
        "..........................####.........................................................#",
        "..........................##..........................................................#.",
        "..........................##.........................................................#..",
        "..........................##............................................................",
        "..........................#..#..........................................................",
        "...........................#............................................................",
        "........................................................................................"
    ]
    private static let dots: [Dot] = buildDots()

    private static func buildDots() -> [Dot] {
        // Deterministic LCG: identical flight pattern on every render.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 11) & 0x1FFFFFFFFFFFFF) / Double(0x20000000000000)
        }
        var out: [Dot] = []
        for (r, line) in mask.enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" {
                out.append(Dot(col: c, row: r, edge: Int(rnd() * 4),
                               frac: CGFloat(rnd()), delay: rnd() * 0.5,
                               color: palette[Int(rnd() * Double(palette.count)) % palette.count]))
            }
        }
        return out
    }

    /// Downward triangle (pin tail) — straight lines only.
    private struct TailShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    /// Chunky cartoon pin from primitive shapes.
    private var pin: some View {
        ZStack {
            TailShape()
                .fill(Toon.coral)
                .frame(width: 36, height: 30)
                .offset(y: 30)
            TailShape()
                .stroke(Toon.ink, lineWidth: 5)
                .frame(width: 36, height: 30)
                .offset(y: 30)
            Circle()
                .fill(Toon.coral)
                .frame(width: 58, height: 58)
                .overlay(Circle().stroke(Toon.ink, lineWidth: 5))
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Toon.ink, lineWidth: 4))
        }
        .frame(width: 64, height: 84)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cell = min(w / CGFloat(Self.cols), h * 0.52 / CGFloat(Self.rows))
            let mapW = cell * CGFloat(Self.cols)
            let mapH = cell * CGFloat(Self.rows)
            let ox = (w - mapW) / 2
            let oy = (h - mapH) / 2 - 58
            let dark = scheme == .dark
            ZStack {
                (dark ? Color(red: 0.06, green: 0.06, blue: 0.08)
                      : Color(red: 1.0, green: 0.965, blue: 0.89))
                    .ignoresSafeArea()
                ForEach(Array(Self.dots.enumerated()), id: \.offset) { _, d in
                    let target = CGPoint(x: ox + (CGFloat(d.col) + 0.5) * cell,
                                         y: oy + (CGFloat(d.row) + 0.5) * cell)
                    let start: CGPoint = switch d.edge {
                    case 0: CGPoint(x: d.frac * w, y: -30)
                    case 1: CGPoint(x: d.frac * w, y: h + 30)
                    case 2: CGPoint(x: -30, y: d.frac * h)
                    default: CGPoint(x: w + 30, y: d.frac * h)
                    }
                    Circle()
                        .fill(d.color)
                        .frame(width: cell * 0.62, height: cell * 0.62)
                        .overlay(Circle().stroke(Toon.ink, lineWidth: 0.7))
                        .position(assembled ? target : start)
                        .animation(.spring(response: 0.9, dampingFraction: 0.82).delay(d.delay),
                                   value: assembled)
                }
                // Pulse rings + bouncing pin under the world
                ZStack {
                    Ellipse()
                        .stroke(Toon.coral, lineWidth: 3)
                        .frame(width: 92, height: 26)
                        .scaleEffect(rings ? 1.5 : 0.4)
                        .opacity(rings ? 0 : 0.8)
                        .offset(y: 36)
                    Ellipse()
                        .fill(Toon.ink.opacity(0.18))
                        .frame(width: 60, height: 15)
                        .offset(y: 36)
                        .scaleEffect(pinIn ? 1 : 0.3)
                    pin
                        .offset(y: pinIn ? -6 : -280)
                        .rotationEffect(.degrees(pinIn ? 0 : -14))
                }
                .position(x: w / 2, y: oy + mapH + 96)
                // Wordmark with a sun-yellow underline
                VStack(spacing: 7) {
                    Text("وجهتي")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(dark ? Color.white : Toon.ink)
                    Capsule()
                        .fill(Toon.sun)
                        .frame(width: 96, height: 10)
                        .overlay(Capsule().stroke(Toon.ink, lineWidth: 2))
                        .scaleEffect(x: showTitle ? 1 : 0.01)
                }
                .scaleEffect(showTitle ? 1 : 0.4)
                .opacity(showTitle ? 1 : 0)
                .position(x: w / 2, y: oy + mapH + 168)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            assembled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.52)) { pinIn = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { showTitle = true }
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { rings = true }
            }
        }
    }
}
