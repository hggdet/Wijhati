import SwiftUI
import CoreLocation

enum MapStyleKind: String, CaseIterable {
    case standard, bright, cartoon, satellite
    var label: String {
        switch self {
        case .standard: return "قياسية"
        case .bright: return "فاتحة"
        case .cartoon: return "كرتونية 🎨"
        case .satellite: return "قمر صناعي"
        }
    }
    var isRaster: Bool { self == .cartoon || self == .satellite }
}

struct CenterRequest: Equatable {
    var coordinate: CLLocationCoordinate2D
    var zoom: Double
    var id: UUID = UUID()
    static func == (lhs: CenterRequest, rhs: CenterRequest) -> Bool { lhs.id == rhs.id }
}

// TEMPORARY STUB for build bisection — replaced by the real MapLibre bridge.
struct MapBridge: View {
    var pins: [Place]
    var routeCoords: [CLLocationCoordinate2D]
    var altRouteCoords: [CLLocationCoordinate2D]
    var tripCoords: [CLLocationCoordinate2D]
    var isoPolygon: [CLLocationCoordinate2D]
    var styleKind: MapStyleKind
    var show3D: Bool
    var radarTimestamp: Int?
    var followUser: Bool
    var centerRequest: CenterRequest?
    var onSelectPin: (Place) -> Void

    var body: some View {
        Rectangle().fill(Color.gray.opacity(0.3))
    }
}
