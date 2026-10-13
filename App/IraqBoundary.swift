import Foundation
import CoreLocation

/// Point-in-polygon check using a simplified Natural Earth 10m Iraq boundary.
/// Source: https://github.com/martynafford/natural-earth-geojson
/// Natural Earth data is public domain; the GeoJSON conversion repository is CC0-1.0.
enum IraqBoundary {
    private static let rings: [[CLLocationCoordinate2D]] = {
        guard let url = Bundle.main.url(forResource: "iraq-boundary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]] else { return [] }
        return raw.compactMap { ring in
            let points = ring.compactMap { pair -> CLLocationCoordinate2D? in
                guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
            return points.count >= 3 ? points : nil
        }
    }()

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90.0...90.0).contains(coordinate.latitude),
              (-180.0...180.0).contains(coordinate.longitude),
              !rings.isEmpty else { return false }
        return rings.contains { contains(coordinate, in: $0) }
    }

    private static func contains(_ point: CLLocationCoordinate2D,
                                 in ring: [CLLocationCoordinate2D]) -> Bool {
        var isInside = false
        var previous = ring.count - 1
        for current in ring.indices {
            let a = ring[current]
            let b = ring[previous]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossingLongitude = (b.longitude - a.longitude)
                    * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if point.longitude < crossingLongitude { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }
}
