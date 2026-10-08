import Foundation
import MapKit
import Combine

final class SearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var completions: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.completions = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.completions = []
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> PlaceResult? {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            if let item = response.mapItems.first {
                return PlaceResult(mapItem: item)
            }
        } catch {
            return nil
        }
        return nil
    }

    func searchText(_ text: String, near region: MKCoordinateRegion?) async -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.map { PlaceResult(mapItem: $0) }
        } catch {
            return []
        }
    }

    func nearby(categoryQuery: String, near coordinate: CLLocationCoordinate2D, radius: Double = 3000) async -> [PlaceResult] {
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: radius * 2,
                                        longitudinalMeters: radius * 2)
        return await searchText(categoryQuery, near: region)
    }
}
