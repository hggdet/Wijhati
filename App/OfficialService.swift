import Foundation
import CoreLocation

/// The official-places layer: government offices, hospitals, universities
/// and police stations as gold-badged pins. The dataset lives in two plain
/// text files hosted with the project (one line per point:
/// name|category|lat|lon); any institution can publish its own points by
/// updating those files — no app update needed. Cached locally after the
/// first fetch so the layer also works offline.
final class OfficialStore: ObservableObject {
    @Published var places: [Place] = [] {
        didSet { rebuildSearchIndex() }
    }
    private var normalizedIndex: [(place: Place, searchable: String)] = []

    private func rebuildSearchIndex() {
        normalizedIndex = places.map { place in
            let searchable = [place.name, place.address, place.kind ?? ""].joined(separator: " ")
            return (place, GeoService.normalizeArabic(searchable))
        }
    }

    /// Instant local matches over the whole official dataset (already
    /// in memory, so search works offline too).
    func matches(_ normalizedQuery: String) -> [Place] {
        normalizedIndex.filter { $0.searchable.contains(normalizedQuery) }.map { $0.place }
    }

    private let cacheKey = "wijhati.officialPlaces.v2"
    private let remoteURLs = [
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-a.csv")!,
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-b.csv")!,
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-c.csv")!,
    ]

    init() {
        if let text = UserDefaults.standard.string(forKey: cacheKey) {
            places = Self.decode(text)
            rebuildSearchIndex()
        }
        Task { await refresh() }
    }

    func refresh() async {
        var combined: [Place] = []
        var rawParts: [String] = []
        for url in remoteURLs {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Wijhati/1.43 iOS (id9871456@gmail.com)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { continue }
            rawParts.append(text)
            combined += Self.decode(text)
        }
        guard !combined.isEmpty else { return }
        UserDefaults.standard.set(rawParts.joined(separator: "\n"), forKey: cacheKey)
        await MainActor.run { self.places = combined }
    }

    private static func decode(_ text: String) -> [Place] {
        var seen = Set<String>()
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "|", omittingEmptySubsequences: false)
            guard f.count == 4, let lat = Double(f[2]), let lon = Double(f[3]),
                  lat.isFinite, lon.isFinite,
                  (-90.0...90.0).contains(lat), (-180.0...180.0).contains(lon) else { return nil }
            let name = String(f[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let category = String(f[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, IraqBoundary.contains(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return nil }
            let id = "official-\(Int((lat * 100_000).rounded()))-\(Int((lon * 100_000).rounded()))-\(GeoService.normalizeArabic(name))"
            guard seen.insert(id).inserted else { return nil }
            return Place(id: id,
                         name: name,
                         address: category.isEmpty ? "نقطة رسمية" : "نقطة رسمية — \(category)",
                         latitude: lat, longitude: lon, kind: category.isEmpty ? nil : category)
        }
    }
}
