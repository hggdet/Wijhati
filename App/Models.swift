import Foundation
import CoreLocation

struct Place: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var phone: String?
    var website: String?
    var kind: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func make(name: String, address: String, lat: Double, lon: Double,
                     phone: String? = nil, website: String? = nil, kind: String? = nil) -> Place {
        Place(id: "\(lat),\(lon)-\(name)", name: name, address: address,
              latitude: lat, longitude: lon, phone: phone, website: website, kind: kind)
    }

    var mapsLink: URL {
        URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "place")")!
    }
}

struct SavedPlace: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var place: Place
    var isFavorite: Bool = false
    var visited: Bool = false
    var note: String = ""
    var savedAt: Date = Date()
}

final class PlacesStore: ObservableObject {
    @Published var places: [SavedPlace] = [] { didSet { persist() } }
    private let key = "wijhati.savedPlaces.v2"

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
    func contains(_ place: Place) -> Bool {
        places.contains { abs($0.place.latitude - place.latitude) < 0.00005 && abs($0.place.longitude - place.longitude) < 0.00005 }
    }
    @discardableResult
    func toggle(_ place: Place) -> Bool {
        if let idx = places.firstIndex(where: { abs($0.place.latitude - place.latitude) < 0.00005 && abs($0.place.longitude - place.longitude) < 0.00005 }) {
            places.remove(at: idx)
            return false
        }
        places.insert(SavedPlace(place: place), at: 0)
        return true
    }
    func setFavorite(_ saved: SavedPlace, _ value: Bool) {
        guard let idx = places.firstIndex(of: saved) else { return }
        places[idx].isFavorite = value
    }
    func remove(_ saved: SavedPlace) {
        places.removeAll { $0.id == saved.id }
    }
    func exportJSON() -> Data? { try? JSONEncoder().encode(places.map { $0.place }) }
    func importJSON(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode([Place].self, from: data) else { return }
        for p in decoded where !contains(p) {
            places.append(SavedPlace(place: p))
        }
    }
}

struct StepData: Identifiable, Equatable {
    var id = UUID()
    var instruction: String
    var distance: Double
    var coordinate: CLLocationCoordinate2D
    static func == (lhs: StepData, rhs: StepData) -> Bool { lhs.id == rhs.id }
}

struct RouteData: Identifiable, Equatable {
    var id = UUID()
    var distance: Double
    var duration: Double
    var coordinates: [CLLocationCoordinate2D]
    var steps: [StepData]
    static func == (lhs: RouteData, rhs: RouteData) -> Bool { lhs.id == rhs.id }
}

struct Trip: Codable, Identifiable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var distance: Double
    var points: [TripPoint]

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var averageSpeedKmh: Double {
        guard duration > 0 else { return 0 }
        return (distance / 1000) / (duration / 3600)
    }
    var coordinates: [CLLocationCoordinate2D] { points.map { $0.coordinate } }

    func gpx() -> String {
        let fmt = ISO8601DateFormatter()
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Wijhati\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n<trk><name>Wijhati Trip</name><trkseg>\n"
        for p in points {
            s += "<trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><time>\(fmt.string(from: p.date))</time></trkpt>\n"
        }
        s += "</trkseg></trk>\n</gpx>\n"
        return s
    }
}

struct TripPoint: Codable {
    var latitude: Double
    var longitude: Double
    var date: Date
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

final class TripsStore: ObservableObject {
    @Published var trips: [Trip] = [] { didSet { persist() } }
    private let key = "wijhati.trips.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = decoded
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func add(_ trip: Trip) { trips.insert(trip, at: 0) }
    func remove(_ trip: Trip) { trips.removeAll { $0.id == trip.id } }
}

/// Recent places the user picked from search (newest first, max 10).
final class SearchHistoryStore: ObservableObject {
    @Published var items: [Place] = [] { didSet { persist() } }
    private let key = "wijhati.searchHistory.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Place].self, from: data) {
            items = decoded
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func add(_ place: Place) {
        var list = items.filter { !(abs($0.latitude - place.latitude) < 0.0005 && abs($0.longitude - place.longitude) < 0.0005) }
        list.insert(place, at: 0)
        items = Array(list.prefix(10))
    }
    func clear() { items = [] }
}

enum TransportChoice: String, CaseIterable, Identifiable {
    case driving, walking, cycling
    var id: String { rawValue }
    var label: String {
        switch self {
        case .driving: return "قيادة".loc
        case .walking: return "مشي".loc
        case .cycling: return "دراجة".loc
        }
    }
    var icon: String {
        switch self {
        case .driving: return "car.fill"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        }
    }
    var osrmProfile: String {
        switch self {
        case .driving: return "driving"
        case .walking: return "foot"
        case .cycling: return "bike"
        }
    }
}

func formatDistance(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int(meters.rounded())) \("م".loc)" }
    return String(format: "%.1f %@", meters / 1000, "كم".loc)
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    if h > 0 { return "\(h) س \(m) د" }
    if m > 0 { return "\(m) د" }
    return "\(total) ث"
}
