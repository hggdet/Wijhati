import SwiftUI
import MapLibre
enum MapStyleKind: String, CaseIterable {
    case standard, pastel, bright, ofmBright, dark, ofmDark, cinematic, cartoon, satellite
    var label: String {
        switch self {
        case .standard: return "قياسية".loc
        case .pastel: return "باستيل ناعم".loc
        case .bright: return "فاتحة".loc
        case .ofmBright: return "زاهية".loc
        case .dark: return "ليلي".loc
        case .ofmDark: return "داكن".loc
        case .cinematic: return "ليلي سينمائي".loc
        case .cartoon: return "كرتونية".loc
        case .satellite: return "قمر صناعي".loc
        }
    }
    var url: URL? {
        switch self {
        case .standard: return Self.patchedStyleFile("liberty") ?? URL(string: "https://tiles.openfreemap.org/styles/liberty")
        case .pastel: return Self.patchedStyleFile("pastel") ?? URL(string: "https://tiles.openfreemap.org/styles/positron")
        case .bright: return Self.patchedStyleFile("positron") ?? URL(string: "https://tiles.openfreemap.org/styles/positron")
        case .ofmBright: return Self.patchedStyleFile("bright") ?? URL(string: "https://tiles.openfreemap.org/styles/bright")
        case .dark: return URL(string: "https://tiles.versatiles.org/styles/eclipse/style.json")
        case .ofmDark: return Self.patchedStyleFile("darkmiru") ?? URL(string: "https://tiles.openfreemap.org/styles/dark")
        case .cinematic: return Bundle.main.url(forResource: "cinematic-style", withExtension: "json")
            ?? URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/cinematic-style.json")
        case .cartoon: return URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/cartoon-style.json")
        case .satellite: return URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/hybrid-style.json")
        }
    }
    /// The unpatched remote equivalent of each style, used by the
    /// watchdog when the local patched copy will not load.
    var remoteURL: URL? {
        switch self {
        case .standard: return URL(string: "https://tiles.openfreemap.org/styles/liberty")
        case .pastel: return URL(string: "https://tiles.openfreemap.org/styles/positron")
        case .bright: return URL(string: "https://tiles.openfreemap.org/styles/positron")
        case .ofmBright: return URL(string: "https://tiles.openfreemap.org/styles/bright")
        case .dark: return URL(string: "https://tiles.versatiles.org/styles/eclipse/style.json")
        case .ofmDark: return URL(string: "https://tiles.openfreemap.org/styles/dark")
        case .cinematic: return URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/cinematic-style.json")
        case .cartoon: return URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/cartoon-style.json")
        case .satellite: return URL(string: "https://cdn.jsdelivr.net/gh/hggdet/Wijhati@main/App/hybrid-style.json")
        }
    }

    var isRaster: Bool { self == .cartoon || self == .satellite }

    // OpenFreeMap tiles carry proper Arabic names (name:ar / name).
    // We download the liberty/positron styles once, rewrite every
    // label to prefer the Arabic name, and cache the patched style
    // locally — labels then show pure Arabic instead of the stock
    // bilingual Latin+Arabic rendering.
    /// Directory for patched style files. Application Support, NOT
    /// Caches: iOS purges Caches under storage pressure — often while
    /// the app sits in the background — and a map whose style file
    /// vanished mid-flight can only render white.
    static var styleDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("wijhati-styles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var patchedMemo: [String: (Date, URL)] = [:]

    private static func patchedStyleFile(_ name: String) -> URL? {
        let file = styleDir.appendingPathComponent("wijhati-\(name)-ar3.json")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard let mtime else { patchedMemo[name] = nil; return nil }
        if let hit = patchedMemo[name], hit.0 == mtime { return hit.1 }
        guard let data = try? Data(contentsOf: file),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["layers"] != nil else {
            // Missing or corrupt cache: drop it so it regenerates cleanly
            // instead of feeding the map a broken style at launch.
            try? FileManager.default.removeItem(at: file)
            patchedMemo[name] = nil
            return nil
        }
        patchedMemo[name] = (mtime, file)
        return file
    }

    /// Label rule: prefer the primary `name` when it is written in Arabic
    /// script — in Iraq it is the most-reviewed value, while the secondary
    /// `name:ar` field is often degraded or plain wrong (one Baghdad
    /// ice-cream shop's name:ar literally reads "clinical_pathology").
    /// Prefer Arabic-script names in `name` (including Sorani), otherwise
    /// use a non-empty Arabic translation and finally the source name.
    private static func arabicNameExpression() -> [Any] {
        let name: [Any] = ["to-string", ["coalesce", ["get", "name"], ""]]
        let probes: [[Any]] = ["ا", "ب", "ت", "ج", "ح", "خ", "د", "ر", "ز", "س", "ش", "ص", "ط", "ع", "ف", "ق", "ك", "ل", "م", "ن", "ه", "و", "ي", "ة", "پ", "چ", "ڕ", "ڵ", "ۆ", "ێ", "گ", "ڤ", "ژ", "ە"]
            .map { ["in", $0, name] as [Any] }
        let hasArabicScript: [Any] = (["any"] as [Any]) + probes
        let nonEmptyArabicName: [Any] = ["case",
            ["==", ["coalesce", ["get", "name:ar"], ""], ""], name,
            ["get", "name:ar"]]
        return ["case", hasArabicScript, name, nonEmptyArabicName] as [Any]
    }

    /// Pastel map (the signature look): positron recoloured soft —
    /// pale-green land, powder-blue water, cream buildings — with the
    /// same Arabic label rule. Cached like the other patched styles.
    static func preparePastelStyle() {
        let dir = MapStyleKind.styleDir
        let file = dir.appendingPathComponent("wijhati-pastel-ar3.json")
        if FileManager.default.fileExists(atPath: file.path) { return }
        guard let remote = URL(string: "https://tiles.openfreemap.org/styles/positron") else { return }
        URLSession.shared.dataTask(with: remote) { data, _, _ in
            guard let data,
                  var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  var layers = root["layers"] as? [[String: Any]] else { return }
            let fills: [String: String] = [
                "park": "#C3E2AD", "landcover_wood": "#ADD39F",
                "water": "#A9DDEB", "landuse_residential": "#F3EEDC",
                "building": "#EADFCB",
            ]
            for i in layers.indices {
                let id = layers[i]["id"] as? String ?? ""
                var paint = layers[i]["paint"] as? [String: Any] ?? [:]
                if id == "background" { paint["background-color"] = "#EEF3DF"; layers[i]["paint"] = paint }
                if let hex = fills[id] { paint["fill-color"] = hex; layers[i]["paint"] = paint }
                if id == "waterway" { paint["line-color"] = "#A9DDEB"; layers[i]["paint"] = paint }
                if var layout = layers[i]["layout"] as? [String: Any], layout["text-field"] != nil {
                    layout["text-field"] = arabicNameExpression()
                    layers[i]["layout"] = layout
                    paint["text-color"] = "#4F5D4E"
                    paint["text-halo-color"] = "#FFFFFF"
                    layers[i]["paint"] = paint
                }
            }
            root["layers"] = layers
            if let out = try? JSONSerialization.data(withJSONObject: root) {
                try? out.write(to: file, options: .atomic)
            }
        }.resume()
    }

    static func prepareArabicStyles() {
        preparePastelStyle()
        for name in ["liberty", "positron", "bright", "dark"] {
            guard let remote = URL(string: "https://tiles.openfreemap.org/styles/\(name)") else { continue }
            let dir = MapStyleKind.styleDir
            let file = dir.appendingPathComponent("wijhati-\(name)-ar3.json")
            if FileManager.default.fileExists(atPath: file.path) { continue }
            URLSession.shared.dataTask(with: remote) { data, _, _ in
                guard let data,
                      var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      var layers = root["layers"] as? [[String: Any]] else { return }
                for i in layers.indices {
                    guard var layout = layers[i]["layout"] as? [String: Any],
                          layout["text-field"] != nil else { continue }
                    layout["text-field"] = arabicNameExpression()
                    layers[i]["layout"] = layout
                }
                if name == "dark" {
                    // Miru night: deep indigo city, near-black blue
                    // water, warm street-light glow under major roads.
                    let darkFills: [String: String] = [
                        "water": "#152533", "landuse_residential": "#262457",
                        "landcover_wood": "#1D2B22", "landuse_park": "#1D2B22",
                        "building": "#2A294D", "road_area_pier": "#1B1B40",
                    ]
                    let darkLines: [String: String] = [
                        "waterway": "#152533", "highway_minor": "#23234E",
                        "highway_major_inner": "#2A2A5E", "highway_motorway_inner": "#2A2A5E",
                        "highway_major_casing": "#191938", "highway_motorway_casing": "#191938",
                        "highway_major_subtle": "#1B1B40", "highway_motorway_subtle": "#23234E",
                        "road_pier": "#1B1B40",
                    ]
                    for i in layers.indices {
                        let layerID = layers[i]["id"] as? String ?? ""
                        var paint = layers[i]["paint"] as? [String: Any] ?? [:]
                        if layerID == "background" { paint["background-color"] = "#23204D"; layers[i]["paint"] = paint }
                        if let hex = darkFills[layerID] { paint["fill-color"] = hex; layers[i]["paint"] = paint }
                        if let hex = darkLines[layerID] { paint["line-color"] = hex; layers[i]["paint"] = paint }
                        if layerID == "building" { paint["fill-outline-color"] = "#191938"; layers[i]["paint"] = paint }
                        if (layers[i]["type"] as? String) == "symbol" {
                            paint["text-color"] = "#EDEDF7"; paint["text-halo-color"] = "#14142E"; layers[i]["paint"] = paint
                        }
                    }
                    if let glowAt = layers.firstIndex(where: { ($0["id"] as? String ?? "").hasPrefix("highway") }) {
                        let glow: [String: Any] = [
                            "id": "wijhati-road-glow", "type": "line", "source": "openmaptiles",
                            "source-layer": "transportation",
                            "filter": ["in", ["get", "class"], ["literal", ["motorway", "trunk", "primary"]]] as [Any],
                            "layout": ["line-cap": "round", "line-join": "round"] as [String: Any],
                            "paint": ["line-color": "#E8933A", "line-opacity": 0.35, "line-blur": 8,
                                      "line-width": ["interpolate", ["linear"], ["zoom"], 12, 2, 16, 10] as [Any]] as [String: Any],
                        ]
                        layers.insert(glow, at: glowAt)
                    }
                }
                root["layers"] = layers
                if let out = try? JSONSerialization.data(withJSONObject: root) {
                    try? out.write(to: file, options: .atomic)
                    if name == "dark" {
                        try? out.write(to: dir.appendingPathComponent("wijhati-darkmiru-ar3.json"), options: .atomic)
                    }
                }
            }.resume()
        }
    }

}

/// One-line health log for the map, shown in Settings → About so a
/// single screenshot reveals what the map actually did.
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
    var heading: Double
    var pitch: CGFloat

    init(map: MLNMapView) {
        let camera = map.camera
        center = camera.centerCoordinate
        zoom = map.zoomLevel
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

    private var isNightStyle: Bool {
        styleKind == .dark || styleKind == .ofmDark || styleKind == .cinematic
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleKind.url ?? MapStyleKind.standard.url)
        map.delegate = context.coordinator
        map.backgroundColor = isNightStyle ? UIColor(red: 0.035, green: 0.055, blue: 0.11, alpha: 1) : UIColor.systemBackground
        map.isOpaque = false
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        map.showsUserLocation = isAppActive
        map.prefetchesTiles = isAppActive && followUser
        map.compassView.isHidden = true
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        if let restoreCamera {
            map.setCenter(restoreCamera.center, zoomLevel: min(22, max(0, restoreCamera.zoom)), animated: false)
            var camera = map.camera
            camera.heading = restoreCamera.heading
            camera.pitch = restoreCamera.pitch
            map.setCamera(camera, animated: false)
        } else {
            let initialCenter = userLocation ?? CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661)
            let initialZoom: Double = userLocation == nil ? 11 : (show3D && !styleKind.isRaster ? 16 : 13)
            map.setCenter(initialCenter, zoomLevel: initialZoom, animated: false)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        map.addGestureRecognizer(longPress)
        context.coordinator.map = map
        if restoreCamera != nil {
            DispatchQueue.main.async {
                context.coordinator.parent.onCameraRestoreConsumed()
            }
        }
        // The Arabic-patched copy of the current style may finish
        // downloading just after launch; if so, swap to it once so
        // labels turn Arabic without waiting for the next launch.
        let kindAtMake = styleKind
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak map] in
            guard let map, context.coordinator.currentStyle == kindAtMake,
                  let fresh = kindAtMake.url, map.styleURL != fresh else { return }
            context.coordinator.styleReady = false
            map.styleURL = fresh
            context.coordinator.armWatchdog(stage: 0)
        }
        context.coordinator.armWatchdog(stage: 0)
        return map
    }

    static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
        coordinator.cancelWatchdog()
        coordinator.cancelResumeFallback()
        NotificationCenter.default.removeObserver(coordinator)
        uiView.delegate = nil
        coordinator.map = nil
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        map.logoView.isHidden = true
        map.attributionButton.isHidden = true
        map.backgroundColor = isNightStyle ? UIColor(red: 0.035, green: 0.055, blue: 0.11, alpha: 1) : UIColor.systemBackground
        if context.coordinator.requestedStyle != styleKind {
            context.coordinator.requestedStyle = styleKind
            context.coordinator.usingFallbackStyle = false
            context.coordinator.currentStyle = styleKind
            context.coordinator.styleReady = false
            if styleKind == .cinematic {
                context.coordinator.was3DOn = false
                if show3D && !styleKind.isRaster && map.zoomLevel >= 13.0 {
                    if map.zoomLevel < 15.5 {
                        map.setCenter(map.centerCoordinate, zoomLevel: 16, animated: true)
                    }
                    var camera = map.camera
                    camera.pitch = max(camera.pitch, 58)
                    map.setCamera(camera, animated: true)
                }
            }
            map.styleURL = styleKind.url ?? MapStyleKind.standard.url
            context.coordinator.armWatchdog(stage: 0)
        }
        context.coordinator.setMapActive(isAppActive)
        let shouldShowUserLocation = isAppActive
        if map.showsUserLocation != shouldShowUserLocation {
            map.showsUserLocation = shouldShowUserLocation
        }
        let shouldPrefetchTiles = isAppActive && followUser
        if map.prefetchesTiles != shouldPrefetchTiles {
            map.prefetchesTiles = shouldPrefetchTiles
        }
        if let ul = userLocation, !context.coordinator.didCenterOnUser {
            context.coordinator.didCenterOnUser = true
            let locationZoom: Double = show3D && !styleKind.isRaster ? 16 : 13
            map.setCenter(ul, zoomLevel: locationZoom, animated: false)
            if show3D && !styleKind.isRaster {
                let targetPitch: CGFloat = styleKind == .cinematic ? 58 : 50
                var camera = map.camera
                camera.pitch = max(camera.pitch, targetPitch)
                map.setCamera(camera, animated: false)
            }
        }
        if isAppActive && followUser {
            if map.userTrackingMode != .followWithHeading { map.userTrackingMode = .followWithHeading }
        } else if map.userTrackingMode != .none {
            map.userTrackingMode = .none
        }
        if let req = bearingRequest, context.coordinator.lastBearingID != req.id {
            context.coordinator.lastBearingID = req.id
            var cam = map.camera
            cam.heading = req.degrees
            map.setCamera(cam, animated: true)
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
        private var placeByAnnotationID: [ObjectIdentifier: Place] = [:]
        var currentStyle: MapStyleKind
        var requestedStyle: MapStyleKind
        var styleReady = false
        var lastCenterID: UUID?
        var lastBearingID: UUID?
        var didCenterOnUser = false
        var lastLayerSignature = "" 
        var lastNorthReset: Int = 0
        var usingFallbackStyle = false
        var was3DOn = false
        var watchdog: DispatchWorkItem?
        var resumeFallback: DispatchWorkItem?
        private var watchdogToken = UUID()
        private var didEnterBackground = false
        private var resumeScheduled = false
        private var lifecycleGeneration = 0
        private var lastReportedAppActive: Bool?
        private var lastAutoTiltZoom: Double?

        func cancelWatchdog() {
            watchdog?.cancel()
            watchdog = nil
            watchdogToken = UUID()
        }

        func cancelResumeFallback() {
            resumeFallback?.cancel()
            resumeFallback = nil
        }

        private func noteBackground() {
            if lastReportedAppActive != false { lifecycleGeneration += 1 }
            lastReportedAppActive = false
            didEnterBackground = true
            resumeScheduled = false
            cancelResumeFallback()
            cancelWatchdog()
        }

        @objc func appEnteredBackground() {
            lifecycleGeneration += 1
            lastReportedAppActive = false
            didEnterBackground = true
            resumeScheduled = false
            cancelResumeFallback()
            cancelWatchdog()
        }

        @objc func appWillEnterForeground() {
            if lastReportedAppActive != false { lifecycleGeneration += 1 }
            lastReportedAppActive = false
            didEnterBackground = true
        }

        func setMapActive(_ active: Bool) {
            if active {
                lastReportedAppActive = true
                appBecameActive()
            } else {
                noteBackground()
            }
        }

        /// Recover from transient style failures without retrying a known-bad
        /// user style forever or changing the camera.
        func armWatchdog(stage: Int) {
            cancelWatchdog()
            let token = watchdogToken
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.watchdogToken == token,
                      let map = self.map, !self.styleReady else { return }
                guard UIApplication.shared.applicationState == .active else {
                    self.watchdog = nil
                    return
                }
                switch stage {
                case 0:
                    MapHealth.log("الحارس: إعادة تحميل النمط الحالي من المصدر البعيد")
                    map.styleURL = self.currentStyle.remoteURL ?? self.currentStyle.url
                    self.armWatchdog(stage: 1)
                case 1:
                    MapHealth.log("الحارس: تحويل للستايل القياسي")
                    if self.currentStyle != .standard {
                        self.usingFallbackStyle = true
                    }
                    self.currentStyle = .standard
                    map.styleURL = MapStyleKind.standard.url
                    self.armWatchdog(stage: 2)
                case 2:
                    MapHealth.log("الحارس: إعادة محاولة النمط القياسي من المصدر البعيد")
                    self.currentStyle = .standard
                    self.usingFallbackStyle = true
                    map.styleURL = MapStyleKind.standard.remoteURL ?? MapStyleKind.standard.url
                    self.armWatchdog(stage: 3)
                default:
                    MapHealth.log("الحارس: النمط ما زال ينتظر اتصال البلاطات")
                    self.watchdog = nil
                }
            }
            watchdog = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }

        @objc func appBecameActive() {
            guard didEnterBackground, !resumeScheduled, map != nil else { return }
            resumeScheduled = true
            let generation = lifecycleGeneration
            guard let map else {
                resumeScheduled = false
                return
            }
            MapHealth.log("رجوع للواجهة: استعادة إطار الخريطة الحالي")
            map.setNeedsLayout()
            map.layoutIfNeeded()
            map.setNeedsDisplay()

            // Reuse a healthy GL surface, but do not leave a blank map waiting
            // through a style reload. Recreate the view quickly if no complete
            // frame arrives, preserving the user's exact camera position.
            let fallback = DispatchWorkItem { [weak self, weak map] in
                guard let self, self.lifecycleGeneration == generation,
                      self.resumeScheduled, self.didEnterBackground else { return }
                guard UIApplication.shared.applicationState == .active else {
                    self.resumeScheduled = false
                    self.didEnterBackground = true
                    return
                }
                guard let map else {
                    self.resumeScheduled = false
                    return
                }
                let restoreStyle = self.usingFallbackStyle ? MapStyleKind.standard : self.requestedStyle
                let camera = MapCameraSnapshot(map: map)
                self.resumeFallback = nil
                self.resumeScheduled = false
                self.didEnterBackground = false
                MapHealth.log("رجوع للواجهة: إعادة إنشاء سطح الخريطة بعد غياب الإطار")
                self.parent.onRecoveryExhausted(restoreStyle, camera)
            }
            resumeFallback = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: fallback)
        }

        func mapView(_ mapView: MLNMapView, didFinishRenderingFrame fullyRendered: Bool) {
            guard fullyRendered, resumeScheduled, didEnterBackground,
                  styleReady, mapView.style != nil,
                  UIApplication.shared.applicationState == .active else { return }
            cancelResumeFallback()
            resumeScheduled = false
            didEnterBackground = false
            MapHealth.log("رجوع للواجهة: الخريطة رسمت إطارًا")
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onMapTap()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            parent.onLongPress(coordinate)
        }

        func mapView(_ mapView: MLNMapView, didFailLoading style: MLNStyle, withError error: Error) {
            MapHealth.log("خطأ تحميل \(currentStyle.rawValue): \(error.localizedDescription.prefix(60))")
            // Keep the requested style separate from the currently rendered
            // fallback so location updates do not reapply a failed style.
            styleReady = false
            usingFallbackStyle = true
            if currentStyle != .standard {
                currentStyle = .standard
                mapView.styleURL = MapStyleKind.standard.url
            }
            armWatchdog(stage: 2)
        }
        private var shownPins: [Place] = []

        init(_ parent: MapBridge) {
            self.parent = parent
            self.currentStyle = parent.styleKind
            self.requestedStyle = parent.styleKind
        }

        // MARK: Delegate
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            mapView.logoView.isHidden = true
            mapView.attributionButton.isHidden = true
            styleReady = true
            if currentStyle == requestedStyle {
                usingFallbackStyle = false
            }
            cancelWatchdog()
            lastLayerSignature = ""
            mapView.setNeedsLayout()
            mapView.setNeedsDisplay()
            refreshLayers(style: style)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            let zoom = mapView.zoomLevel
            let zoomChanged = lastAutoTiltZoom.map { abs($0 - zoom) > 0.12 } ?? false
            lastAutoTiltZoom = zoom
            guard zoomChanged, parent.show3D, !currentStyle.isRaster, zoom >= 15 else { return }
            let targetPitch: CGFloat = currentStyle == .cinematic ? 58 : 50
            guard mapView.camera.pitch < targetPitch else { return }
            var camera = mapView.camera
            camera.pitch = targetPitch
            mapView.setCamera(camera, animated: true)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { false }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            if let place = placeByAnnotationID[ObjectIdentifier(annotation as AnyObject)] {
                parent.onSelectPin(place)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard let place = placeByAnnotationID[ObjectIdentifier(annotation as AnyObject)] else { return nil }
            let isCommunity = place.id.hasPrefix("community-")
            let isOfficial = place.id.hasPrefix("official-")
            let id = isCommunity ? "wijhati-community-pin" : (isOfficial ? "wijhati-official-pin" : "wijhati-pin")
            if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: id) { return existing }
            let img = isCommunity ? Self.communityPinImage() : (isOfficial ? Self.officialPinImage() : Self.pinImage())
            return MLNAnnotationImage(image: img, reuseIdentifier: id)
        }

        static func officialPinImage() -> UIImage {
            let size = CGSize(width: 34, height: 34)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30))
                UIColor(red: 0.85, green: 0.62, blue: 0.08, alpha: 1).setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                let center = UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 6, height: 6))
                UIColor.white.setFill()
                center.fill()
            }
        }

        static func communityPinImage() -> UIImage {
            let size = CGSize(width: 34, height: 34)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let circle = UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 30, height: 30))
                UIColor.systemPurple.setFill()
                circle.fill()
                UIColor.white.setStroke()
                circle.lineWidth = 2.5
                circle.stroke()
                let center = UIBezierPath(ovalIn: CGRect(x: 14, y: 14, width: 6, height: 6))
                UIColor.white.setFill()
                center.fill()
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
            guard let map, parent.pins != shownPins else { return }
            shownPins = parent.pins
            if let existing = map.annotations { map.removeAnnotations(existing) }
            placeByAnnotationID.removeAll(keepingCapacity: true)
            let anns = parent.pins.map { p -> MLNPointAnnotation in
                let a = MLNPointAnnotation()
                a.coordinate = p.coordinate
                a.title = p.name
                placeByAnnotationID[ObjectIdentifier(a)] = p
                return a
            }
            if !anns.isEmpty { map.addAnnotations(anns) }
        }

        // MARK: Layers
        func refreshLayers(style: MLNStyle) {
            let signature = "\(parent.routeRevision)-\(parent.routeCoords.count)-\(parent.altRouteCoords.count)-\(parent.tripCoords.count)-\(parent.show3D)-\(currentStyle.rawValue)-\(parent.routeCoords.first?.latitude ?? 0)-\(parent.routeCoords.first?.longitude ?? 0)-\(parent.routeCoords.last?.latitude ?? 0)-\(parent.altRouteCoords.first?.latitude ?? 0)-\(parent.altRouteCoords.last?.longitude ?? 0)-\(parent.tripCoords.last?.latitude ?? 0)"
            if signature == lastLayerSignature { return }
            lastLayerSignature = signature
            updatePOILabels(style: style)
            updateLine(style: style, id: "alt-route", coords: parent.altRouteCoords,
                       color: .gray, width: 4, opacity: 0.6)
            updateLine(style: style, id: "route", coords: parent.routeCoords,
                       color: .systemBlue, width: 6, opacity: 1.0)
            updateLine(style: style, id: "trip", coords: parent.tripCoords,
                       color: .systemOrange, width: 5, opacity: 0.95)
            updateBuildings(style: style)
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
                    if id == "route" {
                        let halo = MLNLineStyleLayer(identifier: "\(id)-halo-layer", source: source)
                        let haloColor = currentStyle == .cinematic
                            ? UIColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 0.96)
                            : UIColor(red: 1.0, green: 0.91, blue: 0.70, alpha: 0.96)
                        halo.lineColor = NSExpression(forConstantValue: haloColor)
                        halo.lineWidth = NSExpression(forConstantValue: 11.0)
                        halo.lineOpacity = NSExpression(forConstantValue: 0.92)
                        halo.lineCap = NSExpression(forConstantValue: "round")
                        halo.lineJoin = NSExpression(forConstantValue: "round")
                        style.addLayer(halo)
                    }
                    let layer = MLNLineStyleLayer(identifier: "\(id)-layer", source: source)
                    let routeColor: UIColor
                    if id == "route" {
                        routeColor = currentStyle == .cinematic
                            ? UIColor(red: 1.0, green: 0.72, blue: 0.34, alpha: 1)
                            : UIColor(red: 0.96, green: 0.39, blue: 0.16, alpha: 1)
                    } else {
                        routeColor = color
                    }
                    layer.lineColor = NSExpression(forConstantValue: routeColor)
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
            let cinematic = currentStyle == .cinematic
            layer.textColor = NSExpression(forConstantValue: cinematic
                ? UIColor(red: 0.90, green: 0.84, blue: 0.69, alpha: 1)
                : UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1))
            layer.textHaloColor = NSExpression(forConstantValue: cinematic
                ? UIColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 0.96)
                : UIColor.white.withAlphaComponent(0.9))
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
                    if isShortbread {
                        layer.fillExtrusionHeight = NSExpression(forKeyPath: "height")
                        layer.fillExtrusionBase = NSExpression(forKeyPath: "min_height")
                    } else {
                        // Heights grow in smoothly from z15 (OpenFreeMap
                        // recipe). NOTE: no 'extrude' filter — OFM tiles do
                        // not carry that field at all (checked in their
                        // TileJSON), filtering on it hides every building.
                        layer.fillExtrusionHeight = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 15, 0, 15.05, ["get", "render_height"]] as [Any])
                        layer.fillExtrusionBase = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["zoom"], 15, 0, 15.05, ["get", "render_min_height"]] as [Any])
                    }
                    // Colour per building (Miru toy-city): a fixed
                    // palette distributed by feature id — every building
                    // feature in the served tiles carries an id
                    // (verified) — preferring the building's own tagged
                    // colour when the data has one.
                    let night3D = parent.styleKind == .ofmDark || parent.styleKind == .dark
                    let palette3D: [Any]
                    if parent.styleKind == .cinematic {
                        palette3D = ["match", ["%", ["id"], 7], 0, "#302E5E", 1, "#744632", 2, "#39366C", 3, "#28264F", 4, "#8A5032", 5, "#433B70", "#252349"] as [Any]
                    } else if night3D {
                        palette3D = ["match", ["%", ["id"], 7], 0, "#2E2C63", 1, "#37356E", 2, "#403E7A", 3, "#2A2A55", 4, "#332F66", 5, "#3B3873", "#282450"] as [Any]
                    } else {
                        palette3D = ["match", ["%", ["id"], 7], 0, "#EEDFC8", 1, "#F5F1EA", 2, "#EFD2B4", 3, "#BFD2E8", 4, "#C2DED2", 5, "#EBCBCB", "#E3CFA5"] as [Any]
                    }
                    layer.fillExtrusionColor = NSExpression(mglJSONObject: ["coalesce", ["get", "colour"], palette3D] as [Any])
                    layer.fillExtrusionOpacity = NSExpression(forConstantValue: 0.95)
                    layer.minimumZoomLevel = 15
                    // Insert BELOW the label layers so buildings never cover text.
                    if let firstSymbol = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                        style.insertLayer(layer, below: firstSymbol)
                    } else {
                        style.addLayer(layer)
                    }
                }
                if let map, !was3DOn {
                    was3DOn = true
                    // At city zoom, bring the map into the 3D view. Keep a
                    // regional/world view untouched until the user zooms in.
                    if map.zoomLevel >= 13.0 {
                        if map.zoomLevel < 15.5 { map.setCenter(map.centerCoordinate, zoomLevel: 16, animated: true) }
                        let targetPitch: CGFloat = parent.styleKind == .cinematic ? 58 : 50
                        if map.camera.pitch < targetPitch { var cam = map.camera; cam.pitch = targetPitch; map.setCamera(cam, animated: true) }
                    }
                }
            } else {
                was3DOn = false
                if let layer = style.layer(withIdentifier: layerID) { style.removeLayer(layer) }
                if parent.show3D == false, let map, map.camera.pitch > 1 { var cam = map.camera; cam.pitch = 0; map.setCamera(cam, animated: true) }
            }
        }

    }
}
