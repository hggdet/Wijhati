import Foundation
import CoreLocation
import MapKit

struct SavedPlace: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?
    var isFavorite: Bool = false
    var visited: Bool = false
    var note: String = ""
    var savedAt: Date = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class PlacesStore: ObservableObject {
    @Published var places: [SavedPlace] = [] {
        didSet { persist() }
    }

    private let key = "wijhati.savedPlaces.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        places.contains {
            abs($0.latitude - latitude) < 0.00005 && abs($0.longitude - longitude) < 0.00005
        }
    }

    @discardableResult
    func toggle(_ place: SavedPlace) -> Bool {
        if let idx = places.firstIndex(where: {
            abs($0.latitude - place.latitude) < 0.00005 && abs($0.longitude - place.longitude) < 0.00005
        }) {
            places.remove(at: idx)
            return false
        } else {
            places.insert(place, at: 0)
            return true
        }
    }

    func setFavorite(_ place: SavedPlace, _ value: Bool) {
        guard let idx = places.firstIndex(of: place) else { return }
        places[idx].isFavorite = value
    }

    func remove(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
    }
}

struct PlaceResult: Identifiable, Equatable {
    var id: String { "\(name)-\(coordinate.latitude)-\(coordinate.longitude)" }
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var phone: String?
    var website: URL?
    var category: String?

    static func == (lhs: PlaceResult, rhs: PlaceResult) -> Bool { lhs.id == rhs.id }

    init(mapItem: MKMapItem) {
        name = mapItem.name ?? "مكان بدون اسم"
        let pm = mapItem.placemark
        var parts: [String] = []
        if let sub = pm.subLocality { parts.append(sub) }
        if let city = pm.locality { parts.append(city) }
        if let country = pm.country { parts.append(country) }
        address = parts.joined(separator: "، ")
        coordinate = pm.coordinate
        phone = mapItem.phoneNumber
        website = mapItem.url
        category = mapItem.pointOfInterestCategory?.rawValue
    }

    init(saved: SavedPlace) {
        name = saved.name
        address = saved.address
        coordinate = saved.coordinate
        phone = saved.phone
        website = saved.website.flatMap { URL(string: $0) }
        category = nil
    }

    var asSavedPlace: SavedPlace {
        SavedPlace(name: name, address: address,
                   latitude: coordinate.latitude, longitude: coordinate.longitude,
                   phone: phone, website: website?.absoluteString)
    }

    var appleMapsURL: URL {
        URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "place")")!
    }
}

enum TransportChoice: String, CaseIterable, Identifiable {
    case driving, walking, cycling
    var id: String { rawValue }
    var label: String {
        switch self {
        case .driving: return "قيادة"
        case .walking: return "مشي"
        case .cycling: return "دراجة"
        }
    }
    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }
    var mkType: MKDirectionsTransportType {
        switch self {
        case .driving: return .automobile
        case .walking: return .walking
        case .cycling: return .cycling
        }
    }
}

func formatDistance(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int(meters.rounded())) م" }
    return String(format: "%.1f كم", meters / 1000)
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h) س \(m) د" }
    if m > 0 { return "\(m) د" }
    return "\(total) ث"
}
