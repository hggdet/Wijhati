import Foundation
import CoreLocation
import MapLibre

// TEMPORARY STUB for build bisection — replaced by the real offline manager.
final class OfflineManager: ObservableObject {
    @Published var packs: [MLNOfflinePack] = []
    @Published var downloading = false
    @Published var fraction: Double = 0
    @Published var lastError: String?

    func reload() {}
    func download(styleURL: URL, center: CLLocationCoordinate2D, name: String) {}
    func delete(_ pack: MLNOfflinePack) {}
    func name(of pack: MLNOfflinePack) -> String { "منطقة" }
    func sizeText(of pack: MLNOfflinePack) -> String { "—" }
    func stateText(of pack: MLNOfflinePack) -> String { "—" }
}
