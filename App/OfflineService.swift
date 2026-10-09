import Foundation
import CoreLocation
import MapLibre

// MARK: - Offline map regions via MapLibre offline storage
//
// Crash history (1.30-1.34): this flow kept dying on the user's device.
// The pattern below now follows MapLibre's documented usage strictly:
//  - reloadPacks() runs ONCE at startup. It invalidates pack objects, so
//    calling it while the list is on screen or mid-download is dangerous.
//  - The list renders value snapshots (OfflinePackInfo), never live pack
//    objects, so SwiftUI re-renders can't touch a pack mid-invalidation.
//  - Progress notifications only refresh the snapshot, throttled.

struct OfflinePackInfo: Identifiable {
    var id: ObjectIdentifier
    var name: String
    var stateText: String
    var sizeText: String
}

final class OfflineManager: ObservableObject {
    @Published var infos: [OfflinePackInfo] = []
    @Published var downloading = false
    @Published var fraction: Double = 0
    @Published var lastError: String?

    private var packsByID: [ObjectIdentifier: MLNOfflinePack] = [:]
    private var lastSnapshotAt = Date.distantPast

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(progressChanged(_:)),
                                               name: Notification.Name.MLNOfflinePackProgressChanged, object: nil)
        MLNOfflineStorage.shared.reloadPacks()
        refreshSnapshot()
    }

    @objc private func progressChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Progress notifications arrive in bursts; 2 refreshes/sec is plenty.
            if Date().timeIntervalSince(self.lastSnapshotAt) < 0.5 { return }
            self.refreshSnapshot()
        }
    }

    func refreshSnapshot() {
        lastSnapshotAt = Date()
        let packs = MLNOfflineStorage.shared.packs ?? []
        packsByID = Dictionary(uniqueKeysWithValues: packs.map { (ObjectIdentifier($0), $0) })
        var anyActive = false
        var best = 0.0
        infos = packs.map { pack in
            let p = pack.progress
            if pack.state == .active {
                anyActive = true
                if p.countOfResourcesExpected > 0 {
                    best = max(best, Double(p.countOfResourcesCompleted) / Double(p.countOfResourcesExpected))
                }
            }
            return OfflinePackInfo(id: ObjectIdentifier(pack),
                                   name: String(data: pack.context, encoding: .utf8) ?? "منطقة محمّلة",
                                   stateText: Self.stateText(of: pack),
                                   sizeText: Self.sizeText(of: pack))
        }
        downloading = anyActive
        fraction = anyActive ? best : 0
    }

    func download(styleURL: URL, center: CLLocationCoordinate2D, name: String) {
        let half = 0.14 // ≈ 15 km each direction
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: center.latitude - half, longitude: center.longitude - half),
            ne: CLLocationCoordinate2D(latitude: center.latitude + half, longitude: center.longitude + half))
        addPack(styleURL: styleURL, bounds: bounds, fromZoom: 10, toZoom: 15, name: name)
    }

    /// Whole-city download (Nominatim bounding box). Capped at zoom 14:
    /// a full city at zoom 15 would be several GB.
    func downloadRegion(styleURL: URL, sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D, name: String) {
        addPack(styleURL: styleURL, bounds: MLNCoordinateBounds(sw: sw, ne: ne),
                fromZoom: 10, toZoom: 14, name: name)
    }

    private func addPack(styleURL: URL, bounds: MLNCoordinateBounds,
                         fromZoom: Double, toZoom: Double, name: String) {
        guard !downloading else { return }
        lastError = nil
        // Use the map's own current style URL, exactly like MapLibre's
        // documented offline example.
        let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: bounds,
                                                  fromZoomLevel: fromZoom, toZoomLevel: toZoom)
        let context = name.data(using: .utf8) ?? Data()
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
            DispatchQueue.main.async {
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                pack?.resume()
                self?.downloading = true
                self?.refreshSnapshot()
            }
        }
    }

    func delete(_ info: OfflinePackInfo) {
        guard let pack = packsByID[info.id] else { return }
        MLNOfflineStorage.shared.removePack(pack) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshSnapshot() }
        }
    }

    private static func stateText(of pack: MLNOfflinePack) -> String {
        switch pack.state {
        case .complete: return "مكتمل ✓"
        case .active: return "يُحمّل…"
        case .inactive: return "متوقف"
        default: return "—"
        }
    }

    private static func sizeText(of pack: MLNOfflinePack) -> String {
        let bytes = pack.progress.countOfBytesCompleted
        if bytes <= 0 { return "جارٍ الحساب…" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
