import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - Walking AR navigation: live camera + floating guidance arrow
struct ARNavView: View {
    @ObservedObject var locationService: LocationService
    var target: CLLocationCoordinate2D
    var instruction: String
    var distance: Double
    @Environment(\.dismiss) private var dismiss
    @State private var cameraDenied = false

    private var bearing: Double {
        guard let loc = locationService.location else { return 0 }
        let from = loc.coordinate
        let dLon = (target.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(target.latitude * .pi / 180)
        let x = cos(from.latitude * .pi / 180) * sin(target.latitude * .pi / 180) -
                sin(from.latitude * .pi / 180) * cos(target.latitude * .pi / 180) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    private var relative: Double {
        var r = bearing - locationService.heading
        while r > 180 { r -= 360 }
        while r < -180 { r += 360 }
        return r
    }
    private var aligned: Bool { abs(relative) < 15 }

    var body: some View {
        ZStack {
            if cameraDenied {
                Color.black.ignoresSafeArea()
                Text("فعّل الكاميرا من إعدادات النظام حتى تشتغل الملاحة بالكاميرا.".loc)
                    .foregroundStyle(.white).multilineTextAlignment(.center).padding(30)
            } else {
                CameraPreview().ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                }
                .padding(.horizontal, 16).padding(.top, 10)
                Spacer()
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(aligned ? .green : .white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .rotationEffect(.degrees(relative))
                    .animation(.easeOut(duration: 0.25), value: relative)
                Text(aligned ? "امشِ مباشرة ✅".loc : (relative > 0 ? "لف يميناً".loc : "لف يساراً".loc))
                    .font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black.opacity(0.45), in: Capsule())
                Spacer()
                VStack(spacing: 4) {
                    Text(instruction).font(.headline).multilineTextAlignment(.center)
                    Text(distance < 1000 ? "\(Int(distance.rounded())) \("م".loc)" : String(format: "%.1f %@", distance / 1000, "كم".loc))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16).padding(.bottom, 22)
            }
        }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                cameraDenied = !(await AVCaptureDevice.requestAccess(for: .video))
            case .denied, .restricted:
                cameraDenied = true
            default:
                break
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewView { PreviewView() }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) { uiView.stop() }

    final class PreviewView: UIView {
        private let session = AVCaptureSession()
        private var started = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            start()
        }
        required init?(coder: NSCoder) { super.init(coder: coder); start() }
        private func start() {
            guard !started,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            started = true
            session.addInput(input)
            (layer as? AVCaptureVideoPreviewLayer)?.session = session
            (layer as? AVCaptureVideoPreviewLayer)?.videoGravity = .resizeAspectFill
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
        func stop() {
            if session.isRunning { session.stopRunning() }
        }
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }
}
