import SwiftUI
import CoreLocation
import UIKit
import WidgetKit

private typealias MapControlPressStyle = AppPressStyle

struct Category: Identifiable {
    var id: String { key }
    var key: String
    var group: String
    var title: String
    var icon: String
}

let categories: [Category] = [
    Category(key: "restaurant", group: "amenity", title: "مطاعم", icon: "fork.knife"),
    Category(key: "cafe", group: "amenity", title: "كافيهات", icon: "cup.and.saucer.fill"),
    Category(key: "hotel", group: "tourism", title: "فنادق", icon: "bed.double.fill"),
    Category(key: "hospital", group: "amenity", title: "مستشفيات", icon: "cross.case.fill"),
    Category(key: "pharmacy", group: "amenity", title: "صيدليات", icon: "pills.fill"),
    Category(key: "fuel", group: "amenity", title: "وقود", icon: "fuelpump.fill"),
    Category(key: "park", group: "leisure", title: "حدائق", icon: "tree.fill"),
    Category(key: "supermarket", group: "shop", title: "تسوق", icon: "cart.fill"),
]

struct ContentView: View {
    @StateObject private var locationService = LocationService()
    @StateObject private var store = PlacesStore()
    @StateObject private var historyStore = SearchHistoryStore()
    @StateObject private var voice = VoiceGuide()
    @StateObject private var community = CommunityStore()
    @StateObject private var official = OfficialStore()
    @StateObject private var voiceSearch = VoiceSearch()
    @State private var showAssistant = false
    @State private var showAR = false
    @State private var homePlace: Place?
    @State private var workPlace: Place?
    @State private var publishPlace: Place?

    @AppStorage("wijhati.tempUnit") private var tempUnit = "c"
    @AppStorage("wijhati.appearance") private var appearance = "auto"
    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @AppStorage("wijhati.notifMaster") private var notifMaster = true
    @AppStorage("wijhati.language") private var language = "ar"
    @AppStorage("wijhati.voiceID") private var voiceID = ""
    @AppStorage("wijhati.voiceStyle") private var voiceStyle = "calm"
    @AppStorage("wijhati.officialLayer") private var officialEnabled = true
    @AppStorage("wijhati.azureVoice") private var azureVoice = "ar-IQ-BasselNeural"
    @AppStorage("wijhati.azureRegion") private var azureRegion = "eastus"
    @State private var azureKeyInput = ""
    @State private var azureKeyStatus = ""
    @AppStorage("wijhati.lastLightStyle") private var lastLightStyle = "standard"
    @AppStorage("wijhati.autoDark") private var autoDark = false
    @Environment(\.colorScheme) private var deviceScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("wijhati.voiceVolume") private var voiceVolume: Double = 1.0
    @AppStorage("wijhati.distanceUnit") private var distanceUnit = "auto"
    @AppStorage("wijhati.notifSaved") private var notifSaved = false

    @State private var query = ""
    @State private var suggestions: [Place] = []
    @State private var pins: [Place] = []
    @State private var selected: Place?
    @State private var stops: [Place] = []
    @State private var transport: TransportChoice = .driving
    @State private var routes: [RouteData] = []
    @State private var routeGeneration = 0
    @State private var offRouteCount = 0
    @State private var lastRouteAt = Date.distantPast
    @State private var selectedRouteIndex = 0
    @State private var searching = false
    @State private var searchGeneration = 0
    @State private var loadingRoute = false

    @State private var styleKind: MapStyleKind = .standard
    @State private var followUser = false
    @State private var centerRequest: CenterRequest?
    @State private var mapRebuildGeneration = 0
    @State private var mapRecoveryStyle: MapStyleKind?
    @State private var pendingMapCameraRestore: MapCameraSnapshot?

    @State private var showSaved = false
    @State private var showSettings = false
    @State private var showMapAttribution = false
    @AppStorage("wijhati.show3D") private var show3D = true
    @State private var placeWeather: GeoService.WeatherNow?
    @State private var placeDetails: GeoService.PlaceDetails?
    @State private var showDirections = false
    @State private var directionsText = ""
    @State private var searchPins: [Place] = []
    @State private var speedLimitKmh: Int?
    @State private var lastLimitLoc: CLLocation?
    @State private var lastOverspeedAt = Date.distantPast
    @State private var localWeather: GeoService.WeatherNow?
    @State private var weatherFetchedAt: Date?
    @State private var weatherForCoord: CLLocationCoordinate2D?
    @State private var showWeatherDetail = false
    @State private var elevations: [Double] = []
    @State private var shareItem: SharePayload?
    @State private var showSearch = false
    @FocusState private var overlayFocused: Bool
    @State private var routeNotice: String?
    @State private var routeFailed = false
    @State private var suggestTask: Task<Void, Never>?
    @State private var suggestionSearching = false
    @State private var pendingQuickRoute = false
    @State private var pendingInitialLocationCenter = true
    @State private var lastStartupCenterTimestamp: Date?
    @State private var showIntro = false
    @State private var pendingCenterOnUser = false
    @State private var locationNotice: String?
    @State private var locationWaitGeneration = 0
    @State private var placeSheetFull = false
    @State private var placeSheetDragY: CGFloat = 0
    @State private var placeSheetVelocity: CGFloat = 0
    @State private var dragPrevY: CGFloat = 0
    @State private var dragLastTime: Date?
    @State private var alertCooldown: [String: Date] = [:]

    private var allPins: [Place] {
        pins + community.allPlaces.map { $0.asPlace() }
            + (officialEnabled ? official.places : [])
    }
    /// Keep the field's writing direction tied to the first strong character,
    /// rather than the app's chrome direction, so Arabic and English searches
    /// both begin on their natural edge.
    private var searchTextDirection: LayoutDirection {
        for scalar in query.unicodeScalars where CharacterSet.letters.contains(scalar) {
            return Self.isArabicScript(scalar.value) ? .rightToLeft : .leftToRight
        }
        return language == "en" ? .leftToRight : .rightToLeft
    }

    private static func isArabicScript(_ value: UInt32) -> Bool {
        (0x0600...0x08FF).contains(value)
            || (0xFB50...0xFDFF).contains(value)
            || (0xFE70...0xFEFF).contains(value)
            || (0x1EE00...0x1EEFF).contains(value)
    }

    private var schemeOverride: ColorScheme? {
        if appearance == "dark" { return .dark }
        if appearance == "light" { return .light }
        return nil
    }
    private var locationAuthorized: Bool {
        locationService.authorization == .authorizedWhenInUse || locationService.authorization == .authorizedAlways
    }
    private var foregroundLocationActive: Bool {
        scenePhase == .active && !showSettings
    }

    /// Dark (from the device or the in-app appearance) means a night map —
    /// automatically. The last light style is remembered and restored.
    private var effectiveDark: Bool {
        appearance == "dark" || (appearance == "auto" && deviceScheme == .dark)
    }

    private var glassPresetBinding: Binding<Double> {
        Binding(
            get: { [0.0, 0.53, 1.0].min { abs($0 - glassLevel) < abs($1 - glassLevel) } ?? 0.53 },
            set: { glassLevel = $0 }
        )
    }

    private func syncStyleToScheme(initial: Bool = false) {
        if effectiveDark {
            if !initial && !autoDark && styleKind != .dark {
                lastLightStyle = styleKind.rawValue
            }
            styleKind = .dark
            autoDark = true
        } else if initial || autoDark {
            let savedStyle = MapStyleKind(rawValue: lastLightStyle) ?? .standard
            styleKind = savedStyle == .dark ? .standard : savedStyle
            autoDark = false
        }
    }

    private var selectedRoute: RouteData? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }
    private var altCoords: [CLLocationCoordinate2D] {
        routes.enumerated().filter { $0.offset != selectedRouteIndex }.first?.element.coordinates ?? []
    }
    private var routeLayerRevision: String {
        "\(routeGeneration):\(selectedRouteIndex):" + routes.map { $0.id.uuidString }.joined(separator: ":")
    }

    private func fmtDist(_ meters: Double) -> String {
        let useMiles: Bool
        switch distanceUnit {
        case "mi": useMiles = true
        case "km": useMiles = false
        default: useMiles = false
        }
        if useMiles {
            let mi = meters / 1609.34
            if mi >= 0.1 { return String(format: "%.1f %@", mi, "ميل".loc) }
            return String(format: "%.0f %@", meters * 3.28084, "قدم".loc)
        }
        return formatDistance(meters)
    }

    private func displayTemp(_ celsius: Double) -> String {
        if tempUnit == "f" { return "\(Int((celsius * 9 / 5 + 32).rounded()))°F" }
        return "\(Int(celsius.rounded()))°C"
    }

    private var mapComposition: some View {
        ZStack {
            MapBridge(
                pins: allPins,
                routeCoords: selectedRoute?.coordinates ?? [],
                altRouteCoords: altCoords,
                tripCoords: [],
                routeRevision: routeLayerRevision,
                styleKind: mapRecoveryStyle ?? styleKind,
                show3D: show3D,
                followUser: followUser,
                isAppActive: scenePhase == .active && (!showSettings || voice.active),
                userLocation: locationService.location?.coordinate,
                centerRequest: centerRequest,
                bearingRequest: nil,
                northReset: 0,
                onSelectPin: { place in select(place) },
                onLongPress: { coordinate in handleLongPress(coordinate) },
                onMapTap: { closeMapSearch() },
                restoreCamera: pendingMapCameraRestore,
                onCameraRestoreConsumed: { pendingMapCameraRestore = nil },
                onRecoveryExhausted: { recoveredStyle, camera in
                    mapRecoveryStyle = recoveredStyle
                    pendingMapCameraRestore = camera
                    mapRebuildGeneration += 1
                }
            )
            .id(mapRebuildGeneration)
            .ignoresSafeArea()

            if showSearch {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { closeMapSearch() }
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                topBar
                if showWeatherDetail, let w = localWeather {
                    weatherDetailCard(w)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if !showSearch {
                    statusPills
                    if let locationNotice {
                        Text(locationNotice)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .glass(cornerRadius: 15)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if loadingRoute { routeLoadingBanner }
                }
                Spacer(minLength: 0)
                if showSearch { searchResultsPanel }
                floatingMapTools
                if !showSearch && (selected != nil || selectedRoute != nil || !stops.isEmpty || routeNotice != nil) {
                    bottomStack
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showSearch)

            if voice.active { pocketOverlay }
            if showIntro {
                WorldIntroView {
                    withAnimation(.easeInOut(duration: 0.32)) { showIntro = false }
                }
                .transition(.opacity)
                .zIndex(20)
            }
            DynamicIslandNoticeOverlay()
                .zIndex(30)

        }
    }

    private var lifecycleContent: some View {
        mapComposition
        .onAppear {
            locationService.setAppActive(foregroundLocationActive)
            locationService.requestCurrentLocation()
            homePlace = Self.loadQuickPlace("wijhati.homePlace")
            workPlace = Self.loadQuickPlace("wijhati.workPlace")
            syncWidgetPlaces()
            syncStyleToScheme(initial: true)
            if let loc = locationService.location {
                centerAtStartupIfNeeded(loc, resolvesInitialFix: false)
            }
            if pendingInitialLocationCenter && locationAuthorized {
                scheduleLocationWaitTimeout(forStartup: true)
            }
        }
        .onChange(of: locationService.location) { _, newValue in
            guard let loc = newValue else { return }
            if pendingCenterOnUser {
                if loc.horizontalAccuracy >= 0 {
                    centerMapOnUser(loc)
                    if abs(Date().timeIntervalSince(loc.timestamp)) <= 30 {
                        pendingCenterOnUser = false
                        cancelLocationWaitTimeout()
                    }
                }
            } else if pendingInitialLocationCenter {
                centerAtStartupIfNeeded(loc)
            }
            if !pendingCenterOnUser { locationNotice = nil }
            if pendingQuickRoute {
                pendingQuickRoute = false
                Task { await computeRoute() }
            }
            voice.update(userLocation: loc)
            refreshLocalWeatherIfNeeded(loc.coordinate)
            checkProximity(loc)
            checkOffRoute(loc)
            checkSpeedLimit(loc)
        }
        .onChange(of: locationService.authorization) { _, status in
            if (pendingCenterOnUser || pendingInitialLocationCenter) &&
                (status == .denied || status == .restricted) {
                showLocationNotice("اسمح بالوصول إلى الموقع من إعدادات الآيفون.".loc)
            } else if (pendingCenterOnUser || pendingInitialLocationCenter) &&
                        (status == .authorizedWhenInUse || status == .authorizedAlways) {
                locationService.requestCurrentLocation()
                scheduleLocationWaitTimeout(forStartup: pendingInitialLocationCenter && !pendingCenterOnUser)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            locationService.setAppActive(phase == .active && !showSettings)
            if phase == .active && (pendingCenterOnUser || pendingInitialLocationCenter) {
                locationService.requestCurrentLocation()
                if locationAuthorized {
                    scheduleLocationWaitTimeout(forStartup: pendingInitialLocationCenter && !pendingCenterOnUser)
                }
            }
        }
        .onChange(of: showSettings) { _, presented in
            locationService.setAppActive(scenePhase == .active && !presented)
        }
        .onChange(of: voice.active) { _, active in
            locationService.setNavigationActive(active)
            followUser = active
        }
        .onChange(of: showAR) { _, active in
            locationService.setCameraNavigationActive(active)
        }
    }

    private var styledContent: some View {
        lifecycleContent
        .preferredColorScheme(schemeOverride)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
        .onAppear { applySemanticDirection() }
        .onChange(of: language) { _, _ in applySemanticDirection() }
        .onChange(of: showSearch) { _, open in
            if !open {
                overlayFocused = false
                voiceSearch.stop()
                cancelSuggestionSearch()
            }
        }
        .onChange(of: appearance) { _, _ in syncStyleToScheme() }
        .onChange(of: deviceScheme) { _, _ in syncStyleToScheme() }
        .onChange(of: styleKind) { _, newKind in
            mapRecoveryStyle = nil
            // A manual style pick always wins over the automatic night sync.
            if effectiveDark, newKind != .dark { autoDark = false }
            if !effectiveDark { lastLightStyle = newKind.rawValue }
        }
    }

    private var presentedContent: some View {
        styledContent
        .sheet(isPresented: $showSaved) { savedSheet }
        .sheet(isPresented: $showDirections) { directionsSheet }
        .fullScreenCover(isPresented: $showAR) {
            if let target = voice.nextTargetCoordinate ?? selected?.coordinate {
                ARNavView(locationService: locationService, target: target,
                          instruction: voice.currentInstruction, distance: voice.distanceToNext)
            }
        }
        .onOpenURL { url in
            guard url.scheme == "wijhati" else { return }
            if url.host == "home", let place = homePlace ?? Self.loadQuickPlace("wijhati.homePlace") {
                homePlace = place
                openQuickPlace(place)
            }
            if url.host == "work", let place = workPlace ?? Self.loadQuickPlace("wijhati.workPlace") {
                workPlace = place
                openQuickPlace(place)
            }
            if url.host == "setup" {
                showIntro = false
                showSettings = true
            }
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView(userLocation: locationService.location?.coordinate) { place in
                select(place)
            }
        }
        .sheet(item: $publishPlace) { place in
            AddPlaceSheet(place: place) { name, category, note in
                community.addPlace(name: name, category: category, note: note, at: place.coordinate)
                publishPlace = nil
            }
        }
        .task {
            await community.refresh()
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showMapAttribution) { mapAttributionSheet }
        .sheet(item: $shareItem) { payload in
            ShareSheet(text: payload.text)
        }
    }

    var body: some View {
        presentedContent
    }

    @ViewBuilder
    private var statusPills: some View {
        if !voice.active, let loc = locationService.location, loc.speed > 3 {
            let kmh = Int((loc.speed * 3.6).rounded())
            let over = speedLimitKmh.map { kmh > $0 + 10 } ?? false
            HStack {
                Spacer()
                HStack(spacing: 7) {
                    Text("\(kmh) \("كم/س".loc)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(over ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    if let limit = speedLimitKmh {
                        // Road-sign style limit badge: white disc, red ring.
                        Text("\(limit)")
                            .font(.caption2.weight(.black)).foregroundStyle(.black)
                            .frame(width: 25, height: 25)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().stroke(Color.red, lineWidth: 3))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glass(cornerRadius: 14)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    /// Fetches the posted limit at most once per 150 m of travel, and
    /// speaks one warning per 45 s when the driver is 10+ km/h over it.
    private func checkSpeedLimit(_ loc: CLLocation) {
        guard loc.speed > 5 else { return }
        if let last = lastLimitLoc, loc.distance(from: last) < 150 { /* still check overspeed below */ }
        else {
            lastLimitLoc = loc
            Task { speedLimitKmh = await GeoService.speedLimit(near: loc.coordinate) }
        }
        if let limit = speedLimitKmh, loc.speed * 3.6 > Double(limit) + 10,
           Date().timeIntervalSince(lastOverspeedAt) > 45 {
            lastOverspeedAt = Date()
            voice.announce("انتبه، تجاوزت حد السرعة".loc)
        }
    }

    // (intro moved to IntroView below)

    // MARK: - Top bar (weather + compact menu)



    private var topBar: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    showWeatherDetail.toggle()
                }
                refreshLocalWeatherIfNeeded(locationService.location?.coordinate, force: true)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: weatherSymbol(for: localWeather?.weatherCode))
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(adaptiveSecondaryInk)
                    Text(localWeather.map { displayTemp($0.temperature) } ?? "—")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(adaptiveInk)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .glass(cornerRadius: 21)
            }
            .contentShape(Capsule())
            .buttonStyle(MapControlPressStyle())
            .accessibilityLabel("الطقس الحالي".loc)
            .accessibilityValue(localWeather.map { "\(displayTemp($0.temperature))، \($0.label)" } ?? "جارٍ تحميل الطقس".loc)

            Spacer(minLength: 0)

            Menu {
                Button { showSaved = true } label: {
                    Label("الأماكن المحفوظة".loc, systemImage: "bookmark")
                }
                Button { showAssistant = true } label: {
                    Label("المساعد الذكي".loc, systemImage: "sparkles")
                }
                Button { showSettings = true } label: {
                    Label("الإعدادات".loc, systemImage: "gearshape")
                }
                Button { showMapAttribution = true } label: {
                    Label("إسناد الخريطة".loc, systemImage: "map")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(adaptiveInk)
                    .frame(width: 44, height: 44)
            }
            .glassCircle()
            .contentShape(Circle())
            .buttonStyle(MapControlPressStyle())
            .accessibilityLabel("خيارات التطبيق".loc)
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
    }

    private func openMapSearch(focus: Bool = true) {
        invalidateSearchRequests()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSearch = true
        }
        guard focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard showSearch else { return }
            overlayFocused = true
        }
    }

    private func closeMapSearch() {
        invalidateSearchRequests()
        overlayFocused = false
        voiceSearch.stop()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            showSearch = false
        }
    }

    private func invalidateSearchRequests() {
        searchGeneration += 1
        searching = false
    }

    private var floatingMapTools: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Button { centerOnMyLocation(requestFreshFix: true) } label: {
                    mapToolCircle(icon: "location.fill",
                                  tint: Color(red: 0.04, green: 0.62, blue: 0.49))
                }
                .contentShape(Circle())
                .buttonStyle(MapControlPressStyle())
                .accessibilityLabel("موقعي".loc)
                .accessibilityHint("توسيط الخريطة على موقعك".loc)
                .transition(.scale(scale: 0.9).combined(with: .opacity))

                if showSearch {
                    searchBar
                        .frame(maxWidth: .infinity)
                        .transition(.scale(scale: 0.96, anchor: .leading).combined(with: .opacity))
                } else {
                    Button { openMapSearch() } label: {
                        mapToolCircle(icon: "magnifyingglass",
                                      tint: Color(red: 0.35, green: 0.48, blue: 0.62))
                    }
                    .contentShape(Circle())
                    .buttonStyle(MapControlPressStyle())
                    .accessibilityLabel("بحث".loc)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            if !showSearch { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showSearch)
    }

    private func mapToolCircle(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: verticalSizeClass == .compact ? 52 : 58,
                   height: verticalSizeClass == .compact ? 52 : 58)
            .glassCircle()
            .contentShape(Circle())
    }

    private func weatherDetailCard(_ w: GeoService.WeatherNow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("الطقس عند موقعك".loc).font(.caption.weight(.bold))
                Text("\(displayTemp(w.temperature)) • \(w.label)").font(.subheadline.weight(.medium))
                Text("\("الشروق".loc): \(w.sunrise) • \("الغروب".loc): \(w.sunset)")
                    .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                Text("\("الوحدة من الإعدادات".loc): \(tempUnit == "f" ? "فهرنهايت".loc : "سيليزية".loc)")
                    .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
            }
            .padding(12)
            .glass(cornerRadius: 18)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func weatherSymbol(for code: Int?) -> String {
        guard let code else { return "cloud.fill" }
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 66, 67, 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private func refreshLocalWeatherIfNeeded(_ coordinate: CLLocationCoordinate2D?, force: Bool = false) {
        guard let coordinate else { return }
        if !force, let last = weatherFetchedAt, let lastCoord = weatherForCoord,
           Date().timeIntervalSince(last) < 900,
           CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
               .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 2000 {
            return
        }
        weatherFetchedAt = Date()
        weatherForCoord = coordinate
        Task {
            localWeather = await GeoService.weather(lat: coordinate.latitude, lon: coordinate.longitude)
        }
    }

    // MARK: - Search results (the input stays in the single top search bar)

    private func scheduleSuggestions(for newValue: String) {
        suggestTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestionSearching = false
            suggestions = []
            return
        }

        let local = localMatches(for: trimmed)
        suggestions = local
        suggestionSearching = true
        suggestTask = Task {
            do { try await Task.sleep(nanoseconds: 220_000_000) }
            catch { return }
            guard !Task.isCancelled, query == newValue else { return }
            let remote = await GeoService.search(
                trimmed,
                near: locationService.location?.coordinate,
                limit: 6,
                includeFallback: false,
                timeout: 6
            )
            guard !Task.isCancelled, query == newValue else { return }
            suggestions = local + remote.filter { r in !local.contains { $0.id == r.id } }
            suggestionSearching = false
        }
    }

    private var searchResultsPanel: some View {
        VStack(spacing: 8) {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !historyStore.items.isEmpty || !store.places.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            if !historyStore.items.isEmpty { historyList }
                            if !store.places.isEmpty { savedQuickList }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            } else if !suggestions.isEmpty {
                suggestionsList
            } else if suggestionSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("جاري البحث عن الأماكن".loc).font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(12)
                .glass(cornerRadius: 18)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Button {
                    closeMapSearch()
                    Task { await runSearch() }
                } label: {
                    Label("بحث".loc, systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .glass(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: suggestions.count)
    }

    // MARK: - Bottom stack

    private var bottomStack: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if let place = selected, selectedRoute == nil { placeCard(place) }
                if let route = selectedRoute { routeBar(route) }
                if !stops.isEmpty { stopsBar }
                if let routeNotice, selectedRoute == nil { routeNoticeCard(routeNotice) }
            }
        }
        .frame(maxHeight: verticalSizeClass == .compact ? 210 : 340)
        .opacity(showSearch ? 0 : 1)
        .allowsHitTesting(!showSearch)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: suggestions.isEmpty)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showSearch)
    }

    private var routeLoadingBanner: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("جاري حساب المسار".loc).font(.caption.weight(.bold))
                if let place = selected {
                    Text("إلى".loc + " \(place.name)").font(.caption2).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(transport.label).font(.caption2.weight(.semibold)).foregroundStyle(adaptiveSecondaryInk)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .glass(cornerRadius: 17)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("جاري حساب المسار".loc)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func routeNoticeCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: routeFailed ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(routeFailed ? Color.orange : adaptiveSecondaryInk)
                Text(message)
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if routeFailed {
                Button {
                    routeNotice = nil
                    Task { await computeRoute() }
                } label: {
                    Label("إعادة المحاولة".loc, systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(red: 0.04, green: 0.68, blue: 0.55), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityHint("إعادة حساب المسار إلى الوجهة المختارة".loc)
            }
        }
        .padding(12)
        .glass(cornerRadius: 19)
        .accessibilityElement(children: .contain)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Button { openMapSearch() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.47, green: 0.34, blue: 0.22))
            }
            .buttonStyle(.plain)
            TextField(
                "ابحث عن مكان أو عنوان".loc,
                text: $query,
                prompt: Text("ابحث عن مكان أو عنوان".loc)
                    .foregroundStyle(adaptiveSecondaryInk)
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(adaptiveInk)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, searchTextDirection)
                .focused($overlayFocused)
                .submitLabel(.search)
                .onSubmit {
                    suggestTask?.cancel()
                    suggestionSearching = false
                    closeMapSearch()
                    Task { await runSearch() }
                }
                .onChange(of: query) { _, newValue in scheduleSuggestions(for: newValue) }
                .onChange(of: overlayFocused) { _, focused in
                    if focused && !showSearch {
                        openMapSearch(focus: false)
                    }
                }
            if searching || suggestionSearching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button { query = ""; suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(adaptiveSecondaryInk)
                }
                .buttonStyle(.plain)
            }
            Button {
                overlayFocused = false
                openMapSearch(focus: false)
                voiceSearch.toggle { text in
                    DispatchQueue.main.async { query = text }
                }
            } label: {
                Image(systemName: voiceSearch.isListening ? "mic.fill" : "mic")
                    .foregroundStyle(voiceSearch.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(adaptiveSecondaryInk))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(voiceSearch.isListening ? "إيقاف الإملاء".loc : "البحث بالصوت".loc)
            if showSearch {
                Button {
                    closeMapSearch()
                } label: {
                    Image(systemName: "checkmark").foregroundStyle(adaptiveSecondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تم".loc)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 54)
        .background(Color(red: 0.98, green: 0.97, blue: 0.90).opacity(0.30), in: Capsule())
        .glass(cornerRadius: 27)
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.62), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }


    private var savedQuickList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("أماكنك المحفوظة".loc)
                    .font(.caption.weight(.bold)).foregroundStyle(adaptiveSecondaryInk)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
            ForEach(store.places.prefix(5)) { saved in
                Button { select(saved.place) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: saved.isFavorite ? "star.fill" : "mappin.circle.fill")
                            .foregroundStyle(saved.isFavorite ? .yellow : adaptiveInk).font(.system(size: 17))
                        Text(saved.place.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        if let loc = locationService.location {
                            Text(fmtDist(loc.distance(from: CLLocation(latitude: saved.place.latitude, longitude: saved.place.longitude))))
                                .font(.caption2.weight(.medium)).foregroundStyle(adaptiveSecondaryInk)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
            }
            Spacer().frame(height: 5)
        }
        .glass(cornerRadius: 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("الأخيرة".loc)
                    .font(.caption.weight(.bold)).foregroundStyle(adaptiveSecondaryInk)
                Spacer()
                Button("مسح الكل".loc) { historyStore.clear() }
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
            ForEach(historyStore.items) { place in
                Button { select(place) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(adaptiveSecondaryInk).font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            if !place.address.isEmpty {
                                Text(place.address).font(.caption2).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let loc = locationService.location {
                            Text(fmtDist(loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))
                                .font(.caption2.weight(.medium)).foregroundStyle(adaptiveSecondaryInk)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
            }
            Spacer().frame(height: 5)
        }
        .glass(cornerRadius: 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var suggestionsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(suggestions) { place in
                    Button { select(place) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(adaptiveInk).font(.system(size: 19))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                let sub = [place.kind, place.address.isEmpty ? nil : place.address].compactMap { $0 }.joined(separator: " • ")
                                if !sub.isEmpty {
                                    Text(sub).font(.caption2).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                                }
                            }
                            Spacer()
                            if let loc = locationService.location {
                                Text(fmtDist(loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))
                                    .font(.caption2.weight(.medium)).foregroundStyle(adaptiveSecondaryInk)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    if place.id != suggestions.last?.id { Divider().opacity(0.35).padding(.leading, 40) }
                }
            }
        }
        .frame(maxHeight: 340)
        .glass(cornerRadius: 22)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var stopsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(.orange)
                ForEach(stops) { stop in
                    HStack(spacing: 4) {
                        Text(stop.name).font(.caption).lineLimit(1)
                        Button { stops.removeAll { $0.id == stop.id }; Task { await computeRoute() } } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(adaptiveSecondaryInk)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .glass(cornerRadius: 12)
                }
                Button("مسح".loc) { stops = []; Task { await computeRoute() } }
                    .font(.caption).foregroundStyle(.red)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Route UI

    private func expectedArrival(_ duration: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == "ku" ? "ckb" : language)
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: Date().addingTimeInterval(duration))
    }

    private func routeBar(_ route: RouteData) -> some View {
        VStack(spacing: verticalSizeClass == .compact ? 6 : 10) {
            Capsule().fill(adaptiveSecondaryInk.opacity(0.34)).frame(width: 38, height: 5)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("إلى".loc + " \(selected?.name ?? "وجهتك".loc)")
                        .font(.caption.weight(.semibold)).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                    Text("الوصول المتوقع".loc)
                        .font(.caption2.weight(.bold)).foregroundStyle(adaptiveSecondaryInk)
                    Text(expectedArrival(route.duration))
                        .font(verticalSizeClass == .compact ? .headline.weight(.heavy) : .title2.weight(.heavy))
                        .foregroundStyle(adaptiveInk)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Button { clearRoute() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(adaptiveSecondaryInk)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Color.white.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("مسح المسار".loc)
            }

            HStack(spacing: 8) {
                Label(fmtDist(route.distance), systemImage: "arrow.left.and.right")
                Circle().fill(adaptiveSecondaryInk.opacity(0.45)).frame(width: 3, height: 3)
                Label(formatDuration(route.duration), systemImage: "clock")
                Spacer(minLength: 4)
                Button {
                    directionsText = makeDirectionsText()
                    showDirections = true
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .background(Color.white.opacity(0.40), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("وصف الوصول".loc)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(adaptiveInk)

            HStack(spacing: 6) {
                ForEach(TransportChoice.allCases) { choice in
                    Button {
                        transport = choice
                        Task { await computeRoute() }
                    } label: {
                        Label(choice.label, systemImage: choice.icon)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(transport == choice ? Color(red: 0.04, green: 0.68, blue: 0.55) : Color.white.opacity(0.38),
                                        in: Capsule())
                            .foregroundStyle(transport == choice ? .white : adaptiveInk)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if routes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(routes.indices, id: \.self) { idx in
                            Button {
                                selectedRouteIndex = idx
                                if voice.active, let place = selected {
                                    let chosen = routes[idx]
                                    voice.start(steps: chosen.steps, destination: place.coordinate,
                                                routeCoordinates: chosen.coordinates)
                                }
                            } label: {
                                Text(idx == 0 ? "الأسرع".loc + ": \(formatDuration(routes[idx].duration))" : "بديل".loc + ": \(formatDuration(routes[idx].duration))")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(idx == selectedRouteIndex ? Color.orange.opacity(0.22) : Color.white.opacity(0.32), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                if let place = selected {
                    followUser = true
                    voice.start(steps: route.steps, destination: place.coordinate,
                                routeCoordinates: route.coordinates)
                }
            } label: {
                Label(voice.active ? "الملاحة نشطة".loc : "انطلق الآن".loc,
                      systemImage: voice.active ? "location.north.fill" : "location.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: verticalSizeClass == .compact ? 46 : 52)
                    .background(LinearGradient(colors: [Color(red: 0.06, green: 0.73, blue: 0.60), Color(red: 0.02, green: 0.62, blue: 0.51)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(voice.active)
            .opacity(voice.active ? 0.78 : 1)

            if !elevations.isEmpty, verticalSizeClass != .compact {
                HStack(spacing: 6) {
                    Image(systemName: "mountain.2").foregroundStyle(adaptiveSecondaryInk)
                    ElevationChart(values: elevations).frame(height: 22)
                    Text("▲ \(Int(elevations.max() ?? 0)) \("م".loc)")
                        .font(.caption2.weight(.medium)).foregroundStyle(adaptiveSecondaryInk)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, verticalSizeClass == .compact ? 7 : 11)
        .padding(.bottom, verticalSizeClass == .compact ? 9 : 14)
        .glass(cornerRadius: 30)
        .shadow(color: Color(red: 0.17, green: 0.40, blue: 0.35).opacity(0.18), radius: 18, y: 8)
    }

    // MARK: - Place card

    /// One uniform action tile for the place card: icon over label,
    /// equal width and geometry for every action (formal, Apple-like).
    private func cardAction(icon: String, label: String, primary: Bool = false,
                            tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(primary ? AnyShapeStyle(Color(red: 0.04, green: 0.68, blue: 0.55)) : AnyShapeStyle(tint ?? Color.white.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func placeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Apple Maps-style grabber: drag the card up for full details.
            HStack { Spacer()
                Capsule().fill(adaptiveSecondaryInk.opacity(0.4)).frame(width: 36, height: 5)
                Spacer() }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(place.name).font(.title3.weight(.bold)).lineLimit(2)
                        if place.id.hasPrefix("official-") {
                            Text("رسمي".loc)
                                .font(.caption2.weight(.black)).foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(red: 0.98, green: 0.75, blue: 0.14), in: Capsule())
                        }
                        if let kind = place.kind {
                            Text(kind)
                                .font(.caption2.weight(.semibold)).foregroundStyle(adaptiveSecondaryInk)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.white.opacity(0.12), in: Capsule())
                        }
                    }
                    if !place.address.isEmpty {
                        Text(place.address).font(.caption).foregroundStyle(adaptiveSecondaryInk).lineLimit(2)
                    }
                    HStack(spacing: 5) {
                        if let loc = locationService.location {
                            let d = loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                            Text("يبعد \(fmtDist(d)) عنك")
                        }
                        if let w = placeWeather {
                            Text("• \(displayTemp(w.temperature)) \(w.label)")
                        }
                    }
                    .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                }
                Spacer()
                Button { self.selected = nil } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12), in: Circle())
                        .foregroundStyle(adaptiveSecondaryInk)
                }
            }
            HStack(spacing: 7) {
                cardAction(icon: "arrow.triangle.turn.up.right.diamond.fill",
                           label: loadingRoute ? "…" : "الاتجاهات".loc, primary: true) {
                    Task { await computeRoute() }
                }
                cardAction(icon: store.contains(place) ? "bookmark.fill" : "bookmark",
                           label: store.contains(place) ? "محفوظ".loc : "حفظ".loc) {
                    let added = store.toggle(place)
                    if added { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
                if !place.id.hasPrefix("community-"), !place.id.hasPrefix("official-") {
                    cardAction(icon: "mappin.and.ellipse", label: "نشر محلي".loc,
                               tint: Color.purple.opacity(0.25)) {
                        publishPlace = place
                    }
                }
                cardAction(icon: "flag", label: "توقف".loc) { stops.append(place) }
                cardAction(icon: "square.and.arrow.up", label: "مشاركة".loc) {
                    shareItem = SharePayload(text: "\(place.name)\n\(place.mapsLink.absoluteString)")
                }
            }
            if let phone = place.phone, let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) {
                    Label(phone, systemImage: "phone.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 11))
                }
            }
            if placeSheetFull {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 8) {
                    if let photo = placeDetails?.photoURL {
                        AsyncImage(url: photo) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { adaptiveSecondaryInk.opacity(0.15) }
                        .frame(height: 130).frame(maxWidth: .infinity)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let d = placeDetails {
                        if let hours = d.openingHours {
                            HStack(spacing: 6) {
                                Circle().fill(d.isOpenNow == true ? Color.green : (d.isOpenNow == false ? Color.red : adaptiveSecondaryInk))
                                    .frame(width: 8, height: 8)
                                Text(d.isOpenNow == true ? "مفتوح الآن".loc : (d.isOpenNow == false ? "مغلق الآن".loc : "ساعات الدوام".loc))
                                    .font(.caption.weight(.semibold))
                                Text(hours).font(.caption2).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                            }
                        }
                        if let phone = d.phone, let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                            Link(destination: url) {
                                Label(phone, systemImage: "phone.fill").font(.caption.weight(.medium))
                            }
                        }
                        if let site = d.website, let url = URL(string: site.hasPrefix("http") ? site : "https://\(site)") {
                            Link(destination: url) {
                                Label("الموقع الإلكتروني".loc, systemImage: "globe").font(.caption.weight(.medium))
                            }
                        }
                    }
                    if !place.address.isEmpty {
                        Label(place.address, systemImage: "signpost.right.and.left")
                            .font(.caption).foregroundStyle(adaptiveSecondaryInk)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "location.viewfinder").font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                        Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                            .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = String(format: "%.5f, %.5f", place.latitude, place.longitude)
                        } label: {
                            Label("نسخ الإحداثيات".loc, systemImage: "doc.on.doc")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    Link(destination: place.mapsLink) {
                        Label("فتح في خرائط آبل".loc, systemImage: "map")
                            .font(.caption.weight(.medium))
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .glass(cornerRadius: 20)
        .offset(y: placeSheetDragY)
        .blur(radius: min(abs(placeSheetVelocity) / 500, 5))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: placeSheetFull)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    let now = Date()
                    if let last = dragLastTime {
                        let dt = max(now.timeIntervalSince(last), 0.016)
                        placeSheetVelocity = (v.translation.height - dragPrevY) / CGFloat(dt)
                    }
                    dragLastTime = now
                    dragPrevY = v.translation.height
                    placeSheetDragY = placeSheetFull
                        ? max(0, min(v.translation.height, 240))
                        : min(0, max(v.translation.height, -240))
                }
                .onEnded { v in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if placeSheetFull {
                            if v.translation.height > 60 { placeSheetFull = false }
                        } else if v.translation.height < -60 {
                            placeSheetFull = true
                        }
                        placeSheetDragY = 0
                    }
                    placeSheetVelocity = 0
                    dragLastTime = nil
                }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: place.id) {
            placeDetails = nil
            placeWeather = await GeoService.weather(lat: place.latitude, lon: place.longitude)
            placeDetails = await GeoService.details(for: place)
        }
    }

    /// Human, landmark-based arrival description for the current route —
    /// the way Iraqis actually give directions ("بجانب الجامع…"). The text
    /// can be shared to anyone, even without the app.
    private func makeDirectionsText() -> String {
        guard let route = selectedRoute, let dest = selected else { return "" }
        var lines = ["\("الطريق إلى".loc) \(dest.name):"]
        var n = 0
        for step in route.steps where step.distance > 15 {
            n += 1
            lines.append("\(n). \(step.instruction) (\(fmtDist(step.distance)))")
        }
        lines.append("\("المسافة الكلية".loc): \(fmtDist(route.distance)) • \("الوقت التقريبي".loc): \(formatDuration(route.duration))")
        lines.append("— \("وجهتي".loc)")
        return lines.joined(separator: "\n")
    }

    private var directionsSheet: some View {
        NavigationStack {
            ScrollView {
                Text(directionsText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .textSelection(.enabled)
            }
            .navigationTitle("وصف الوصول".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: directionsText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق".loc) { showDirections = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Pocket overlay

    private var pocketOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: voice.arrived ? "flag.checkered" : "location.north.line.fill")
                    .font(.system(size: 64)).foregroundStyle(.blue)
                Text(voice.currentInstruction).font(.title3.weight(.bold))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding(.horizontal, 24)
                if !voice.arrived {
                    Text(fmtDist(voice.distanceToNext)).font(.headline).foregroundStyle(.gray)
                }
                if transport == .walking && !voice.arrived {
                    Button { showAR = true } label: {
                        Label("ملاحة بالكاميرا".loc, systemImage: "camera.viewfinder")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Color.blue, in: Capsule())
                    }
                }
                Button { voice.stop(); followUser = false } label: {
                    Text("إيقاف الملاحة".loc)
                        .font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 26).padding(.vertical, 13)
                        .background(Color.red, in: Capsule())
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Sheets

    private var savedSheet: some View {
        NavigationStack {
            List {
                Section("أماكن سريعة".loc) {
                    quickPlaceRow(title: "البيت".loc, icon: "house.fill", place: homePlace, key: "wijhati.homePlace", isHome: true)
                    quickPlaceRow(title: "الشغل".loc, icon: "briefcase.fill", place: workPlace, key: "wijhati.workPlace", isHome: false)
                }
                if store.places.isEmpty {
                    Text("لا توجد أماكن محفوظة بعد".loc).foregroundStyle(adaptiveSecondaryInk)
                }
                ForEach(store.places) { saved in
                    Button {
                        showSaved = false
                        select(saved.place)
                    } label: {
                        HStack {
                            Image(systemName: saved.isFavorite ? "star.fill" : "mappin.circle.fill")
                                .foregroundStyle(saved.isFavorite ? .yellow : adaptiveInk)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(saved.place.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                if !saved.place.address.isEmpty {
                                    Text(saved.place.address).font(.caption2).foregroundStyle(adaptiveSecondaryInk).lineLimit(1)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { store.setFavorite(saved, !saved.isFavorite) } label: {
                            Label("مفضلة".loc, systemImage: "star")
                        }.tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.remove(saved) } label: {
                            Label("حذف".loc, systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("أماكني المحفوظة".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let data = store.exportJSON(), let text = String(data: data, encoding: .utf8) {
                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("إغلاق".loc) { showSaved = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("الخريطة والمظهر".loc) {
                    Picker("المظهر".loc, selection: $appearance) {
                        Text("الوضع العادي".loc).tag("light")
                        Text("تلقائي".loc).tag("auto")
                        Text("الوضع الداكن".loc).tag("dark")
                    }
                    .pickerStyle(.segmented)
                    NavigationLink {
                        mapSettingsPage
                    } label: {
                        Label("الخريطة".loc, systemImage: "map.fill")
                    }
                }
                Section("الملاحة".loc) {
                    NavigationLink {
                        navigationSettingsPage
                    } label: {
                        Label("الملاحة والصوت".loc, systemImage: "waveform")
                    }
                }
                Section("اللغة والوحدات".loc) {
                    Picker("اللغة".loc, selection: $language) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                        Text("کوردی").tag("ku")
                    }
                    .pickerStyle(.menu)
                    Picker("وحدة الحرارة".loc, selection: $tempUnit) {
                        Text("سيليزية °C".loc).tag("c")
                        Text("فهرنهايت °F".loc).tag("f")
                    }
                    .pickerStyle(.menu)
                    Picker("وحدة المسافة".loc, selection: $distanceUnit) {
                        Text("كيلومتر".loc).tag("km")
                        Text("ميل".loc).tag("mi")
                        Text("تلقائي".loc).tag("auto")
                    }
                    .pickerStyle(.menu)
                }
                Section("أماكن سريعة".loc) {
                    quickPlaceRow(title: "البيت".loc, icon: "house.fill", place: homePlace,
                                  key: "wijhati.homePlace", isHome: true, dismissSettings: true)
                    quickPlaceRow(title: "الشغل".loc, icon: "briefcase.fill", place: workPlace,
                                  key: "wijhati.workPlace", isHome: false, dismissSettings: true)
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { showSaved = true }
                    } label: {
                        Label("أماكني المحفوظة".loc, systemImage: "bookmark.fill")
                    }
                }
                Section("الوصول والبيانات".loc) {
                    NavigationLink {
                        offlinePage
                    } label: {
                        Label("خرائط بدون إنترنت".loc, systemImage: "arrow.down.circle.fill")
                    }
                    NavigationLink {
                        locationSettingsPage
                    } label: {
                        Label("الموقع".loc, systemImage: "location.fill")
                    }
                }
                Section("مساعدة وملاحظات".loc) {
                    NavigationLink {
                        helpPage
                    } label: {
                        Label("مساعدة وملاحظات".loc, systemImage: "questionmark.circle.fill")
                    }
                    NavigationLink {
                        aboutPage
                    } label: {
                        Label("حول وجهتي".loc, systemImage: "info.circle.fill")
                    }
                }
            }
            .navigationTitle("الإعدادات".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق".loc) { showSettings = false } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(schemeOverride)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
    }

    private var mapSettingsPage: some View {
        Form {
            Section("طبقات".loc) {
                Picker("النمط".loc, selection: $styleKind) {
                    ForEach(MapStyleKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                Toggle("أبنية ثلاثية الأبعاد".loc, isOn: $show3D)
                Toggle("الطبقة الرسمية".loc, isOn: $officialEnabled)
            }
            Section("شفافية الواجهة".loc) {
                Picker("شفافية الواجهة".loc, selection: glassPresetBinding) {
                    Text("مصمت".loc).tag(0.0)
                    Text("متوازن".loc).tag(0.53)
                    Text("زجاجي".loc).tag(1.0)
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("الخريطة".loc)
        .navigationBarTitleDisplayMode(.inline)
    }


    private var helpPage: some View {
        List {
            Section("تعليمات الاستخدام".loc) {
                Label("ابحث عن أي مكان من شريط البحث — الاقتراحات تظهر ويا المسافة لكل نتيجة".loc, systemImage: "magnifyingglass")
                Label("اضغط مطوّلاً على أي نقطة بالخريطة حتى يثبت دبوس وتطلع بطاقة المكان".loc, systemImage: "mappin.and.ellipse")
                Label("اسحب بطاقة المكان للأعلى حتى تشوف العنوان الكامل والإحداثيات".loc, systemImage: "square.and.arrow.up.on.square")
                Label("زر الموقع: ضغطة واحدة تقرّب الكاميرا على موقعك الحالي".loc, systemImage: "location.fill")
                Label("من الإعدادات ← «الخريطة» اختَر شفافية الواجهة: مصمت، متوازن، أو زجاجي".loc, systemImage: "slider.horizontal.3")
                Label("بعد رسم المسار اضغط «جيب» للملاحة الصوتية وهاتفك بجيبك، وبالمشي جرّب «ملاحة بالكاميرا»".loc, systemImage: "waveform")
                Label("ثبّت بيتك وشغلك من «أماكني المحفوظة» وضيف ودجت وجهتي لشاشتك حتى توصل بضغطة".loc, systemImage: "house.fill")
                Label("تُدار خرائط Apple دون اتصال من تطبيق خرائط Apple؛ افتح صفحة «خرائط بدون إنترنت» للمزيد".loc, systemImage: "arrow.down.circle")
            }
            Section("أسئلة شائعة".loc) {
                DisclosureGroup("ليش بعض أسماء الأماكن خطأ أو ناقصة؟".loc) {
                    Text("تعرض خريطة Apple بيانات Apple؛ أما البحث وبعض بيانات الأماكن والمسارات في وجهتي فتأتي من مزودين خارجيين وقد تختلف الأسماء والتغطية.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
                DisclosureGroup("شلون أبدّل نمط الخريطة؟".loc) {
                    Text("من الإعدادات ← «الخريطة» اختَر الخريطة القياسية أو الهادئة أو القمر الصناعي أو الهجينة؛ ويمكن تفعيل عرض التضاريس ثلاثي الأبعاد الواقعي.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
                DisclosureGroup("هل يشتغل التطبيق بدون إنترنت؟".loc) {
                    Text("إدارة خرائط Apple دون اتصال تتم في تطبيق خرائط Apple والنظام؛ لا يتيح MapKit تنزيل أو إدارة مناطق خرائط من داخل وجهتي. البحث وحساب المسارات والطقس تحتاج اتصالاً.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
                DisclosureGroup("شلون أضيف مكاناً مو موجود بالخريطة؟".loc) {
                    Text("افتح أي مكان قريب واضغط «نشر محلي» من بطاقته، أو ثبّت دبوساً بضغطة مطوّلة وانشر المكان من بطاقته — يظهر عندك وبالمجتمع.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
                DisclosureGroup("شلون أوصل للبيت أو الشغل بسرعة؟".loc) {
                    Text("ثبّتهما أول مرة من «أماكني المحفوظة» ← البيت/الشغل، وبعدها الاتجاهات بضغطة وحدة من نفس الصفحة أو من ودجت الشاشة الرئيسية.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
                DisclosureGroup("ليش ما تغيّر وقت المسار بين السيارة والمشي؟".loc) {
                    Text("كل نمط يُحسب من خادم مختلف. إذا تعذّر حساب نمط معيّن يطلع لك تنبيه برتقالي — تأكد من اتصالك وجرّب مرة ثانية.".loc)
                        .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                }
            }
            Section("تواصل ومشاركة".loc) {
                Link(destination: URL(string: "mailto:id9871456@gmail.com?subject=" + ("ملاحظات وجهتي".loc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))!) {
                    Label("إرسال ملاحظات للمطوّر".loc, systemImage: "envelope.fill")
                }
                ShareLink(item: "جرّب تطبيق وجهتي — خرائط وملاحة عربية أنيقة".loc) {
                    Label("مشاركة التطبيق مع صديق".loc, systemImage: "square.and.arrow.up")
                }
            }
            Section {
                VStack(spacing: 4) {
                    Text("من تطوير".loc)
                        .font(.caption).foregroundStyle(adaptiveSecondaryInk)
                    Text("عبدالباسط خضير".loc)
                        .font(.headline)
                    Text("© 2026 عبدالباسط خضير — جميع الحقوق محفوظة".loc)
                        .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("مساعدة وملاحظات".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var aboutPage: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 54)).foregroundStyle(.pink)
                        Text("وجهتي — Wijhati").font(.title3.weight(.bold))
                        Text("خرائط وملاحة عربية للعالم كله".loc).font(.caption).foregroundStyle(adaptiveSecondaryInk)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                HStack { Text("الإصدار".loc); Spacer(); Text("1.65.0").foregroundStyle(adaptiveSecondaryInk) }
                HStack { Text("المطوّر".loc); Spacer(); Text("عبدالباسط خضير".loc).foregroundStyle(adaptiveSecondaryInk) }
                Text("خرائط Apple • يظهر إسناد Apple الأصلي على الخريطة".loc)
                    .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                Text("حدود فلترة الأماكن الرسمية من Natural Earth (بيانات مفتوحة)")
                    .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                HStack { Text("المحرك".loc); Spacer(); Text("MapKit").foregroundStyle(adaptiveSecondaryInk) }
                MapHealthStatusRow()
                HStack { Text("مؤثرات بصرية".loc); Spacer(); Text("مستوحاة من مشاريع rit3zh (MIT)".loc).font(.caption2).foregroundStyle(adaptiveSecondaryInk) }
            }
            Section {
                Text("وجهتي تطبيق خرائط عالمي بواجهة عربية زجاجية أنيقة: بحث فوري، مسارات بديلة، أنماط خرائط متعددة، أبنية ثلاثية الأبعاد، وملاحة صوتية تعمل والهاتف في جيبك.".loc)
                    .font(.callout).foregroundStyle(adaptiveSecondaryInk)
            }
        }
        .navigationTitle("حول وجهتي".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mapAttributionText: String {
        "خرائط Apple © Apple".loc
    }

    private var mapAttributionSheet: some View {
        NavigationStack {
            List {
                Section("بيانات الخريطة".loc) {
                    Text(mapAttributionText)
                    Text("يظهر إسناد Apple المعتمد مباشرةً على الخريطة.".loc)
                    Text("MapKit")
                        .font(.caption)
                        .foregroundStyle(adaptiveSecondaryInk)
                }
            }
            .navigationTitle("إسناد الخريطة".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إغلاق".loc) { showMapAttribution = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Offline page

    private var offlinePage: some View {
        List {
            Section {
                Text("إدارة خرائط Apple دون اتصال تتم في تطبيق خرائط Apple والنظام؛ لا يتيح MapKit تنزيل أو إدارة مناطق خرائط من داخل وجهتي.".loc)
                    .font(.callout).foregroundStyle(adaptiveSecondaryInk)
                Link(destination: URL(string: "https://maps.apple.com/")!) {
                    Label("فتح في خرائط آبل".loc, systemImage: "map.fill")
                }
            }
            Section {
                Text("البحث وحساب المسارات والطقس في وجهتي تحتاج اتصالاً بالإنترنت.".loc)
                    .font(.caption).foregroundStyle(adaptiveSecondaryInk)
            }
        }
        .navigationTitle("خرائط بدون إنترنت".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationSettingsPage: some View {
        Form {
            Section("موقعك الحالي".loc) {
                if let loc = locationService.location {
                    HStack { Text("خط العرض".loc); Spacer(); Text(String(format: "%.5f", loc.coordinate.latitude)).foregroundStyle(adaptiveSecondaryInk) }
                    HStack { Text("خط الطول".loc); Spacer(); Text(String(format: "%.5f", loc.coordinate.longitude)).foregroundStyle(adaptiveSecondaryInk) }
                    HStack { Text("الدقة".loc); Spacer(); Text("\(Int(loc.horizontalAccuracy)) م").foregroundStyle(adaptiveSecondaryInk) }
                } else {
                    Text("فعّل خدمات الموقع حتى يظهر موقعك هنا".loc)
                        .foregroundStyle(adaptiveSecondaryInk)
                }
            }
            Section {
                Button {
                    if let c = locationService.location?.coordinate {
                        centerRequest = CenterRequest(coordinate: c, zoom: 15)
                    }
                    showSettings = false
                } label: {
                    Label("ركّز الخريطة على موقعي".loc, systemImage: "location.fill")
                }
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("فتح إعدادات موقع النظام".loc, systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("الموقع".loc)
        .navigationBarTitleDisplayMode(.inline)
    }


    private func qualityLabel(_ q: Int) -> String {
        switch q {
        case 3: return "ممتازة".loc
        case 2: return "محسّنة".loc
        default: return "عادية".loc
        }
    }

    private var voicePickerPage: some View {
        Form {
            Section {
                Text("صوت الآيفون هو الافتراضي ويعمل دون مفتاح أو إعداد إضافي.".loc)
                    .font(.callout).foregroundStyle(adaptiveSecondaryInk)
            }
            Section("صوت الجهاز".loc) {
                if VoiceGuide.arabicVoiceInfos.isEmpty {
                    Text("لا توجد أصوات عربية مثبتة؛ نزّل صوتاً عربياً من إعدادات الآيفون.".loc)
                        .font(.caption).foregroundStyle(adaptiveSecondaryInk)
                } else {
                    ForEach(VoiceGuide.arabicVoiceInfos, id: \.id) { info in
                        Button {
                            voiceID = info.id
                            voice.preview(voiceID: info.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name)
                                    Text("\(info.language) • \(qualityLabel(info.quality))")
                                        .font(.caption).foregroundStyle(adaptiveSecondaryInk)
                                }
                                Spacer()
                                if voiceID == info.id {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            Section("أسلوب الصوت".loc) {
                ForEach(VoiceGuide.styles, id: \.id) { style in
                    Button {
                        voiceStyle = style.id
                        voice.previewStyle(style)
                    } label: {
                        HStack {
                            Text(style.name.loc)
                            Spacer()
                            if voiceStyle == style.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                DisclosureGroup("أصوات سحابية اختيارية".loc) {
                    ForEach(CloudVoice.voices, id: \.name) { option in
                        Button {
                            azureVoice = option.name
                            if CloudVoice.configured {
                                CloudVoice.shared.preview(voiceName: option.name)
                            } else {
                                azureKeyStatus = "أضف مفتاح Azure فقط إذا أردت تجربة الصوت السحابي.".loc
                            }
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                if azureVoice == option.name {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    SecureField("مفتاح Azure".loc, text: $azureKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    TextField("المنطقة (Region)".loc, text: $azureRegion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("حفظ".loc) {
                            let saved = CloudVoice.storeKey(azureKeyInput)
                            azureKeyInput = ""
                            azureKeyStatus = saved ? "تم حفظ المفتاح بأمان على هذا الجهاز".loc : "تعذر حفظ المفتاح؛ حاول مرة أخرى".loc
                        }
                        .disabled(azureKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if CloudVoice.configured {
                            Button("حذف".loc, role: .destructive) {
                                _ = CloudVoice.storeKey("")
                                azureKeyInput = ""
                                azureKeyStatus = "تم حذف المفتاح؛ سيعمل صوت الجهاز".loc
                            }
                        }
                    }
                    if !azureKeyStatus.isEmpty {
                        Text(azureKeyStatus).font(.caption).foregroundStyle(adaptiveSecondaryInk)
                    }
                    Text(CloudVoice.configured
                         ? "المفتاح محفوظ؛ جرّب معاينة الصوت العراقي أعلاه".loc
                         : (CloudVoice.key.isEmpty
                            ? "لا يوجد مفتاح محفوظ؛ الملاحة الصوتية تستخدم صوت الجهاز".loc
                            : "منطقة Azure غير صالحة؛ تحقق من قيمة Region".loc))
                        .font(.caption2).foregroundStyle(adaptiveSecondaryInk)
                }
            } header: {
                Text("صوت إضافي".loc)
            } footer: {
                Text("الأصوات العراقية السحابية اختيارية وتحتاج مفتاحك من Azure؛ من دون مفتاح يعمل صوت الجهاز محلياً. مفتاحك يُحفظ في Keychain على هذا الجهاز.".loc)
                    .font(.caption2)
            }
            Section {
                Text("لأصوات عربية إضافية بجودة أعلى، حمّلها من إعدادات الآيفون ← إمكانية الوصول ← المحتوى المنطوق ← الأصوات ← العربية، وستظهر هنا تلقائياً.".loc)
                    .font(.caption).foregroundStyle(adaptiveSecondaryInk)
            }
        }
        .navigationTitle("اختيار الصوت".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationSettingsPage: some View {
        Form {
            Section {
                Toggle("التنبيهات".loc, isOn: $notifMaster)
                    .onChange(of: notifMaster) { _, on in if on { Notify.requestPermission() } }
                Toggle("تنبيه عند الاقتراب".loc, isOn: $notifSaved)
                    .onChange(of: notifSaved) { _, on in if on { Notify.requestPermission() } }
                    .disabled(!notifMaster)
            }
            Section("صوت المرشد".loc) {
                DeferredSettingsSliderRow(
                    title: "صوت المرشد".loc,
                    value: $voiceVolume,
                    range: 0...1,
                    formattedValue: { "\(Int($0 * 100))٪" },
                    onCommit: { voice.announce("صوت المرشد".loc) }
                )
            }
            Section {
                NavigationLink {
                    voicePickerPage
                } label: {
                    Label("اختيار الصوت".loc, systemImage: "person.wave.2.fill")
                }
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("فتح إعدادات التطبيق".loc, systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("الملاحة والصوت".loc)
        .navigationBarTitleDisplayMode(.inline)
    }






    /// SwiftUI's layoutDirection environment alone did not flip lists on
    /// the user's iOS 27 build, so force it at the UIKit level too (the
    /// collection views under List/Form obey semanticContentAttribute),
    /// while the map view itself stays mounted to preserve its state.
    private func applySemanticDirection() {
        let attr: UISemanticContentAttribute = language == "en" ? .forceLeftToRight : .forceRightToLeft
        UIView.appearance().semanticContentAttribute = attr
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.semanticContentAttribute = attr
                window.rootViewController?.view.semanticContentAttribute = attr
                window.rootViewController?.view.setNeedsLayout()
                window.rootViewController?.view.layoutIfNeeded()
            }
        }
    }

    private func checkProximity(_ loc: CLLocation) {
        guard notifMaster else { return }
        let now = Date()
        func cooling(_ key: String) -> Bool {
            if let last = alertCooldown[key], now.timeIntervalSince(last) < 900 { return true }
            alertCooldown[key] = now
            return false
        }
        if notifSaved {
            for saved in store.places {
                let d = loc.distance(from: CLLocation(latitude: saved.place.latitude, longitude: saved.place.longitude))
                if d < 50, !cooling("saved-\(saved.place.id)") {
                    voice.announce("اقتربت من مكانك المحفوظ: \(saved.place.name)")
                    Notify.fire(title: "وجهتي — مكان محفوظ".loc,
                                body: "\("اقتربت من مكانك المحفوظ".loc): \(saved.place.name)",
                                symbol: "bookmark.fill",
                                tone: .success)
                }
            }
        }
    }

    // MARK: - Actions

    private func showLocationNotice(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) { locationNotice = message }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if locationNotice == message {
                withAnimation(.easeInOut(duration: 0.18)) { locationNotice = nil }
            }
        }
    }

    private func scheduleLocationWaitTimeout(forStartup: Bool) {
        locationWaitGeneration += 1
        let generation = locationWaitGeneration
        let timeoutSeconds: UInt64 = forStartup ? 20 : 12
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            guard locationWaitGeneration == generation else { return }
            if forStartup {
                guard pendingInitialLocationCenter else { return }
                pendingInitialLocationCenter = false
            } else {
                guard pendingCenterOnUser else { return }
                pendingCenterOnUser = false
            }
            showLocationNotice("تعذر تحديد موقعك الآن. تحقق من خدمات الموقع وحاول مرة أخرى.".loc)
        }
    }

    private func cancelLocationWaitTimeout() {
        locationWaitGeneration += 1
    }

    private func centerOnMyLocation(requestFreshFix: Bool = false) {
        if showSearch { closeMapSearch() }
        pendingInitialLocationCenter = false
        cancelLocationWaitTimeout()
        UISelectionFeedbackGenerator().selectionChanged()
        if locationService.authorization == .denied || locationService.authorization == .restricted {
            pendingCenterOnUser = true
            showLocationNotice("اسمح بالوصول إلى الموقع من إعدادات الآيفون.".loc)
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
            return
        }
        guard let loc = locationService.location else {
            pendingCenterOnUser = true
            showLocationNotice("جارٍ تحديد موقعك…".loc)
            locationService.requestCurrentLocation()
            if locationAuthorized { scheduleLocationWaitTimeout(forStartup: false) }
            return
        }
        pendingCenterOnUser = false
        locationNotice = nil
        centerMapOnUser(loc)
        let locationIsStale = abs(Date().timeIntervalSince(loc.timestamp)) > 30
        if requestFreshFix || locationIsStale {
            locationService.requestCurrentLocation()
        }
        if locationIsStale {
            pendingCenterOnUser = true
            showLocationNotice("جارٍ تحديث موقعك…".loc)
            if locationAuthorized { scheduleLocationWaitTimeout(forStartup: false) }
        }
    }

    private func centerMapOnUser(_ loc: CLLocation) {
        followUser = voice.active
        centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
    }

    private func centerAtStartupIfNeeded(_ loc: CLLocation, resolvesInitialFix: Bool = true) {
        guard pendingInitialLocationCenter, loc.horizontalAccuracy >= 0 else { return }
        if lastStartupCenterTimestamp != loc.timestamp {
            lastStartupCenterTimestamp = loc.timestamp
            centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
        }
        let age = Date().timeIntervalSince(loc.timestamp)
        if resolvesInitialFix && age >= -30 && age <= 30 {
            pendingInitialLocationCenter = false
            cancelLocationWaitTimeout()
        }
    }

    private func openQuickPlace(_ place: Place) {
        showIntro = false
        select(place)
        if locationService.location != nil {
            Task { await computeRoute() }
        } else {
            pendingQuickRoute = true
        }
    }

    private func select(_ place: Place, preservingSearchRequest: Bool = false) {
        if !preservingSearchRequest { invalidateSearchRequests() }
        pendingQuickRoute = false
        routeFailed = false
        pendingInitialLocationCenter = false
        let selectedFromSearch = showSearch || !suggestions.isEmpty || searchPins.contains(where: { $0.id == place.id })
        if selectedFromSearch {
            historyStore.add(place)
            query = ""
        }
        if selected?.id != place.id {
            // Invalidate any in-flight route for the previous destination.
            // Otherwise its delayed network response can redraw a stale route.
            routeGeneration += 1
            loadingRoute = false
            routes = []
            selectedRouteIndex = 0
            elevations = []
            offRouteCount = 0
            voice.stop()
        }
        showSearch = false
        routeNotice = nil
        placeSheetFull = false
        placeSheetDragY = 0
        selected = place
        suggestions = []
        if !pins.contains(place) { pins = [place] }
        centerRequest = CenterRequest(coordinate: place.coordinate, zoom: 15)
        followUser = false
    }

    private func handleLongPress(_ coordinate: CLLocationCoordinate2D) {
        let temp = Place.make(name: "موقع مُحدد".loc,
                               address: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
                               lat: coordinate.latitude, lon: coordinate.longitude)
        select(temp)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            if let resolved = await GeoService.reverse(lat: coordinate.latitude, lon: coordinate.longitude),
               selected?.id == temp.id {
                select(resolved)
            }
        }
    }

    private func cancelSuggestionSearch() {
        suggestTask?.cancel()
        suggestTask = nil
        suggestionSearching = false
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchGeneration += 1
        let generation = searchGeneration
        searching = true
        let results = await GeoService.search(text, near: locationService.location?.coordinate)
        guard generation == searchGeneration else { return }
        searching = false
        pins = results
        searchPins = results
        suggestions = []
        if let first = results.first {
            select(first, preservingSearchRequest: true)
            pins = results
        }
    }

    private func computeRoute(announceRecalculation: Bool = false) async {
        guard let dest = selected else { return }
        routeGeneration += 1
        let gen = routeGeneration
        let resumeVoiceAfterRecalculation = voice.active
        voice.stop()
        routes = []
        selectedRouteIndex = 0
        elevations = []
        offRouteCount = 0
        routeNotice = nil
        routeFailed = false
        loadingRoute = false

        guard let currentLocation = locationService.location else {
            routeFailed = true
            routeNotice = "بانتظار تحديد موقعك. فعّل إذن الموقع ثم أعد المحاولة.".loc
            locationService.request()
            return
        }
        let locationAge = Date().timeIntervalSince(currentLocation.timestamp)
        guard currentLocation.horizontalAccuracy >= 0,
              currentLocation.horizontalAccuracy <= 100,
              locationAge >= -5, locationAge <= 45 else {
            routeFailed = true
            routeNotice = "موقعك غير دقيق بعد؛ انتظر تثبيت GPS ثم أعد المحاولة.".loc
            locationService.request()
            return
        }

        let origin = currentLocation.coordinate
        lastRouteAt = Date()
        loadingRoute = true
        let result = await GeoService.route(from: origin, waypoints: stops.map { $0.coordinate },
                                            to: dest.coordinate, profile: transport.osrmProfile)
        guard gen == routeGeneration else { return }
        loadingRoute = false
        if result.isEmpty {
            routeFailed = true
            routeNotice = "\("تعذّر حساب مسار".loc) \(transport.label) \("لهذه الوجهة — جرّب وسيلة أخرى أو وجهة أقرب".loc)"
            if announceRecalculation && resumeVoiceAfterRecalculation {
                voice.announce("تعذّر تحديث المسار؛ انتبه للطريق واتبع الخريطة.".loc)
            }
            return
        }
        // Show the routes immediately; landmark-enriched copies replace
        // them when the (slower) Overpass pass returns.
        routes = result
        selectedRouteIndex = 0
        let enriched = await GeoService.enrichRoutes(result)
        guard gen == routeGeneration else { return }
        routes = enriched.isEmpty ? result : enriched
        if let first = result.first {
            let els = await GeoService.elevations(for: first.coordinates)
            guard gen == routeGeneration else { return }
            elevations = els
        }
        if resumeVoiceAfterRecalculation, let place = selected, let newRoute = routes.first {
            voice.start(steps: newRoute.steps, destination: place.coordinate,
                        routeCoordinates: newRoute.coordinates)
            followUser = true
            if announceRecalculation {
                voice.announce("تم تحديث المسار بعد خروجك عن الطريق.".loc)
            }
        }
    }

    /// Auto-reroute: while a route is shown, watch the distance to its
    /// line; three consecutive fixes 75 m+ away mean the user left the
    /// route — recompute from the current position (20 s grace after any
    /// computation so a fresh route never instantly re-triggers).
    private func checkOffRoute(_ loc: CLLocation) {
        guard let route = selectedRoute, route.coordinates.count > 1,
              !loadingRoute, selected != nil else { return }
        guard Date().timeIntervalSince(lastRouteAt) > 20 else { return }
        if let dest = selected,
           loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)) < 40 { return }
        let coords = route.coordinates
        var best = Double.greatestFiniteMagnitude
        for (a, b) in zip(coords, coords.dropFirst()) {
            best = min(best, distanceFromRoutePoint(loc.coordinate, toSegmentFrom: a, to: b))
        }
        if best > 75 { offRouteCount += 1 } else { offRouteCount = 0 }
        if offRouteCount >= 3 {
            offRouteCount = 0
            Task { await computeRoute(announceRecalculation: true) }
        }
    }

    private func distanceFromRoutePoint(_ point: CLLocationCoordinate2D,
                                        toSegmentFrom a: CLLocationCoordinate2D,
                                        to b: CLLocationCoordinate2D) -> Double {
        let scaleY = 111_320.0
        let scaleX = scaleY * cos(point.latitude * .pi / 180)
        let ax = (a.longitude - point.longitude) * scaleX
        let ay = (a.latitude - point.latitude) * scaleY
        let bx = (b.longitude - point.longitude) * scaleX
        let by = (b.latitude - point.latitude) * scaleY
        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        let fraction = lengthSquared > 0
            ? min(1, max(0, -(ax * dx + ay * dy) / lengthSquared))
            : 0
        return hypot(ax + fraction * dx, ay + fraction * dy)
    }

    private func clearRoute() {
        // A route request may still be waiting on the routing service.
        // Incrementing the generation prevents that response from reviving
        // the route after the user explicitly cleared it.
        routeGeneration += 1
        loadingRoute = false
        offRouteCount = 0
        routeFailed = false
        routeNotice = nil
        routes = []
        elevations = []
        voice.stop()
        followUser = false
    }

}

struct ElevationChart: View {
    var values: [Double]
    var body: some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 1)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height - CGFloat((v - minV) / range) * (geo.size.height - 4) - 2
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.teal, lineWidth: 1.6)
        }
    }
}

struct SharePayload: Identifiable {
    var id = UUID()
    var text: String
}

struct ShareSheet: UIViewControllerRepresentable {
    var text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Morph-symbol launch intro (native take on expo-ios-morph-symbol)

// MARK: - Quick places (home / work) + local search matches
extension ContentView {
    static func loadQuickPlace(_ key: String) -> Place? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }
    func saveQuickPlace(_ place: Place?, key: String, isHome: Bool) {
        if isHome { homePlace = place } else { workPlace = place }
        if let place, let data = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        syncWidgetPlaces()
    }
    func syncWidgetPlaces() {
        guard let shared = UserDefaults(suiteName: "group.com.hggdet.wijhati") else { return }
        var changed = false
        for (place, k) in [(homePlace, "home"), (workPlace, "work")] {
            let existing = shared.dictionary(forKey: k)
            let matches: Bool
            if let place {
                matches = (existing?["name"] as? String) == place.name
                    && abs((existing?["lat"] as? Double ?? .greatestFiniteMagnitude) - place.latitude) < 0.0000001
                    && abs((existing?["lon"] as? Double ?? .greatestFiniteMagnitude) - place.longitude) < 0.0000001
                if !matches {
                    shared.set(["name": place.name, "lat": place.latitude, "lon": place.longitude], forKey: k)
                }
            } else {
                matches = existing == nil
                if !matches { shared.removeObject(forKey: k) }
            }
            changed = changed || !matches
        }
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: "WijhatiQuick")
        }
    }
    func localMatches(for query: String) -> [Place] {
        let q = GeoService.normalizeArabic(query)
        guard q.count >= 2 else { return [] }
        let candidates = store.places.map { $0.place } + community.allPlaces.map { $0.asPlace() } + historyStore.items
        var out: [Place] = []
        for place in candidates {
            let fields = [place.name, place.address, place.kind ?? ""]
            guard fields.contains(where: { GeoService.normalizeArabic($0).contains(q) }),
                  !out.contains(where: { $0.id == place.id }) else { continue }
            out.append(place)
        }
        for place in official.matches(q) where !out.contains(where: { $0.id == place.id }) {
            out.append(place)
        }
        return Array(out.prefix(4))
    }
    @ViewBuilder
    func quickPlaceRow(title: String, icon: String, place: Place?, key: String,
                       isHome: Bool, dismissSettings: Bool = false) -> some View {
        if let place {
            HStack {
                Image(systemName: icon).foregroundStyle(adaptiveInk)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(adaptiveSecondaryInk)
                    Text(place.name).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Spacer()
                Button("اتجاهات".loc) {
                    if dismissSettings { showSettings = false }
                    showSaved = false
                    select(place)
                    Task { await computeRoute() }
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.borderless)
                Button(role: .destructive) { saveQuickPlace(nil, key: key, isHome: isHome) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button {
                guard let loc = locationService.location else { return }
                let p = Place.make(name: title, address: "موقعي الحالي".loc, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                saveQuickPlace(p, key: key, isHome: isHome)
                Task {
                    if let resolved = await GeoService.reverse(lat: p.latitude, lon: p.longitude) {
                        saveQuickPlace(Place.make(name: title, address: resolved.address, lat: p.latitude, lon: p.longitude), key: key, isHome: isHome)
                    }
                }
            } label: {
                Label("\("تعيين".loc) \(title) \("من موقعي الحالي".loc)", systemImage: icon)
            }
            .disabled(locationService.location == nil)
        }
    }
}

// MARK: - Publish a local place (Local Intelligence contribution)
struct AddPlaceSheet: View {
    var place: Place
    var onPublish: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: String = "محل"
    @State private var note: String = ""
    private let cats = ["محل", "مطعم", "كافيه", "صيدلية", "خدمة", "معلم", "أخرى"]

    init(place: Place, onPublish: @escaping (String, String, String) -> Void) {
        self.place = place
        self.onPublish = onPublish
        _name = State(initialValue: place.name == "موقع مُحدد".loc ? "" : place.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("اسم المكان".loc) {
                    TextField("مثال: مخبز التنور".loc, text: $name)
                }
                Section("النوع".loc) {
                    Picker("النوع".loc, selection: $category) {
                        ForEach(cats, id: \.self) { Text($0.loc) }
                    }
                    .pickerStyle(.menu)
                }
                Section("معلومة إضافية (اختياري)".loc) {
                    TextField("ساعات الفتح، رقم، وصف قصير…".loc, text: $note)
                }
                Section {
                    Text(Backend.isConfigured
                         ? "ينشر لكل مستخدمي وجهتي وينحفظ بجهازك.".loc
                         : "ينحفظ بجهازك هسه، وينشر للكل من يشتغل السيرفر المشترك.".loc)
                        .font(.caption).foregroundStyle(adaptiveSecondaryInk)
                }
            }
            .navigationTitle("نشر مكان محلي".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء".loc) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("نشر".loc) {
                        onPublish(name.trimmingCharacters(in: .whitespaces), category, note)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
