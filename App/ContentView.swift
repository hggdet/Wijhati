import SwiftUI
import CoreLocation
import UIKit
import WidgetKit


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
    @State private var showAssistant = false
    @State private var showAR = false
    @State private var homePlace: Place?
    @State private var workPlace: Place?
    @State private var publishPlace: Place?
    @StateObject private var offlineManager = OfflineManager()

    @AppStorage("wijhati.tempUnit") private var tempUnit = "c"
    @AppStorage("wijhati.appearance") private var appearance = "auto"
    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @AppStorage("wijhati.notifMaster") private var notifMaster = true
    @AppStorage("wijhati.language") private var language = "ar"
    @AppStorage("wijhati.voiceID") private var voiceID = ""
    @AppStorage("wijhati.voiceStyle") private var voiceStyle = "calm"
    @AppStorage("wijhati.maptilerKey") private var maptilerKey = ""
    @AppStorage("wijhati.officialLayer") private var officialEnabled = true
    @AppStorage("wijhati.lastLightStyle") private var lastLightStyle = "standard"
    @AppStorage("wijhati.autoDark") private var autoDark = false
    @Environment(\.colorScheme) private var deviceScheme
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
    @State private var loadingRoute = false

    @State private var styleKind: MapStyleKind = .standard
    @State private var followUser = false
    @State private var centerRequest: CenterRequest?
    @State private var northReset = 0

    @State private var showSaved = false
    @State private var showSettings = false
    @State private var show3D = false
    @State private var placeWeather: GeoService.WeatherNow?
    @State private var placeDetails: GeoService.PlaceDetails?
    @State private var showDirections = false
    @State private var directionsText = ""
    @State private var searchPins: [Place] = []
    @State private var cityQuery = ""
    @State private var cityResults: [GeoService.CityResult] = []
    @State private var citySearching = false
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
    @State private var suggestTask: Task<Void, Never>?
    @State private var showIntro = true
    @State private var locStage = 0
    @State private var placeSheetFull = false
    @State private var placeSheetDragY: CGFloat = 0
    @State private var placeSheetVelocity: CGFloat = 0
    @State private var dragPrevY: CGFloat = 0
    @State private var dragLastTime: Date?
    @State private var bearingRequest: BearingRequest?
    @State private var alertCooldown: [String: Date] = [:]

    private var allPins: [Place] {
        pins + community.allPlaces.map { $0.asPlace() }
            + (officialEnabled ? official.places : [])
    }
    private var schemeOverride: ColorScheme? {
        if appearance == "dark" { return .dark }
        if appearance == "light" { return .light }
        return nil
    }

    /// Dark (from the device or the in-app appearance) means a night map —
    /// automatically. The last light style is remembered and restored.
    private var effectiveDark: Bool {
        appearance == "dark" || (appearance == "auto" && deviceScheme == .dark)
    }

    private func syncStyleToScheme() {
        if effectiveDark {
            if styleKind != .dark, styleKind != .ofmDark {
                lastLightStyle = styleKind.rawValue
                styleKind = .dark
                autoDark = true
            }
        } else if autoDark {
            styleKind = MapStyleKind(rawValue: lastLightStyle) ?? .standard
            autoDark = false
        }
    }

    private var selectedRoute: RouteData? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }
    private var altCoords: [CLLocationCoordinate2D] {
        routes.enumerated().filter { $0.offset != selectedRouteIndex }.first?.element.coordinates ?? []
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

    var body: some View {
        ZStack {
            MapBridge(
                pins: allPins,
                routeCoords: selectedRoute?.coordinates ?? [],
                altRouteCoords: altCoords,
                tripCoords: [],
                styleKind: styleKind,
                show3D: show3D,
                followUser: followUser,
                userLocation: locationService.location?.coordinate,
                centerRequest: centerRequest,
                bearingRequest: bearingRequest,
                northReset: northReset,
                onSelectPin: { place in select(place) },
                onLongPress: { coordinate in handleLongPress(coordinate) },
                onMapTap: { showSearch = false }
            )
            .ignoresSafeArea()

            // Progressive blur veils over the map edges (expo-backdrop take)
            VStack(spacing: 0) {
                ProgressiveBlurView(edge: .top).frame(height: 110)
                Spacer()
                ProgressiveBlurView(edge: .bottom).frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if showSearch {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { showSearch = false }
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                topBar
                statusPills
                if showWeatherDetail, let w = localWeather { weatherDetailCard(w) }
                Spacer()
                if !showSearch {
                HStack {
                    Spacer()

                    Button { advanceLocationStage() } label: {
                        Image(systemName: locStageIcon)
                            .font(.system(size: 20, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(locStageColors.0, locStageColors.1)
                            .frame(width: 52, height: 52)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .glass(cornerRadius: 26)
                }
                .transition(.opacity)
                }
                bottomStack
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if showSearch { searchOverlay }
            if voice.active { pocketOverlay }
            if showIntro { WorldIntroView().contentShape(Rectangle()).onTapGesture { withAnimation(.easeOut(duration: 0.4)) { showIntro = false } } }
        }
        .onAppear {
            locationService.request()
            homePlace = Self.loadQuickPlace("wijhati.homePlace")
            workPlace = Self.loadQuickPlace("wijhati.workPlace")
            syncWidgetPlaces()
            syncStyleToScheme()
            Task {
                try? await Task.sleep(nanoseconds: 4_800_000_000)
                withAnimation(.easeOut(duration: 0.5)) { showIntro = false }
            }
            if let loc = locationService.location {
                centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 13)
            }
        }
        .onChange(of: locationService.location) { _, newValue in
            guard let loc = newValue else { return }
            voice.update(userLocation: loc)
            refreshLocalWeatherIfNeeded(loc.coordinate)
            checkProximity(loc)
            checkOffRoute(loc)
            checkSpeedLimit(loc)
        }
        .preferredColorScheme(schemeOverride)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
        .onAppear { applySemanticDirection() }
        .onChange(of: language) { _, _ in applySemanticDirection() }
        .onChange(of: appearance) { _, _ in syncStyleToScheme() }
        .onChange(of: deviceScheme) { _, _ in syncStyleToScheme() }
        .onChange(of: styleKind) { _, newKind in
            // A manual style pick always wins over the automatic night sync.
            if effectiveDark, newKind != .dark, newKind != .ofmDark { autoDark = false }
            if newKind == .maptiler, MapStyleKind.maptilerKey.isEmpty {
                routeNotice = "أضف مفتاح MapTiler المجاني من الإعدادات ← الخريطة".loc
            }
        }
        .onChange(of: maptilerKey) { _, _ in
            // A new key invalidates the cached patched MapTiler style
            // (its embedded tile/font URLs carry the old key).
            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("wijhati-maptiler-ar2.json"))
            MapStyleKind.prepareArabicStyles()
        }
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
            if url.host == "home", let homePlace { select(homePlace); Task { await computeRoute() } }
            if url.host == "work", let workPlace { select(workPlace); Task { await computeRoute() } }
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
        .fullScreenCover(isPresented: $showSettings) { settingsSheet }
        .sheet(item: $shareItem) { payload in
            ShareSheet(text: payload.text)
        }
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

    private func searchCities() async {
        let text = cityQuery.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        citySearching = true
        cityResults = await GeoService.citySearch(text)
        citySearching = false
    }

    // (intro moved to IntroView below)

    // MARK: - Top bar (weather + compass)



    private var topBar: some View {
        HStack(alignment: .top) {
            Button { showWeatherDetail.toggle(); refreshLocalWeatherIfNeeded(locationService.location?.coordinate, force: true) } label: {
                VStack(spacing: 1) {
                    Image(systemName: "sun.max.fill").font(.system(size: 16)).foregroundStyle(.yellow)
                    Text(localWeather.map { tempUnit == "f" ? "\(Int(($0.temperature * 9 / 5 + 32).rounded()))" : "\(Int($0.temperature.rounded()))" } ?? "—")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(adaptiveInk)
                }
                .frame(width: 46, height: 46)
            }
            .glass(cornerRadius: 23)

            Spacer()

            Button { showAssistant = true } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.red, .blue, .green], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 46, height: 46)
            }
            .glass(cornerRadius: 23)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(adaptiveInk)
                    .frame(width: 46, height: 46)
            }
            .glass(cornerRadius: 23)
        }
    }

    private func weatherDetailCard(_ w: GeoService.WeatherNow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("الطقس عند موقعك".loc).font(.caption.weight(.bold))
                Text("\(displayTemp(w.temperature)) • \(w.label)").font(.subheadline.weight(.medium))
                Text("🌅 شروق \(w.sunrise) • 🌇 غروب \(w.sunset)").font(.caption2).foregroundStyle(.secondary)
                Text("\("الوحدة من الإعدادات".loc) ⚙️: \(tempUnit == "f" ? "فهرنهايت".loc : "سيليزية".loc)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .glass(cornerRadius: 18)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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

    // MARK: - Raised search overlay (bar at top, suggestions under it)
    private var searchOverlay: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28).ignoresSafeArea()
                .onTapGesture { showSearch = false; overlayFocused = false }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("ابحث عن مكان أو عنوان".loc, text: $query)
                        .font(.subheadline)
                        .focused($overlayFocused)
                        .onSubmit { showSearch = false; overlayFocused = false; Task { await runSearch() } }
                        .onChange(of: query) { _, newValue in
                            suggestTask?.cancel()
                            suggestTask = Task {
                                try? await Task.sleep(nanoseconds: 120_000_000)
                                guard !Task.isCancelled, query == newValue else { return }
                                if newValue.trimmingCharacters(in: .whitespaces).count >= 2 {
                                    let local = localMatches(for: newValue)
                                    let remote = await GeoService.search(newValue, near: locationService.location?.coordinate, limit: 6)
                                    suggestions = local + remote.filter { r in !local.contains { $0.id == r.id } }
                                } else {
                                    suggestions = []
                                }
                            }
                        }
                    if searching { ProgressView() }
                    if !query.isEmpty {
                        Button { query = ""; suggestions = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                    Button("تم".loc) { showSearch = false; overlayFocused = false }
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glass(cornerRadius: 23)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(spacing: 8) {
                        if !historyStore.items.isEmpty { historyList }
                        if !store.places.isEmpty { savedQuickList }
                    }
                } else if !suggestions.isEmpty {
                    suggestionsList
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 54)
        }
        .zIndex(6)
        .onAppear { DispatchQueue.main.async { overlayFocused = true } }
        .transition(.opacity)
    }

    // MARK: - Bottom stack

    private var bottomStack: some View {
        VStack(spacing: 8) {
            if let place = selected, selectedRoute == nil { placeCard(place) }
            if let route = selectedRoute { routeBar(route) }
            if !stops.isEmpty { stopsBar }
            if let routeNotice, selectedRoute == nil {
                Text(routeNotice)
                    .font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(cornerRadius: 14)
            }
            searchBar
        }
        .opacity(showSearch ? 0 : 1)
        .allowsHitTesting(!showSearch)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: suggestions.isEmpty)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showSearch)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text(query.isEmpty ? "ابحث عن مكان أو عنوان".loc : query)
                        .font(.subheadline)
                        .foregroundStyle(query.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if searching { ProgressView() }
            if !query.isEmpty {
                Button { query = ""; suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glass(cornerRadius: 23)
    }


    private var savedQuickList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("أماكنك المحفوظة".loc)
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
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
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
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
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button("مسح الكل".loc) { historyStore.clear() }
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
            ForEach(historyStore.items) { place in
                Button { select(place) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            if !place.address.isEmpty {
                                Text(place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let loc = locationService.location {
                            Text(fmtDist(loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
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
                                if !place.address.isEmpty {
                                    Text(place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if let loc = locationService.location {
                                Text(fmtDist(loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))
                                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
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
                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.secondary)
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

    private func routeBar(_ route: RouteData) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(TransportChoice.allCases) { choice in
                    Button {
                        transport = choice
                        Task { await computeRoute() }
                    } label: {
                        Label(choice.label, systemImage: choice.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(transport == choice ? Color.blue.opacity(0.85) : Color.white.opacity(0.14),
                                        in: Capsule())
                            .foregroundStyle(transport == choice ? .white : .primary)
                    }
                }
                if loadingRoute { ProgressView().controlSize(.small) }
                Spacer()
                Button { clearRoute() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            if routes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(routes.indices, id: \.self) { idx in
                        Button { selectedRouteIndex = idx } label: {
                            Text(idx == 0 ? "الأسرع: \(formatDuration(routes[idx].duration))" : "بديل: \(formatDuration(routes[idx].duration))")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(idx == selectedRouteIndex ? Color.blue.opacity(0.25) : Color.white.opacity(0.1), in: Capsule())
                        }
                    }
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                Label("\(transport.label): \(formatDuration(route.duration))", systemImage: "clock")
                Label(fmtDist(route.distance), systemImage: "arrow.triangle.swap")
                if !elevations.isEmpty {
                    Label("▲ \(Int(elevations.max() ?? 0)) \("م".loc)", systemImage: "mountain.2")
                }
                Spacer()
                Button {
                    if let place = selected {
                        followUser = true
                        voice.start(steps: route.steps, destination: place.coordinate)
                    }
                } label: {
                    Label("جيب".loc, systemImage: "waveform")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                }
                Button {
                    directionsText = makeDirectionsText()
                    showDirections = true
                } label: {
                    Label("وصف الوصول".loc, systemImage: "text.bubble")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }
            .font(.caption.weight(.medium))
            if !elevations.isEmpty { ElevationChart(values: elevations).frame(height: 34) }
        }
        .padding(11)
        .glass(cornerRadius: 20)
    }

    // MARK: - Place card

    private func placeCard(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Apple Maps-style grabber: drag the card up for full details.
            HStack { Spacer()
                Capsule().fill(Color.secondary.opacity(0.45)).frame(width: 38, height: 5)
                Spacer() }
            .padding(.bottom, 1)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(place.name).font(.headline).lineLimit(2)
                        if place.id.hasPrefix("official-") {
                            Text("رسمي".loc)
                                .font(.caption2.weight(.black)).foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(red: 0.98, green: 0.75, blue: 0.14), in: Capsule())
                        }
                    }
                    if !place.address.isEmpty {
                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let loc = locationService.location {
                        let d = loc.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                        Text("يبعد \(fmtDist(d)) عنك").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let w = placeWeather {
                        Text("🌡 \(displayTemp(w.temperature)) \(w.label) • شروق \(w.sunrise) • غروب \(w.sunset)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { self.selected = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                Button { Task { await computeRoute() } } label: {
                    Label(loadingRoute ? "…" : "الاتجاهات".loc, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                }
                Button {
                    let added = store.toggle(place)
                    if added { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                } label: {
                    Label(store.contains(place) ? "محفوظ".loc : "حفظ الموقع".loc, systemImage: store.contains(place) ? "bookmark.fill" : "bookmark")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                if !place.id.hasPrefix("community-"), !place.id.hasPrefix("official-") {
                    Button { publishPlace = place } label: {
                        Label("نشر محلي".loc, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.purple.opacity(0.18), in: Capsule())
                    }
                }
                Button { stops.append(place) } label: {
                    Label("توقف".loc, systemImage: "flag")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                if let phone = place.phone, let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                            .padding(8).background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                Button { shareItem = SharePayload(text: "\(place.name)\n\(place.mapsLink.absoluteString)") } label: {
                    Label("مشاركة".loc, systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if placeSheetFull {
                Divider().opacity(0.4)
                VStack(alignment: .leading, spacing: 8) {
                    if let photo = placeDetails?.photoURL {
                        AsyncImage(url: photo) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { Color.secondary.opacity(0.15) }
                        .frame(height: 130).frame(maxWidth: .infinity)
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let d = placeDetails {
                        if let hours = d.openingHours {
                            HStack(spacing: 6) {
                                Circle().fill(d.isOpenNow == true ? Color.green : (d.isOpenNow == false ? Color.red : Color.secondary))
                                    .frame(width: 8, height: 8)
                                Text(d.isOpenNow == true ? "مفتوح الآن".loc : (d.isOpenNow == false ? "مغلق الآن".loc : "ساعات الدوام".loc))
                                    .font(.caption.weight(.semibold))
                                Text(hours).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "location.viewfinder").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                            .font(.caption2).foregroundStyle(.secondary)
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
                    Text("لا توجد أماكن محفوظة بعد".loc).foregroundStyle(.secondary)
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
                                    Text(saved.place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
                NavigationLink {
                    mapSettingsPage
                } label: {
                    Label("الخريطة".loc, systemImage: "map.fill")
                }
                NavigationLink {
                    appearancePage
                } label: {
                    Label("المظهر".loc, systemImage: "circle.lefthalf.filled")
                }
                NavigationLink {
                    offlinePage
                } label: {
                    Label("خرائط بدون إنترنت".loc, systemImage: "arrow.down.circle.fill")
                }
                NavigationLink {
                    notificationsPage
                } label: {
                    Label("الإشعارات".loc, systemImage: "bell.fill")
                }
                NavigationLink {
                    locationSettingsPage
                } label: {
                    Label("الموقع".loc, systemImage: "location.fill")
                }
                NavigationLink {
                    languagePage
                } label: {
                    Label("اللغة".loc, systemImage: "globe")
                }
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
                Section {
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showSaved = true }
                    } label: {
                        Label("أماكني المحفوظة".loc, systemImage: "bookmark.fill")
                    }
                }
            }
            .navigationTitle("الإعدادات".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق".loc) { showSettings = false } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(schemeOverride)
        .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
        .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
    }

    private var mapSettingsPage: some View {
        Form {
            Section {
                Picker("النمط".loc, selection: $styleKind) {
                    ForEach(MapStyleKind.allCases.filter { $0 != .cartoon }, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
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
                Toggle("أبنية ثلاثية الأبعاد".loc, isOn: $show3D)
                Toggle("الطبقة الرسمية".loc, isOn: $officialEnabled)
                VStack(spacing: 8) {
                    HStack {
                        Text("شريط التحكم بالزجاج".loc)
                        Spacer()
                        Text("\(Int(glassLevel * 100))٪")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("مصمت".loc).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        Slider(value: $glassLevel, in: 0...1)
                        Text("زجاجي".loc).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                TextField("مفتاح MapTiler".loc, text: $maptilerKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link("الحصول على مفتاح مجاني".loc,
                     destination: URL(string: "https://cloud.maptiler.com/account/keys/")!)
                    .font(.footnote)
            } header: {
                Text("MapTiler")
            } footer: {
                Text("سجّل مجاناً في maptiler.com، انسخ مفتاح API والصقه هنا، ثم اختر MapTiler من «النمط» بالأعلى".loc)
            }
        }
        .navigationTitle("الخريطة".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appearancePage: some View {
        Form {
            ForEach([("light", "الوضع العادي"), ("auto", "تلقائي"), ("dark", "الوضع الداكن")], id: \.0) { item in
                Button {
                    appearance = item.0
                } label: {
                    HStack {
                        Text(item.1.loc)
                        Spacer()
                        if appearance == item.0 {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("المظهر".loc)
        .navigationBarTitleDisplayMode(.inline)
    }


    private var helpPage: some View {
        List {
            Section("تعليمات الاستخدام".loc) {
                Label("ابحث عن أي مكان من شريط البحث — الاقتراحات تظهر ويا المسافة لكل نتيجة".loc, systemImage: "magnifyingglass")
                Label("اضغط مطوّلاً على أي نقطة بالخريطة حتى يثبت دبوس وتطلع بطاقة المكان".loc, systemImage: "mappin.and.ellipse")
                Label("اسحب بطاقة المكان للأعلى حتى تشوف العنوان الكامل والإحداثيات".loc, systemImage: "square.and.arrow.up.on.square")
                Label("زر الموقع: ضغطة تركّز عليك، الثانية بوصلة باتجاه وجهتك، الثالثة أبنية ثلاثية الأبعاد".loc, systemImage: "location.fill")
                Label("من الإعدادات ← «الخريطة» شريط «مصمت — زجاجي» يتحكم بشفافية واجهة التطبيق مثلما تتحكم بالصوت".loc, systemImage: "slider.horizontal.3")
                Label("بعد رسم المسار اضغط «جيب» للملاحة الصوتية وهاتفك بجيبك، وبالمشي جرّب «ملاحة بالكاميرا»".loc, systemImage: "waveform")
                Label("ثبّت بيتك وشغلك من «أماكني المحفوظة» وضيف ودجت وجهتي لشاشتك حتى توصل بضغطة".loc, systemImage: "house.fill")
                Label("نزّل خرائط منطقتك من «خرائط بدون إنترنت» حتى تتصفح بدون إنترنت".loc, systemImage: "arrow.down.circle")
            }
            Section("أسئلة شائعة".loc) {
                DisclosureGroup("ليش بعض أسماء الأماكن خطأ أو ناقصة؟".loc) {
                    Text("بيانات الخريطة من OpenStreetMap ويحرّرها متطوعون حول العالم. وجهتي يعرض الاسم العربي متى ما توفّر، وبعض الأخطاء من المصدر نفسه وتتصلح بتحديثات البيانات.".loc)
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("شلون أبدّل نمط الخريطة؟".loc) {
                    Text("من الإعدادات ← «الخريطة» تختار النمط (قياسية، فاتحة، زاهية، ليلي، داكن، قمر صناعي) وتفعّل الأبنية ثلاثية الأبعاد.".loc)
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("هل يشتغل التطبيق بدون إنترنت؟".loc) {
                    Text("بعد تنزيل منطقة من «خرائط بدون إنترنت» تقدر تتصفح خريطتها بدون نت. البحث وحساب المسارات والطقس يحتاجون اتصالاً.".loc)
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("شلون أضيف مكاناً مو موجود بالخريطة؟".loc) {
                    Text("افتح أي مكان قريب واضغط «نشر محلي» من بطاقته، أو ثبّت دبوساً بضغطة مطوّلة وانشر المكان من بطاقته — يظهر عندك وبالمجتمع.".loc)
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("شلون أوصل للبيت أو الشغل بسرعة؟".loc) {
                    Text("ثبّتهما أول مرة من «أماكني المحفوظة» ← البيت/الشغل، وبعدها الاتجاهات بضغطة وحدة من نفس الصفحة أو من ودجت الشاشة الرئيسية.".loc)
                        .font(.callout).foregroundStyle(.secondary)
                }
                DisclosureGroup("ليش ما تغيّر وقت المسار بين السيارة والمشي؟".loc) {
                    Text("كل نمط يُحسب من خادم مختلف. إذا تعذّر حساب نمط معيّن يطلع لك تنبيه برتقالي — تأكد من اتصالك وجرّب مرة ثانية.".loc)
                        .font(.callout).foregroundStyle(.secondary)
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
                        .font(.caption).foregroundStyle(.secondary)
                    Text("عبدالباسط خضير".loc)
                        .font(.headline)
                    Text("© 2026 عبدالباسط خضير — جميع الحقوق محفوظة".loc)
                        .font(.caption2).foregroundStyle(.secondary)
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
                        Text("خرائط وملاحة عربية للعالم كله".loc).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                HStack { Text("الإصدار".loc); Spacer(); Text("1.43").foregroundStyle(.secondary) }
                HStack { Text("المطوّر".loc); Spacer(); Text("عبدالباسط خضير".loc).foregroundStyle(.secondary) }
                HStack { Text("المحرك".loc); Spacer(); Text("MapLibre").foregroundStyle(.secondary) }
                HStack { Text("مؤثرات بصرية".loc); Spacer(); Text("مستوحاة من مشاريع rit3zh (MIT)".loc).font(.caption2).foregroundStyle(.secondary) }
            }
            Section {
                Text("وجهتي تطبيق خرائط عالمي بواجهة عربية زجاجية أنيقة: بحث فوري، مسارات بديلة، أنماط خرائط متعددة، أبنية ثلاثية الأبعاد، وملاحة صوتية تعمل والهاتف في جيبك.".loc)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("حول وجهتي".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Offline page

    private var offlinePage: some View {
        List {
            Section {
                Button {
                    if let loc = locationService.location, let url = styleKind.url {
                        offlineManager.download(styleURL: url,
                                                center: loc.coordinate, name: "منطقتي — \(styleKind.label)")
                    }
                } label: {
                    Label("تنزيل المنطقة حول موقعي".loc, systemImage: "arrow.down.circle.fill")
                }
                .disabled(locationService.location == nil || offlineManager.downloading)
                if offlineManager.downloading {
                    ProgressView(value: offlineManager.fraction) {
                        Text("\("جارٍ التنزيل…".loc) \(Int(offlineManager.fraction * 100))\(L10n.lang == "en" ? "%" : "٪")")
                    }
                }
                if let error = offlineManager.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
            Section("تنزيل مدينة".loc) {
                HStack {
                    TextField("اسم المدينة".loc, text: $cityQuery)
                        .onSubmit { Task { await searchCities() } }
                    if citySearching { ProgressView() }
                    Button("بحث".loc) { Task { await searchCities() } }
                        .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty || citySearching)
                }
                ForEach(cityResults) { city in
                    Button {
                        if let url = styleKind.url {
                            offlineManager.downloadRegion(styleURL: url, sw: city.sw, ne: city.ne, name: city.name)
                        }
                    } label: {
                        HStack {
                            Text(city.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                    .disabled(offlineManager.downloading || styleKind.url == nil)
                }
            }
            Section {
                if offlineManager.infos.isEmpty {
                    Text("لا توجد مناطق محمّلة بعد".loc).foregroundStyle(.secondary)
                }
                ForEach(offlineManager.infos) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.name).font(.subheadline.weight(.medium))
                            Text("\(info.stateText) • \(info.sizeText)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { offlineManager.delete(info) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("خرائط بدون إنترنت".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var languagePage: some View {
        Form {
            ForEach([("ar", "العربية"), ("en", "English"), ("ku", "کوردی")], id: \.0) { item in
                Button {
                    language = item.0
                } label: {
                    HStack {
                        Text(item.1)
                        Spacer()
                        if language == item.0 {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("اللغة".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationSettingsPage: some View {
        Form {
            Section("موقعك الحالي".loc) {
                if let loc = locationService.location {
                    HStack { Text("خط العرض".loc); Spacer(); Text(String(format: "%.5f", loc.coordinate.latitude)).foregroundStyle(.secondary) }
                    HStack { Text("خط الطول".loc); Spacer(); Text(String(format: "%.5f", loc.coordinate.longitude)).foregroundStyle(.secondary) }
                    HStack { Text("الدقة".loc); Spacer(); Text("\(Int(loc.horizontalAccuracy)) م").foregroundStyle(.secondary) }
                } else {
                    Text("فعّل خدمات الموقع حتى يظهر موقعك هنا".loc)
                        .foregroundStyle(.secondary)
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
            Section("الصوت".loc) {
                ForEach(VoiceGuide.arabicVoiceInfos, id: \.id) { info in
                    Button {
                        voiceID = info.id
                        voice.preview(voiceID: info.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.name)
                                Text("\(info.language) • \(qualityLabel(info.quality))")
                                    .font(.caption).foregroundStyle(.secondary)
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
                Text("لأصوات عربية إضافية بجودة أعلى، حمّلها من إعدادات الآيفون ← إمكانية الوصول ← المحتوى المنطوق ← الأصوات ← العربية، وستظهر هنا تلقائياً.".loc)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("اختيار الصوت".loc)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notificationsPage: some View {
        Form {
            Section {
                Toggle("التنبيهات".loc, isOn: $notifMaster)
                    .onChange(of: notifMaster) { _, on in if on { Notify.requestPermission() } }
                Toggle("تنبيه عند الاقتراب".loc, isOn: $notifSaved)
                    .onChange(of: notifSaved) { _, on in if on { Notify.requestPermission() } }
                    .disabled(!notifMaster)
            }
            Section {
                VStack(spacing: 8) {
                    HStack {
                        Text("صوت المرشد".loc)
                        Spacer()
                        Text("\(Int(voiceVolume * 100))٪")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Slider(value: $voiceVolume, in: 0...1) { editing in
                        if !editing { voice.announce("صوت المرشد") }
                    }
                }
                .padding(.vertical, 4)
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
        .navigationTitle("الإشعارات".loc)
        .navigationBarTitleDisplayMode(.inline)
    }






    /// SwiftUI's layoutDirection environment alone did not flip lists on
    /// the user's iOS 27 build, so force it at the UIKit level too (the
    /// collection views under List/Form obey semanticContentAttribute),
    /// and WijhatiApp rebuilds the whole tree on language change (.id).
    private func applySemanticDirection() {
        let attr: UISemanticContentAttribute = language == "en" ? .forceLeftToRight : .forceRightToLeft
        UIView.appearance().semanticContentAttribute = attr
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.semanticContentAttribute = attr }
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
                                body: "\("اقتربت من مكانك المحفوظ".loc): \(saved.place.name)")
                }
            }
        }
    }

    // MARK: - Actions

    private var locStageColors: (Color, Color) {
        switch locStage {
        case 2: return (.red, .blue)       // compass stage
        case 3: return (.green, .green)  // 3D stage
        default: return (adaptiveInk, adaptiveInk)
        }
    }

    private var locStageIcon: String {
        switch locStage {
        case 2: return "location.north.fill"
        case 3: return "building.2.fill"
        default: return "location.fill"
        }
    }

    /// One button, three stages: 1 = go to my location,
    /// 2 = compass (or face the chosen destination), 3 = 3D buildings,
    /// next press returns to flat north view.
    private func advanceLocationStage() {
        locStage = (locStage + 1) % 4
        switch locStage {
        case 1:
            followUser = false
            if let loc = locationService.location {
                centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
            }
        case 2:
            if let dest = selected?.coordinate, let loc = locationService.location {
                followUser = false
                bearingRequest = BearingRequest(degrees: bearingDegrees(from: loc.coordinate, to: dest))
                centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
            } else {
                followUser = true
            }
        case 3:
            followUser = false
            show3D = true
        default:
            followUser = false
            show3D = false
            northReset += 1
        }
    }

    private func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func select(_ place: Place) {
        if showSearch || !suggestions.isEmpty || searchPins.contains(where: { $0.id == place.id }) {
            historyStore.add(place)
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

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        let results = await GeoService.search(text, near: locationService.location?.coordinate)
        searching = false
        pins = results
        searchPins = results
        suggestions = []
        if let first = results.first { select(first); pins = results }
    }

    private func computeRoute() async {
        guard let origin = locationService.location?.coordinate, let dest = selected else { return }
        // Generation guard: if the user switches transport or destination
        // mid-flight, the stale computation must not overwrite the new one.
        routeGeneration += 1
        let gen = routeGeneration
        lastRouteAt = Date()
        routeNotice = nil
        loadingRoute = true
        let result = await GeoService.route(from: origin, waypoints: stops.map { $0.coordinate },
                                            to: dest.coordinate, profile: transport.osrmProfile)
        guard gen == routeGeneration else { return }
        loadingRoute = false
        if result.isEmpty {
            routeNotice = "\("تعذّر حساب مسار".loc) \(transport.label) \("لهذه الوجهة — جرّب وسيلة أخرى أو وجهة أقرب".loc)"
        }
        // Show the routes immediately; landmark-enriched copies replace
        // them when the (slower) Overpass pass returns.
        routes = result
        selectedRouteIndex = 0
        let enriched = await GeoService.enrichRoutes(result)
        guard gen == routeGeneration else { return }
        routes = enriched
        elevations = []
        if let first = result.first {
            let els = await GeoService.elevations(for: first.coordinates)
            guard gen == routeGeneration else { return }
            elevations = els
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
        let stride = max(1, coords.count / 400)
        var best = Double.greatestFiniteMagnitude
        var i = 0
        while i < coords.count {
            let c = coords[i]
            let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < best { best = d }
            i += stride
        }
        if let last = coords.last {
            let d = loc.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            if d < best { best = d }
        }
        if best > 75 { offRouteCount += 1 } else { offRouteCount = 0 }
        if offRouteCount >= 3 {
            offRouteCount = 0
            voice.announce("إعادة حساب المسار".loc)
            Task { await computeRoute() }
        }
    }

    private func clearRoute() {
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
        for (place, k) in [(homePlace, "home"), (workPlace, "work")] {
            if let place {
                shared.set(["name": place.name, "lat": place.latitude, "lon": place.longitude], forKey: k)
            } else {
                shared.removeObject(forKey: k)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
    func localMatches(for query: String) -> [Place] {
        let q = GeoService.normalizeArabic(query)
        guard q.count >= 2 else { return [] }
        let candidates = store.places.map { $0.place } + community.allPlaces.map { $0.asPlace() }
        return Array(candidates.filter { GeoService.normalizeArabic($0.name).contains(q) }.prefix(3))
    }
    @ViewBuilder
    func quickPlaceRow(title: String, icon: String, place: Place?, key: String, isHome: Bool) -> some View {
        if let place {
            HStack {
                Image(systemName: icon).foregroundStyle(adaptiveInk)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(place.name).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Spacer()
                Button("اتجاهات".loc) {
                    showSaved = false
                    select(place)
                    Task { await computeRoute() }
                }
                .font(.caption.weight(.bold))
                Button(role: .destructive) { saveQuickPlace(nil, key: key, isHome: isHome) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
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
                        .font(.caption).foregroundStyle(.secondary)
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
