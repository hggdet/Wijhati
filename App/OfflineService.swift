import Foundation
import CoreLocation
import MapLibre

// MARK: - Offline map regions via MapLibre offline storage

final class OfflineManager: ObservableObject {
    @Published var packs: [MLNOfflinePack] = []
    @Published var downloading = false
    @Published var fraction: Double = 0
    @Published var lastError: String?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(progressChanged(_:)),
                                               name: Notification.Name.MLNOfflinePackProgressChanged, object: nil)
        reload()
    }

    func reload() {
        MLNOfflineStorage.shared.reloadPacks()
        packs = MLNOfflineStorage.shared.packs ?? []
        updateState()
    }

    @objc private func progressChanged(_ notification: Notification) {
        // NOTE: never call requestProgress()/reload() from here — requesting
        // progress posts this same notification, which used to recurse until
        // the app froze and got killed. Just re-read the cached progress,
        // on the main thread (the notification can arrive on any queue).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.packs = MLNOfflineStorage.shared.packs ?? []
            self.updateState()
        }
    }

    private func updateState() {
        var anyActive = false
        var bestFraction = 0.0
        for pack in packs {
            if pack.state == .active {
                anyActive = true
                let p = pack.progress
                if p.countOfResourcesExpected > 0 {
                    bestFraction = max(bestFraction,
                                       Double(p.countOfResourcesCompleted) / Double(p.countOfResourcesExpected))
                }
            }
            if pack.state == .complete { bestFraction = max(bestFraction, 1) }
        }
        downloading = anyActive
        fraction = anyActive ? bestFraction : (packs.isEmpty ? 0 : fraction)
        if !anyActive { fraction = 0 }
    }

    func download(styleURL: URL, center: CLLocationCoordinate2D, name: String) {
        guard !downloading else { return }
        let half = 0.14 // ≈ 15 km each direction
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: center.latitude - half, longitude: center.longitude - half),
            ne: CLLocationCoordinate2D(latitude: center.latitude + half, longitude: center.longitude + half))
        let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: bounds,
                                                  fromZoomLevel: 10, toZoomLevel: 15)
        let context = (name.data(using: .utf8)) ?? Data()
        lastError = nil
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
            DispatchQueue.main.async {
                if let error { self?.lastError = error.localizedDescription }
                pack?.resume()
                self?.downloading = true
                self?.reload()
            }
        }
    }

    func delete(_ pack: MLNOfflinePack) {
        MLNOfflineStorage.shared.removePack(pack) { [weak self] _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func name(of pack: MLNOfflinePack) -> String {
        String(data: pack.context, encoding: .utf8) ?? "منطقة محمّلة"
    }

    func sizeText(of pack: MLNOfflinePack) -> String {
        let bytes = pack.progress.countOfBytesCompleted
        if bytes <= 0 { return "جارٍ الحساب…" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func stateText(of pack: MLNOfflinePack) -> String {
        switch pack.state {
        case .complete: return "مكتمل ✓"
        case .active: return "يُحمّل…"
        case .inactive: return "متوقف"
        default: return "—"
        }
    }
}
