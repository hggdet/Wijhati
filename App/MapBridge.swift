import SwiftUI
import MapLibre

enum MapStyleKind: String, CaseIterable {
    case standard, bright, cartoon, satellite
    var label: String {
        switch self {
        case .standard: return "قياسية"
        case .bright: return "فاتحة"
        case .cartoon: return "كرتونية 🎨"
        case .satellite: return "قمر صناعي"
        }
    }
    var url: URL? {
        switch self {
        case .standard: return URL(string: "https://openfreemap.org/styles/liberty")
        case .bright: return URL(string: "https://openfreemap.org/styles/positron")
        case .cartoon: return Bundle.main.url(forResource: "cartoon-style", withExtension: "json")
        case .satellite: return Bundle.main.url(forResource: "satellite-style", withExtension: "json")
        }
    }
    var isRaster: Bool { self == .cartoon || self == .satellite }
}

struct CenterRequest: Equatable {
    var coordinate: CLLocationCoordinate2D
    var zoom: Double
    var id: UUID = UUID()
    static func == (lhs: CenterRequest, rhs: CenterRequest) -> Bool { lhs.id == rhs.id }
}

struct MapBridge: UIViewRepresentable {
    var pins: [Place]
    var routeCoords: [CLLocationCoordinate2D]
    var altRouteCoords: [CLLocationCoordinate2D]
    var tripCoords: [CLLocationCoordinate2D]
    var isoPolygon: [CLLocationCoordinate2D]
    var styleKind: MapStyleKind
    var show3D: Bool
    var radarTimestamp: Int?
    var followUser: Bool
    var centerRequest: CenterRequest?
    var onSelectPin: (Place) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleKind.url ?? MapStyleKind.standard.url)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.compassView.isHidden = true
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.setCenter(CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661), zoomLevel: 11, animated: false)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.currentStyle != styleKind {
            context.coordinator.currentStyle = styleKind
            context.coordinator.styleReady = false
            map.styleURL = styleKind.url ?? MapStyleKind.standard.url
        }
        if followUser {
            if map.userTrackingMode != .followWithHeading { map.userTrackingMode = .followWithHeading }
        } else if map.userTrackingMode != .none {
            map.userTrackingMode = .none
        }
        if let req = centerRequest, context.coordinator.lastCenterID != req.id {
            context.coordinator.lastCenterID = req.id
            map.setCenter(req.coordinate, zoomLevel: req.zoom, animated: true)
        }
        context.coordinator.refreshAnnotations()
        if context.coordinator.styleReady, let style = map.style {
            context.coordinator.refreshLayers(style: style)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapBridge
        weak var map: MLNMapView?
        var currentStyle: MapStyleKind
        var styleReady = false
        var lastCenterID: UUID?
        private var shownPinIDs: [String] = []
        private var lastRadarTS: Int?

        init(_ parent: MapBridge) {
            self.parent = parent
            self.currentStyle = parent.styleKind
        }

        // MARK: Delegate
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            refreshLayers(style: style)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { false }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let ann = annotation as? MLNPointAnnotation else { return }
            if let place = parent.pins.first(where: {
                abs($0.latitude - ann.coordinate.latitude) < 0.00005 &&
                abs($0.longitude - ann.coordinate.longitude) < 0.00005
            }) {
                parent.onSelectPin(place)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            let id = "wijhati-pin"
            if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: id) { return existing }
            return MLNAnnotationImage(image: Self.pinImage(), reuseIdentifier: id)
        }

        static func pinImage() -> UIImage {
            let size = CGSize(width: 34, height: 44)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let cg = ctx.cgContext
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

        // MARK: Annotations
        func refreshAnnotations() {
            guard let map else { return }
            let ids = parent.pins.map { $0.id }
            if ids == shownPinIDs { return }
            shownPinIDs = ids
            if let existing = map.annotations { map.removeAnnotations(existing) }
            let anns = parent.pins.map { p -> MLNPointAnnotation in
                let a = MLNPointAnnotation()
                a.coordinate = p.coordinate
                a.title = p.name
                return a
            }
            if !anns.isEmpty { map.addAnnotations(anns) }
        }

        // MARK: Layers
        func refreshLayers(style: MLNStyle) {
            updateLine(style: style, id: "alt-route", coords: parent.altRouteCoords,
                       color: .gray, width: 4, opacity: 0.6)
            updateLine(style: style, id: "route", coords: parent.routeCoords,
                       color: .systemBlue, width: 6, opacity: 1.0)
            updateLine(style: style, id: "trip", coords: parent.tripCoords,
                       color: .systemOrange, width: 5, opacity: 0.95)
            updateIsochrone(style: style)
            updateBuildings(style: style)
            updateRadar(style: style)
        }

        private func geoJSONLine(_ coords: [CLLocationCoordinate2D]) -> MLNShape? {
            let obj: [String: Any] = ["type": "LineString",
                "coordinates": coords.map { [$0.longitude, $0.latitude] }]
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
        }

        private func updateLine(style: MLNStyle, id: String, coords: [CLLocationCoordinate2D],
                                color: UIColor, width: Double, opacity: Double) {
            let sourceID = "\(id)-source"
            if coords.count >= 2, let shape = geoJSONLine(coords) {
                if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                    source.shape = shape
                } else {
                    let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
                    style.addSource(source)
                    let layer = MLNLineStyleLayer(identifier: "\(id)-layer", source: source)
                    layer.lineColor = NSExpression(forConstantValue: color)
                    layer.lineWidth = NSExpression(forConstantValue: width)
                    layer.lineOpacity = NSExpression(forConstantValue: opacity)
                    layer.lineCap = NSExpression(forConstantValue: "round")
                    layer.lineJoin = NSExpression(forConstantValue: "round")
                    style.addLayer(layer)
                }
            } else {
                if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                    source.shape = nil
                }
            }
        }

        private func updateIsochrone(style: MLNStyle) {
            let sourceID = "iso-source"
            let coords = parent.isoPolygon
            if coords.count >= 3 {
                let obj: [String: Any] = ["type": "Polygon",
                    "coordinates": [coords.map { [$0.longitude, $0.latitude] }]]
                if let data = try? JSONSerialization.data(withJSONObject: obj),
                   let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
                    if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                        source.shape = shape
                    } else {
                        let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
                        style.addSource(source)
                        let fill = MLNFillStyleLayer(identifier: "iso-fill", source: source)
                        fill.fillColor = NSExpression(forConstantValue: UIColor.systemTeal)
                        fill.fillOpacity = NSExpression(forConstantValue: 0.22)
                        style.addLayer(fill)
                        let line = MLNLineStyleLayer(identifier: "iso-line", source: source)
                        line.lineColor = NSExpression(forConstantValue: UIColor.systemTeal)
                        line.lineWidth = NSExpression(forConstantValue: 2)
                        style.addLayer(line)
                    }
                }
            } else if let source = style.source(withIdentifier: sourceID) as? MLNShapeSource {
                source.shape = nil
            }
        }

        private func updateBuildings(style: MLNStyle) {
            let layerID = "buildings-3d"
            if parent.show3D && !currentStyle.isRaster {
                if style.layer(withIdentifier: layerID) == nil,
                   let vector = style.source(withIdentifier: "openmaptiles") as? MLNVectorTileSource {
                    let layer = MLNFillExtrusionStyleLayer(identifier: layerID, source: vector)
                    layer.sourceLayerIdentifier = "building"
                    layer.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
                    layer.fillExtrusionBase = NSExpression(forKeyPath: "render_min_height")
                    layer.fillExtrusionColor = NSExpression(forConstantValue: UIColor(red: 0.62, green: 0.68, blue: 0.78, alpha: 1))
                    layer.fillExtrusionOpacity = NSExpression(forConstantValue: 0.85)
                    layer.minimumZoomLevel = 15
                    style.addLayer(layer)
                }
                if let map, map.camera.pitch < 40 { var cam = map.camera; cam.pitch = 55; map.setCamera(cam, animated: true) }
            } else {
                if let layer = style.layer(withIdentifier: layerID) { style.removeLayer(layer) }
                if parent.show3D == false, let map, map.camera.pitch > 1 { var cam = map.camera; cam.pitch = 0; map.setCamera(cam, animated: true) }
            }
        }

        private func updateRadar(style: MLNStyle) {
            let sourceID = "rain-source"
            if let ts = parent.radarTimestamp {
                if lastRadarTS != ts {
                    lastRadarTS = ts
                    if let layer = style.layer(withIdentifier: "rain-layer") { style.removeLayer(layer) }
                    if let source = style.source(withIdentifier: sourceID) { style.removeSource(source) }
                    let source = MLNRasterTileSource(identifier: sourceID,
                        tileURLTemplates: ["https://tilecache.rainviewer.com/v2/radar/\(ts)/{z}/{x}/{y}/256/2/1_1.png"],
                        options: [.minimumZoomLevel: 0, .maximumZoomLevel: 12, .tileSize: 256])
                    style.addSource(source)
                    let layer = MLNRasterStyleLayer(identifier: "rain-layer", source: source)
                    layer.rasterOpacity = NSExpression(forConstantValue: 0.55)
                    style.addLayer(layer)
                }
            } else {
                lastRadarTS = nil
                if let layer = style.layer(withIdentifier: "rain-layer") { style.removeLayer(layer) }
                if let source = style.source(withIdentifier: sourceID) { style.removeSource(source) }
            }
        }
    }
}
