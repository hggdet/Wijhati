import SwiftUI
import UIKit

// MARK: - Progressive (gradient) blur — native take on expo-backdrop
/// Blur that is strongest at one edge and fades away, like the iOS 26
/// scroll-edge effect. Used as soft veils over the map's top and bottom.
struct ProgressiveBlurView: UIViewRepresentable {
    enum Edge { case top, bottom }
    var edge: Edge = .top

    func makeUIView(context: Context) -> ProgressiveBlurUIView {
        ProgressiveBlurUIView(edge: edge)
    }
    func updateUIView(_ uiView: ProgressiveBlurUIView, context: Context) {}

    final class ProgressiveBlurUIView: UIVisualEffectView {
        private let gradient = CAGradientLayer()

        init(edge: Edge) {
            super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            gradient.colors = [UIColor.white.cgColor, UIColor.clear.cgColor]
            if edge == .top {
                gradient.startPoint = CGPoint(x: 0.5, y: 0)
                gradient.endPoint = CGPoint(x: 0.5, y: 1)
            } else {
                gradient.startPoint = CGPoint(x: 0.5, y: 1)
                gradient.endPoint = CGPoint(x: 0.5, y: 0)
            }
            layer.mask = gradient
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = bounds
        }
    }
}
