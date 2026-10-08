import SwiftUI
import MapLibre

enum MapStyleKind: String, CaseIterable {
    case standard, bright, dark, cartoon, satellite
    var label: String {
        switch self {
        case .standard: return "قياسية"
        case .bright: return "فاتحة"
        case .dark: return "ليلي 🌙"
        case .cartoon: return "كرتونية 🎨"
        case .satellite: return "قمر صناعي"
        }
    }
    var url: URL? {
        switch self {
        case .standard: return URL(string: "https://tiles.versatiles.org/styles/colorful/style.json")
        case .bright: return URL(string: "https://tiles.versatiles.org/styles/graybeard/style.json")
        case .dark: return URL(string: "https://tiles.versatiles.org/styles/eclipse/style.json")
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
    var userLocation: CLLocationCoordinate2D?
    var centerRequest: CenterRequest?
    var northReset: Int
    var onSelectPin: (Place) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleKind.url ?? MapStyleKind.standard.url)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.prefetchesTiles = true
        map.compassView.isHidden = true
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.setCenter(CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661), zoomLevel: 11, animated: false)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        map.addGestureRecognizer(longPress)
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
        if let ul = userLocation, !context.coordinator.didCenterOnUser {
            context.coordinator.didCenterOnUser = true
            map.setCenter(ul, zoomLevel: 13, animated: false)
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
        if context.coordinator.lastNorthReset != northReset {
            context.coordinator.lastNorthReset = northReset
            var cam = map.camera
            cam.heading = 0
            cam.pitch = 0
            map.setCamera(cam, animated: true)
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
        var didCenterOnUser = false
        var lastLayerSignature = "" 
        var lastNorthReset: Int = 0

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: MLNMapView, didFailLoading style: MLNStyle, withError error: Error) {
            if currentStyle != .standard {
                currentStyle = .standard
                styleReady = false
                mapView.styleURL = MapStyleKind.standard.url
            }
        }
        private var shownPinIDs: [String] = []
        private var lastRadarTS: Int?

        init(_ parent: MapBridge) {
            self.parent = parent
            self.currentStyle = parent.styleKind
        }

        // MARK: Delegate
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            lastLayerSignature = ""
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
            let isReport = parent.pins.contains {
                $0.id.hasPrefix("report-") &&
                abs($0.latitude - annotation.coordinate.latitude) < 0.00005 &&
                abs($0.longitude - annotation.coordinate.longitude) < 0.00005
            }
            let id = isReport ? "wijhati-report-pin" : "wijhati-pin"
            if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: id) { return existing }
            return MLNAnnotationImage(image: isReport ? Self.reportPinImage() : Self.pinImage(), reuseIdentifier: id)
        }

        static func reportPinImage() -> UIImage {
            let size = CGSize(width: 36, height: 36)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 32, height: 32))
                UIColor.systemOrange.setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .black),
                    .foregroundColor: UIColor.white
                ]
                let text = "!" as NSString
                let ts = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
            }
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
            let signature = "\(parent.routeCoords.count)-\(parent.altRouteCoords.count)-\(parent.tripCoords.count)-\(parent.isoPolygon.count)-\(parent.radarTimestamp ?? -1)-\(parent.show3D)-\(currentStyle.rawValue)-\(parent.routeCoords.last?.latitude ?? 0)-\(parent.isoPolygon.last?.longitude ?? 0)"
            if signature == lastLayerSignature { return }
            lastLayerSignature = signature
            updatePOILabels(style: style)
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

        private func updatePOILabels(style: MLNStyle) {
            let layerID = "wijhati-poi-labels"
            guard !currentStyle.isRaster, style.layer(withIdentifier: layerID) == nil,
                  let vector = style.source(withIdentifier: "versatiles-shortbread") as? MLNVectorTileSource
            else { return }
            let layer = MLNSymbolStyleLayer(identifier: layerID, source: vector)
            layer.sourceLayerIdentifier = "pois"
            layer.predicate = NSPredicate(format: "name != nil")
            layer.text = NSExpression(forKeyPath: "name")
            layer.textFontNames = NSExpression(forConstantValue: ["noto_sans_regular"])
            layer.textFontSize = NSExpression(forConstantValue: 12)
            layer.textColor = NSExpression(forConstantValue: UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1))
            layer.textHaloColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.9))
            layer.textHaloWidth = NSExpression(forConstantValue: 1.4)
            layer.minimumZoomLevel = 15
            layer.maximumZoomLevel = 18
            style.addLayer(layer)
        }

        private func updateBuildings(style: MLNStyle) {
            let layerID = "buildings-3d"
            if parent.show3D && !currentStyle.isRaster {
                let vector = (style.source(withIdentifier: "openmaptiles") as? MLNVectorTileSource)
                    ?? (style.source(withIdentifier: "versatiles-shortbread") as? MLNVectorTileSource)
                let isShortbread = style.source(withIdentifier: "versatiles-shortbread") != nil
                if style.layer(withIdentifier: layerID) == nil, let vector {
                    let layer = MLNFillExtrusionStyleLayer(identifier: layerID, source: vector)
                    layer.sourceLayerIdentifier = isShortbread ? "buildings" : "building"
                    layer.fillExtrusionHeight = NSExpression(forKeyPath: isShortbread ? "height" : "render_height")
                    layer.fillExtrusionBase = NSExpression(forKeyPath: isShortbread ? "min_height" : "render_min_height")
                    layer.fillExtrusionColor = NSExpression(forConstantValue: UIColor(red: 0.62, green: 0.68, blue: 0.78, alpha: 1))
                    layer.fillExtrusionOpacity = NSExpression(forConstantValue: 0.85)
                    layer.minimumZoomLevel = 15
                    style.addLayer(layer)
                }
                if let map {
                    if map.zoomLevel < 15.5 { map.setCenter(map.centerCoordinate, zoomLevel: 15.5, animated: true) }
                    if map.camera.pitch < 25 { var cam = map.camera; cam.pitch = 30; map.setCamera(cam, animated: true) }
                }
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
