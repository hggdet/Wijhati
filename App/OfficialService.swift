import Foundation
import CoreLocation

/// The official-places layer: government offices, hospitals, universities
/// and police stations as gold-badged pins. The dataset lives in two plain
/// text files hosted with the project (one line per point:
/// name|category|lat|lon); any institution can publish its own points by
/// updating those files — no app update needed. Cached locally after the
/// first fetch so the layer also works offline.
final class OfficialStore: ObservableObject {
    @Published var places: [Place] = []

    private let cacheKey = "wijhati.officialPlaces.v2"
    private let remoteURLs = [
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-a.csv")!,
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-b.csv")!,
        URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/official-places-c.csv")!,
    ]

    init() {
        if let text = UserDefaults.standard.string(forKey: cacheKey) {
            places = Self.decode(text)
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
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let text = String(data: data, encoding: .utf8) else { continue }
            rawParts.append(text)
            combined += Self.decode(text)
        }
        guard !combined.isEmpty else { return }
        UserDefaults.standard.set(rawParts.joined(separator: "\n"), forKey: cacheKey)
        await MainActor.run { self.places = combined }
    }

    private static func decode(_ text: String) -> [Place] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "|", omittingEmptySubsequences: false)
            guard f.count == 4, let lat = Double(f[2]), let lon = Double(f[3]) else { return nil }
            let name = String(f[0])
            return Place(id: "official-\(lat),\(lon)-\(name)",
                         name: name,
                         address: "نقطة رسمية — \(f[1])",
                         latitude: lat, longitude: lon)
        }
    }
}
