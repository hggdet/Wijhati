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
    private var appIsActive = true
    private var navigationActive = false
    private var cameraNavigationActive = false
    private var locationUpdatesActive = false
    private var headingUpdatesActive = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 15
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        refreshActivityProfile()
    }

    func setAppActive(_ active: Bool) {
        guard appIsActive != active else { return }
        appIsActive = active
        refreshActivityProfile()
    }

    func setNavigationActive(_ active: Bool) {
        guard navigationActive != active else { return }
        navigationActive = active
        refreshActivityProfile()
    }

    func setCameraNavigationActive(_ active: Bool) {
        guard cameraNavigationActive != active else { return }
        cameraNavigationActive = active
        refreshActivityProfile()
    }

    private func refreshActivityProfile() {
        let status = manager.authorizationStatus
        if authorization != status { authorization = status }
        let isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways

        guard isAuthorized else {
            stopLocationUpdatesIfNeeded()
            stopHeadingUpdatesIfNeeded()
            return
        }

        let highAccuracyNeeded = navigationActive || recording || (cameraNavigationActive && appIsActive)
        let shouldRunLocation = appIsActive || navigationActive || recording

        if shouldRunLocation {
            manager.desiredAccuracy = highAccuracyNeeded
                ? kCLLocationAccuracyBestForNavigation
                : kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = highAccuracyNeeded ? 7 : 15
            manager.activityType = navigationActive || cameraNavigationActive
                ? .otherNavigation
                : (recording ? .fitness : .other)
            manager.pausesLocationUpdatesAutomatically = !appIsActive && !highAccuracyNeeded
            if !locationUpdatesActive {
                manager.startUpdatingLocation()
                locationUpdatesActive = true
            }
        } else {
            stopLocationUpdatesIfNeeded()
        }

        if cameraNavigationActive && appIsActive {
            manager.headingFilter = 5
            if !headingUpdatesActive {
                manager.startUpdatingHeading()
                headingUpdatesActive = true
            }
        } else {
            stopHeadingUpdatesIfNeeded()
        }
    }

    private func stopLocationUpdatesIfNeeded() {
        guard locationUpdatesActive else { return }
        manager.stopUpdatingLocation()
        locationUpdatesActive = false
    }

    private func stopHeadingUpdatesIfNeeded() {
        guard headingUpdatesActive else { return }
        manager.stopUpdatingHeading()
        headingUpdatesActive = false
    }

    func startRecording() {
        recordedPoints = []
        recordedDistance = 0
        lastRecorded = nil
        recordStartedAt = Date()
        recording = true
        refreshActivityProfile()
    }

    func stopRecording() -> Trip? {
        recording = false
        refreshActivityProfile()
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
        refreshActivityProfile()
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
