import Foundation
import CoreLocation
import Combine

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: Double = 0
    @Published var authorization: CLAuthorizationStatus = .notDetermined

    // Trip recording
    @Published var recording: Bool = false
    @Published var recordedPoints: [TripPoint] = []
    @Published var recordedDistance: Double = 0
    @Published var recordStartedAt: Date?
    private var lastRecorded: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func startRecording() {
        recordedPoints = []
        recordedDistance = 0
        lastRecorded = nil
        recordStartedAt = Date()
        recording = true
    }

    func stopRecording() -> Trip? {
        recording = false
        guard let start = recordStartedAt, recordedPoints.count >= 2 else {
            recordStartedAt = nil
            return nil
        }
        let trip = Trip(startedAt: start, endedAt: Date(),
                        distance: recordedDistance, points: recordedPoints)
        recordStartedAt = nil
        return trip
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        if recording {
            if let prev = lastRecorded {
                let d = last.distance(from: prev)
                if d >= 3 && d < 500 {
                    recordedDistance += d
                    recordedPoints.append(TripPoint(latitude: last.coordinate.latitude,
                                                    longitude: last.coordinate.longitude,
                                                    date: last.timestamp))
                    lastRecorded = last
                }
            } else {
                recordedPoints.append(TripPoint(latitude: last.coordinate.latitude,
                                                longitude: last.coordinate.longitude,
                                                date: last.timestamp))
                lastRecorded = last
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
