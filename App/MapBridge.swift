import SwiftUI
import MapKit
import UIKit

/// Apple Maps styles available through the public MapKit configuration API.
enum MapStyleKind: String, CaseIterable {
    case standard, muted, satellite, hybrid, dark

    var label: String {
        switch self {
        case .standard: return "قياسية".loc
        case .muted: return "هادئة".loc
        case .satellite: return "قمر صناعي".loc
        case .hybrid: return "هجينة".loc
        case .dark: return "ليلية".loc
        }
    }

    var isNightStyle: Bool { self == .dark }
}

enum MapHealth {
    static func log(_ event: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        let line = "\(df.string(from: Date())) \(event)"
        let old = UserDefaults.standard.string(forKey: "wijhati.health.log") ?? ""
        let parts = (line + " ؛ " + old).split(separator: "؛").prefix(3)
        UserDefaults.standard.set(parts.joined(separator: " ؛ "), forKey: "wijhati.health.log")
    }
}

struct BearingRequest: Equatable {
    var degrees: Double
    var id: UUID = UUID()
    static func == (lhs: BearingRequest, rhs: BearingRequest) -> Bool { lhs.id == rhs.id }
}

struct CenterRequest: Equatable {
    var coordinate: CLLocationCoordinate2D
    var zoom: Double
    var id: UUID = UUID()
    static func == (lhs: CenterRequest, rhs: CenterRequest) -> Bool { lhs.id == rhs.id }
}

struct MapCameraSnapshot {
    var center: CLLocationCoordinate2D
    var zoom: Double
    var distance: CLLocationDistance
    var heading: Double
    var pitch: CGFloat

    init(map: MKMapView) {
        let camera = map.camera
        center = camera.centerCoordinate
        distance = camera.centerCoordinateDistance
        zoom = MapBridge.zoomLevel(forDistance: distance, latitude: center.latitude,
                                   mapWidth: map.bounds.width)
        heading = camera.heading
        pitch = camera.pitch
    }
}

struct MapBridge: UIViewRepresentable {
    var pins: [Place]
    var routeCoords: [CLLocationCoordinate2D]
    var altRouteCoords: [CLLocationCoordinate2D]
    var tripCoords: [CLLocationCoordinate2D]
    var routeRevision: String
    var styleKind: MapStyleKind
    var show3D: Bool
    var followUser: Bool
    var isAppActive: Bool
    var userLocation: CLLocationCoordinate2D?
    var centerRequest: CenterRequest?
    var bearingRequest: BearingRequest?
    var northReset: Int
    var onSelectPin: (Place) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onMapTap: () -> Void
    var restoreCamera: MapCameraSnapshot?
    var onCameraRestoreConsumed: () -> Void
    var onRecoveryExhausted: (MapStyleKind, MapCameraSnapshot) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = isAppActive
        map.backgroundColor = styleKind.isNightStyle ? .black : UIColor.systemBackground
        map.isOpaque = false

        let initialCenter = userLocation ?? CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661)
        let initialZoom: Double = userLocation == nil ? 11 : (show3D ? 16 : 13)
        let initialPitch: CGFloat = userLocation != nil && show3D ? 52 : 0
        if let restoreCamera {
            let distance = restoreCamera.distance > 0
                ? restoreCamera.distance
                : Self.cameraDistance(forZoom: restoreCamera.zoom, latitude: restoreCamera.center.latitude,
                                      mapWidth: map.bounds.width)
            map.setCamera(MKMapCamera(lookingAtCenter: restoreCamera.center,
                                      fromDistance: distance,
                                      pitch: restoreCamera.pitch,
                                      heading: restoreCamera.heading), animated: false)
        } else {
            map.setCamera(Self.camera(center: initialCenter, zoom: initialZoom,
                                      pitch: initialPitch, heading: 0, in: map), animated: false)
        }
        context.coordinator.map = map
        context.coordinator.applyConfiguration(to: map, force: true)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        map.addGestureRecognizer(longPress)

        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.appEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(context.coordinator,
            selector: #selector(Coordinator.appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)

        if restoreCamera != nil {
            DispatchQueue.main.async { context.coordinator.parent.onCameraRestoreConsumed() }
        }
        return map
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.cancelResumeFallback()
        NotificationCenter.default.removeObserver(coordinator)
        uiView.delegate = nil
        coordinator.map = nil
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        map.backgroundColor = styleKind.isNightStyle ? .black : UIColor.systemBackground
        context.coordinator.applyConfiguration(to: map)
        context.coordinator.setMapActive(isAppActive)

        if map.showsUserLocation != isAppActive { map.showsUserLocation = isAppActive }
        if let location = userLocation, !context.coordinator.didCenterOnUser {
            context.coordinator.didCenterOnUser = true
            let pitch: CGFloat = show3D ? 52 : 0
            map.setCamera(Self.camera(center: location, zoom: show3D ? 16 : 13,
                                      pitch: pitch, heading: 0, in: map), animated: false)
        }

        if isAppActive && followUser {
            if map.userTrackingMode != .followWithHeading { map.userTrackingMode = .followWithHeading }
        } else if map.userTrackingMode != .none {
            map.userTrackingMode = .none
        }

        if let request = bearingRequest, context.coordinator.lastBearingID != request.id {
            context.coordinator.lastBearingID = request.id
            var camera = map.camera
            camera.heading = request.degrees
            map.setCamera(camera, animated: true)
        }
        if let request = centerRequest, context.coordinator.lastCenterID != request.id {
            context.coordinator.lastCenterID = request.id
            var camera = Self.camera(center: request.coordinate, zoom: request.zoom,
                                     pitch: map.camera.pitch, heading: map.camera.heading, in: map)
            camera.pitch = map.camera.pitch
            map.setCamera(camera, animated: true)
        }
        if context.coordinator.lastNorthReset != northReset {
            context.coordinator.lastNorthReset = northReset
            var camera = map.camera
            camera.heading = 0
            camera.pitch = 0
            map.setCamera(camera, animated: true)
        }

        context.coordinator.refreshAnnotations()
        context.coordinator.refreshOverlays()
    }

    static func camera(center: CLLocationCoordinate2D, zoom: Double, pitch: CGFloat,
                       heading: Double, in map: MKMapView) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: center,
                    fromDistance: cameraDistance(forZoom: zoom, latitude: center.latitude,
                                                 mapWidth: map.bounds.width),
                    pitch: pitch, heading: heading)
    }

    /// Approximate MapKit camera distance for the familiar 0...22 zoom scale.
    /// The width-based conversion keeps recenter controls consistent across devices.
    static func cameraDistance(forZoom zoom: Double, latitude: CLLocationDegrees,
                               mapWidth: CGFloat) -> CLLocationDistance {
        let z = min(21.5, max(0, zoom))
        let width = max(320, Double(mapWidth))
        let mapPointsPerPixel = MKMapSize.world.width / (256 * pow(2, z))
        let metersAcross = MKMetersPerMapPointAtLatitude(latitude) * mapPointsPerPixel * width
        return min(50_000_000, max(200, metersAcross * 1.2))
    }

    static func zoomLevel(forDistance distance: CLLocationDistance, latitude: CLLocationDegrees,
                          mapWidth: CGFloat) -> Double {
        let width = max(320, Double(mapWidth))
        let baseMetersAcross = MKMetersPerMapPointAtLatitude(latitude)
            * MKMapSize.world.width / 256 * width
        guard distance > 0, baseMetersAcross > 0 else { return 11 }
        return min(21.5, max(0, log2((baseMetersAcross * 1.2) / distance)))
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapBridge
        weak var map: MKMapView?
        private var placeByAnnotationID: [ObjectIdentifier: Place] = [:]
        private var shownPins: [Place] = []
        private var overlayKinds: [ObjectIdentifier: String] = [:]
        private var lastOverlaySignature = ""
        private var appliedConfigurationKey = ""
        private var lastAutoTiltZoom: Double?
        var lastCenterID: UUID?
        var lastBearingID: UUID?
        var lastNorthReset: Int = 0
        var didCenterOnUser = false
        private var didEnterBackground = false
        private var resumeScheduled = false
        private var lifecycleGeneration = 0
        private var resumeFallback: DispatchWorkItem?

        init(_ parent: MapBridge) { self.parent = parent }

        func applyConfiguration(to map: MKMapView, force: Bool = false) {
            let key = "\(parent.styleKind.rawValue)-\(parent.show3D)"
            guard force || key != appliedConfigurationKey else { return }
            let oldKey = appliedConfigurationKey
            appliedConfigurationKey = key
            map.overrideUserInterfaceStyle = parent.styleKind.isNightStyle ? .dark : .unspecified
            let elevation: MKMapConfiguration.ElevationStyle = parent.show3D ? .realistic : .flat
            switch parent.styleKind {
            case .satellite:
                map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: elevation)
            case .hybrid:
                map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: elevation)
            case .standard, .muted, .dark:
                let emphasis: MKStandardMapConfiguration.EmphasisStyle = parent.styleKind == .muted ? .muted : .default
                map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: elevation,
                                                                         emphasisStyle: emphasis)
            }
            if !oldKey.isEmpty, oldKey != key {
                var camera = map.camera
                if !parent.show3D {
                    camera.pitch = 0
                } else if !oldKey.hasSuffix("true"), Self.zoom(for: map) >= 13 {
                    camera.pitch = max(camera.pitch, 52)
                }
                map.setCamera(camera, animated: true)
            }
        }

        private static func zoom(for map: MKMapView) -> Double {
            MapBridge.zoomLevel(forDistance: map.camera.centerCoordinateDistance,
                                latitude: map.camera.centerCoordinate.latitude,
                                mapWidth: map.bounds.width)
        }

        func setMapActive(_ active: Bool) {
            if active {
                if didEnterBackground { appBecameActive() }
            } else {
                lifecycleGeneration += 1
                didEnterBackground = true
                resumeScheduled = false
                cancelResumeFallback()
            }
        }

        private func cancelResumeFallback() {
            resumeFallback?.cancel()
            resumeFallback = nil
        }

        @objc func appEnteredBackground() {
            lifecycleGeneration += 1
            didEnterBackground = true
            resumeScheduled = false
            cancelResumeFallback()
        }

        @objc func appWillEnterForeground() {
            didEnterBackground = true
        }

        @objc func appBecameActive() {
            guard didEnterBackground, !resumeScheduled, let map else { return }
            resumeScheduled = true
            let generation = lifecycleGeneration
            MapHealth.log("رجوع للواجهة: استعادة إطار خريطة Apple")
            map.setNeedsLayout()
            map.layoutIfNeeded()
            map.setNeedsDisplay()
            let fallback = DispatchWorkItem { [weak self, weak map] in
                guard let self, self.lifecycleGeneration == generation,
                      self.resumeScheduled, self.didEnterBackground,
                      UIApplication.shared.applicationState == .active,
                      let map else { return }
                self.resumeFallback = nil
                self.resumeScheduled = false
                MapHealth.log("رجوع للواجهة: إعادة إنشاء سطح خريطة Apple")
                self.parent.onRecoveryExhausted(self.parent.styleKind, MapCameraSnapshot(map: map))
            }
            resumeFallback = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: fallback)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard resumeScheduled, didEnterBackground,
                  UIApplication.shared.applicationState == .active else { return }
            cancelResumeFallback()
            resumeScheduled = false
            didEnterBackground = false
            MapHealth.log(fullyRendered
                ? "رجوع للواجهة: خريطة Apple اكتمل رسمها"
                : "رجوع للواجهة: خريطة Apple رسمت إطارًا جزئيًا")
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onMapTap()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            parent.onLongPress(map.convert(gesture.location(in: map), toCoordinateFrom: map))
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let zoom = Self.zoom(for: mapView)
            let changed = lastAutoTiltZoom.map { abs($0 - zoom) > 0.12 } ?? false
            lastAutoTiltZoom = zoom
            guard changed, parent.show3D, zoom >= 15, mapView.camera.pitch < 50 else { return }
            var camera = mapView.camera
            camera.pitch = 52
            mapView.setCamera(camera, animated: true)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation,
                  let place = placeByAnnotationID[ObjectIdentifier(annotation as AnyObject)] else { return }
            parent.onSelectPin(place)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation),
                  let place = placeByAnnotationID[ObjectIdentifier(annotation as AnyObject)] else { return nil }
            let isCommunity = place.id.hasPrefix("community-")
            let isOfficial = place.id.hasPrefix("official-")
            let reuseID = isCommunity ? "wijhati-community-pin" : (isOfficial ? "wijhati-official-pin" : "wijhati-pin")
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            let image = isCommunity ? Self.communityPinImage() : (isOfficial ? Self.officialPinImage() : Self.pinImage())
            view.annotation = annotation
            view.image = image
            view.centerOffset = CGPoint(x: 0, y: -image.size.height / 2)
            view.canShowCallout = false
            view.displayPriority = .required
            return view
        }

        static func officialPinImage() -> UIImage {
            let size = CGSize(width: 34, height: 34)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30))
                UIColor(red: 0.85, green: 0.62, blue: 0.08, alpha: 1).setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 6, height: 6)).fill()
            }
        }

        static func communityPinImage() -> UIImage {
            let size = CGSize(width: 34, height: 34)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30))
                UIColor.systemPurple.setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 6, height: 6)).fill()
            }
        }

        static func pinImage() -> UIImage {
            let size = CGSize(width: 34, height: 44)
            return UIGraphicsImageRenderer(size: size).image { context in
                let cg = context.cgContext
                let drop = UIBezierPath()
                drop.move(to: CGPoint(x: 17, y: 43))
                drop.addCurve(to: CGPoint(x: 2, y: 15), controlPoint1: CGPoint(x: 8, y: 32), controlPoint2: CGPoint(x: 2, y: 24))
                drop.addArc(withCenter: CGPoint(x: 17, y: 15), radius: 13, startAngle: .pi, endAngle: 0, clockwise: true)
                drop.addCurve(to: CGPoint(x: 17, y: 43), controlPoint1: CGPoint(x: 32, y: 24), controlPoint2: CGPoint(x: 26, y: 32))
                drop.close()
                UIColor.systemBlue.setFill()
                drop.fill()
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: 11, y: 9, width: 12, height: 12))
            }
        }

        func refreshAnnotations() {
            guard let map, parent.pins != shownPins else { return }
            shownPins = parent.pins
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            placeByAnnotationID.removeAll(keepingCapacity: true)
            let annotations = parent.pins.map { place -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.coordinate = place.coordinate
                annotation.title = place.name
                placeByAnnotationID[ObjectIdentifier(annotation)] = place
                return annotation
            }
            if !annotations.isEmpty { map.addAnnotations(annotations) }
        }

        func refreshOverlays() {
            guard let map else { return }
            let signature = "\(parent.routeRevision)-\(parent.routeCoords.count)-\(parent.altRouteCoords.count)-\(parent.tripCoords.count)-\(parent.show3D)-\(parent.styleKind.rawValue)-\(parent.routeCoords.first?.latitude ?? 0)-\(parent.routeCoords.last?.longitude ?? 0)-\(parent.altRouteCoords.first?.latitude ?? 0)-\(parent.tripCoords.last?.longitude ?? 0)"
            guard signature != lastOverlaySignature else { return }
            lastOverlaySignature = signature
            map.removeOverlays(map.overlays)
            overlayKinds.removeAll(keepingCapacity: true)
            var overlays: [MKPolyline] = []
            func append(_ coordinates: [CLLocationCoordinate2D], kind: String) {
                guard coordinates.count >= 2 else { return }
                let line = coordinates.withUnsafeBufferPointer { buffer -> MKPolyline? in
                    guard let baseAddress = buffer.baseAddress else { return nil }
                    return MKPolyline(coordinates: baseAddress, count: buffer.count)
                }
                guard let line else { return }
                overlayKinds[ObjectIdentifier(line)] = kind
                overlays.append(line)
            }
            append(parent.altRouteCoords, kind: "alt-route")
            append(parent.tripCoords, kind: "trip")
            if parent.routeCoords.count >= 2 {
                append(parent.routeCoords, kind: "route-halo")
                append(parent.routeCoords, kind: "route")
            }
            if !overlays.isEmpty { map.addOverlays(overlays, level: .aboveRoads) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let kind = overlayKinds[ObjectIdentifier(line)] ?? "route"
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            switch kind {
            case "route-halo":
                renderer.strokeColor = parent.styleKind.isNightStyle
                    ? UIColor(red: 1, green: 0.66, blue: 0.28, alpha: 0.92)
                    : UIColor(red: 1, green: 0.91, blue: 0.70, alpha: 0.96)
                renderer.lineWidth = 11
            case "route":
                renderer.strokeColor = parent.styleKind.isNightStyle
                    ? UIColor(red: 1, green: 0.72, blue: 0.34, alpha: 1)
                    : UIColor(red: 0.96, green: 0.39, blue: 0.16, alpha: 1)
                renderer.lineWidth = 6
            case "alt-route":
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.7)
                renderer.lineWidth = 4
            case "trip":
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.95)
                renderer.lineWidth = 5
            default:
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 5
            }
            return renderer
        }
    }
}
