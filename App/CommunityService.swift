import Foundation
import CoreLocation

// MARK: - Community places (Local Intelligence layer)
struct CommunityPlace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var note: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    func asPlace() -> Place {
        let bits = [category, note].filter { !$0.isEmpty }
        return Place(id: "community-\(id)", name: name,
                     address: (bits.joined(separator: " • ") + " • مكان محلي").trimmingCharacters(in: CharacterSet(charactersIn: " •")),
                     latitude: latitude, longitude: longitude, phone: nil, website: nil)
    }
}

final class CommunityStore: ObservableObject {
    @Published var myPlaces: [CommunityPlace] = [] { didSet { persist() } }
    @Published var remotePlaces: [CommunityPlace] = []
    @Published var remoteReports: [RoadReport] = []
    private let key = "wijhati.myPlaces.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CommunityPlace].self, from: data) {
            myPlaces = decoded
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(myPlaces) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var allPlaces: [CommunityPlace] {
        let mine = Set(myPlaces.map { $0.id })
        return myPlaces + remotePlaces.filter { !mine.contains($0.id) }
    }

    @discardableResult
    func addPlace(name: String, category: String, note: String, at coordinate: CLLocationCoordinate2D) -> CommunityPlace {
        let place = CommunityPlace(id: UUID().uuidString, name: name, category: category,
                                   note: note, latitude: coordinate.latitude,
                                   longitude: coordinate.longitude, createdAt: Date())
        myPlaces.insert(place, at: 0)
        Task { await Self.uploadPlace(place) }
        return place
    }

    func removeMyPlace(_ id: String) {
        myPlaces.removeAll { $0.id == id }
    }

    // MARK: Sync
    func refresh() async {
        guard Backend.isConfigured else { return }
        async let placeRows = Backend.fetchRows("local_places?select=*&order=created_at.desc&limit=300")
        async let reportRows = Backend.fetchRows("road_reports?select=*&order=created_at.desc&limit=200")
        let places = await placeRows.compactMap { row -> CommunityPlace? in
            guard let id = row["id"] as? String, let name = row["name"] as? String,
                  let lat = (row["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (row["longitude"] as? NSNumber)?.doubleValue else { return nil }
            return CommunityPlace(id: id, name: name,
                                  category: row["category"] as? String ?? "",
                                  note: row["note"] as? String ?? "",
                                  latitude: lat, longitude: lon,
                                  createdAt: ISOTime.parse(row["created_at"]) ?? Date())
        }
        let reports = await reportRows.compactMap { row -> RoadReport? in
            guard let id = row["id"] as? String, let kind = row["kind"] as? String,
                  let lat = (row["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (row["longitude"] as? NSNumber)?.doubleValue else { return nil }
            return RoadReport(id: id, kind: kind, latitude: lat, longitude: lon,
                              createdAt: ISOTime.parse(row["created_at"]) ?? Date(),
                              confirmedAt: ISOTime.parse(row["confirmed_at"]) ?? ISOTime.parse(row["created_at"]) ?? Date())
        }
        remotePlaces = places
        remoteReports = reports.filter { Date().timeIntervalSince($0.confirmedAt) < 3 * 3600 }
    }

    static func uploadReport(_ report: RoadReport) async {
        guard Backend.isConfigured else { return }
        await Backend.insert(table: "road_reports", payload: [
            "id": report.id, "kind": report.kind,
            "latitude": report.latitude, "longitude": report.longitude,
            "device_id": Backend.deviceID,
            "created_at": ISOTime.string(report.createdAt),
            "confirmed_at": ISOTime.string(report.confirmedAt)
        ])
    }

    static func uploadPlace(_ place: CommunityPlace) async {
        guard Backend.isConfigured else { return }
        await Backend.insert(table: "local_places", payload: [
            "id": place.id, "name": place.name, "category": place.category,
            "note": place.note,
            "latitude": place.latitude, "longitude": place.longitude,
            "device_id": Backend.deviceID,
            "created_at": ISOTime.string(place.createdAt)
        ])
    }
}
