import SwiftUI
import CoreLocation
import UIKit

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
    @StateObject private var voice = VoiceGuide()
    @StateObject private var community = CommunityStore()
    @State private var showAssistant = false
    @State private var showAR = false
    @State private var homePlace: Place?
    @State private var workPlace: Place?
    @State private var publishPlace: Place?
    @StateObject private var offlineManager = OfflineManager()

    @AppStorage("wijhati.tempUnit") private var tempUnit = "c"
    @AppStorage("wijhati.appearance") private var appearance = "auto"
    @AppStorage("wijhati.glassLevel") private var glassLevel: Double = 0.53
    @AppStorage("wijhati.distanceUnit") private var distanceUnit = "auto"
    @AppStorage("wijhati.notifSaved") private var notifSaved = false

    @State private var query = ""
    @State private var suggestions: [Place] = []
    @State private var pins: [Place] = []
    @State private var selected: Place?
    @State private var stops: [Place] = []
    @State private var transport: TransportChoice = .driving
    @State private var routes: [RouteData] = []
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
    @State private var radarOn = false
    @State private var radarTS: Int?
    @State private var isoMinutes: Int = 0
    @State private var isoPolygon: [CLLocationCoordinate2D] = []

    @State private var placeWeather: GeoService.WeatherNow?
    @State private var localWeather: GeoService.WeatherNow?
    @State private var weatherFetchedAt: Date?
    @State private var weatherForCoord: CLLocationCoordinate2D?
    @State private var showWeatherDetail = false
    @State private var elevations: [Double] = []
    @State private var shareItem: SharePayload?
    @FocusState private var searchFocused: Bool
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
    }
    private var schemeOverride: ColorScheme? {
        if appearance == "dark" { return .dark }
        if appearance == "light" { return .light }
        return nil
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
            if mi >= 0.1 { return String(format: "%.1f ميل", mi) }
            return String(format: "%.0f قدم", meters * 3.28084)
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
                isoPolygon: isoPolygon,
                styleKind: styleKind,
                show3D: show3D,
                radarTimestamp: radarOn ? radarTS : nil,
                followUser: followUser,
                userLocation: locationService.location?.coordinate,
                centerRequest: centerRequest,
                bearingRequest: bearingRequest,
                northReset: northReset,
                onSelectPin: { place in select(place) },
                onLongPress: { coordinate in handleLongPress(coordinate) },
                onMapTap: { searchFocused = false }
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

            if searchFocused {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { searchFocused = false }
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                topBar
                statusPills
                if !searchFocused {
                    HStack { Spacer(); surfaceControlBar; Spacer() }
                        .transition(.opacity)
                }
                if showWeatherDetail, let w = localWeather { weatherDetailCard(w) }
                Spacer()
                if !searchFocused {
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

            if searchFocused { searchOverlay }
            if voice.active { pocketOverlay }
            if showIntro { MorphIntroView() }
        }
        .onAppear {
            locationService.request()
            homePlace = Self.loadQuickPlace("wijhati.homePlace")
            workPlace = Self.loadQuickPlace("wijhati.workPlace")
            syncWidgetPlaces()
            Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
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
        }
        .preferredColorScheme(schemeOverride)
        .sheet(isPresented: $showSaved) { savedSheet }
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
            HStack {
                Spacer()
                Text("\(Int((loc.speed * 3.6).rounded())) كم/س")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .glass(cornerRadius: 14)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    // (intro moved to IntroView below)

    // MARK: - Top bar (weather + compass)


    /// Glass-strength slider bar — like a volume control for the glass.
    private var surfaceControlBar: some View {
        HStack(spacing: 8) {
            Text("مصمت").font(.caption2.weight(.bold)).foregroundStyle(Color(white: 0.08))
            Slider(value: $glassLevel, in: 0...1)
                .tint(Color(white: 0.08))
                .frame(width: 140)
            Text("زجاجي").font(.caption2.weight(.bold)).foregroundStyle(Color(white: 0.08))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(cornerRadius: 19)
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { showWeatherDetail.toggle(); refreshLocalWeatherIfNeeded(locationService.location?.coordinate, force: true) } label: {
                VStack(spacing: 1) {
                    Image(systemName: "sun.max.fill").font(.system(size: 16)).foregroundStyle(.yellow)
                    Text(localWeather.map { tempUnit == "f" ? "\(Int(($0.temperature * 9 / 5 + 32).rounded()))" : "\(Int($0.temperature.rounded()))" } ?? "—")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
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
                    .foregroundStyle(.black)
                    .frame(width: 46, height: 46)
            }
            .glass(cornerRadius: 23)
        }
    }

    private func weatherDetailCard(_ w: GeoService.WeatherNow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("الطقس عند موقعك").font(.caption.weight(.bold))
                Text("\(displayTemp(w.temperature)) • \(w.label)").font(.subheadline.weight(.medium))
                Text("🌅 شروق \(w.sunrise) • 🌇 غروب \(w.sunset)").font(.caption2).foregroundStyle(.secondary)
                Text("الوحدة من الإعدادات ⚙️: \(tempUnit == "f" ? "فهرنهايت" : "سيليزية")")
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
                .onTapGesture { searchFocused = false }
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("ابحث عن مكان أو عنوان", text: $query)
                        .font(.subheadline)
                        .focused($overlayFocused)
                        .onSubmit { searchFocused = false; Task { await runSearch() } }
                    if searching { ProgressView() }
                    if !query.isEmpty {
                        Button { query = ""; suggestions = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                    Button("تم") { searchFocused = false }
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .glass(cornerRadius: 23)
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !store.places.isEmpty { savedQuickList }
                } else if !suggestions.isEmpty {
                    suggestionsList
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 54)
        }
        .zIndex(6)
        .onAppear { overlayFocused = true }
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
        .opacity(searchFocused ? 0 : 1)
        .allowsHitTesting(!searchFocused)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: suggestions.isEmpty)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: searchFocused)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("ابحث عن مكان أو عنوان", text: $query)
                .font(.subheadline)
                .focused($searchFocused)
                .onSubmit { searchFocused = false; Task { await runSearch() } }
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
            if searchFocused {
                Button("تم") { searchFocused = false }
                    .font(.subheadline.weight(.bold))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glass(cornerRadius: 23)
    }

    private var savedQuickList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("أماكنك المحفوظة")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
            ForEach(store.places.prefix(5)) { saved in
                Button { select(saved.place) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: saved.isFavorite ? "star.fill" : "mappin.circle.fill")
                            .foregroundStyle(saved.isFavorite ? .yellow : Color(white: 0.05)).font(.system(size: 17))
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

    private var suggestionsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(suggestions) { place in
                    Button { select(place) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(Color(white: 0.05)).font(.system(size: 19))
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
                Button("مسح") { stops = []; Task { await computeRoute() } }
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
                    Label("▲ \(Int(elevations.max() ?? 0)) م", systemImage: "mountain.2")
                }
                Spacer()
                Button {
                    if let place = selected {
                        followUser = true
                        voice.start(steps: route.steps, destination: place.coordinate)
                    }
                } label: {
                    Label("جيب", systemImage: "waveform")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
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
                    Text(place.name).font(.headline).lineLimit(2)
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
                    Label(loadingRoute ? "…" : "الاتجاهات", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                }
                Button {
                    let added = store.toggle(place)
                    if added { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                } label: {
                    Label(store.contains(place) ? "محفوظ" : "حفظ الموقع", systemImage: store.contains(place) ? "bookmark.fill" : "bookmark")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                if !place.id.hasPrefix("community-") {
                    Button { publishPlace = place } label: {
                        Label("نشر محلي", systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.purple.opacity(0.18), in: Capsule())
                    }
                }
                Button { stops.append(place) } label: {
                    Label("توقف", systemImage: "flag")
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
                    Label("مشاركة", systemImage: "square.and.arrow.up")
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
                            Label("نسخ الإحداثيات", systemImage: "doc.on.doc")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    Link(destination: place.mapsLink) {
                        Label("فتح في خرائط آبل", systemImage: "map")
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
            placeWeather = await GeoService.weather(lat: place.latitude, lon: place.longitude)
        }
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
                        Label("ملاحة بالكاميرا", systemImage: "camera.viewfinder")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Color.blue, in: Capsule())
                    }
                }
                Button { voice.stop(); followUser = false } label: {
                    Text("إيقاف الملاحة")
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
                Section("أماكن سريعة") {
                    quickPlaceRow(title: "البيت", icon: "house.fill", place: homePlace, key: "wijhati.homePlace", isHome: true)
                    quickPlaceRow(title: "الشغل", icon: "briefcase.fill", place: workPlace, key: "wijhati.workPlace", isHome: false)
                }
                if store.places.isEmpty {
                    Text("لا توجد أماكن محفوظة بعد").foregroundStyle(.secondary)
                }
                ForEach(store.places) { saved in
                    Button {
                        showSaved = false
                        select(saved.place)
                    } label: {
                        HStack {
                            Image(systemName: saved.isFavorite ? "star.fill" : "mappin.circle.fill")
                                .foregroundStyle(saved.isFavorite ? .yellow : Color(white: 0.05))
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
                            Label("مفضلة", systemImage: "star")
                        }.tint(.yellow)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.remove(saved) } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("أماكني المحفوظة")
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
                    Button("إغلاق") { showSaved = false }
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
                    Label("الخريطة والطبقات", systemImage: "map.fill")
                }
                NavigationLink {
                    offlinePage
                } label: {
                    Label("خرائط بدون إنترنت", systemImage: "arrow.down.circle.fill")
                }
                NavigationLink {
                    notificationsPage
                } label: {
                    Label("الإشعارات", systemImage: "bell.fill")
                }
                NavigationLink {
                    helpPage
                } label: {
                    Label("مساعدة وملاحظات", systemImage: "questionmark.circle.fill")
                }
                NavigationLink {
                    aboutPage
                } label: {
                    Label("حول وجهتي", systemImage: "info.circle.fill")
                }
                Section {
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showSaved = true }
                    } label: {
                        Label("أماكني المحفوظة", systemImage: "bookmark.fill")
                    }
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showSettings = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var mapSettingsPage: some View {
        Form {
            Section("نمط الخريطة") {
                Picker("النمط", selection: $styleKind) {
                    ForEach(MapStyleKind.allCases.filter { $0 != .cartoon }, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
            }
            Section("وحدة الحرارة") {
                Picker("الوحدة", selection: $tempUnit) {
                    Text("سيليزية °C").tag("c")
                    Text("فهرنهايت °F").tag("f")
                }
                .pickerStyle(.segmented)
            }
            Section("المظهر") {
                Picker("الوضع", selection: $appearance) {
                    Text("عادي").tag("light")
                    Text("تلقائي").tag("auto")
                    Text("داكن").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, mode in
                    if mode == "dark", styleKind != .dark { styleKind = .dark }
                    if mode == "light", styleKind == .dark { styleKind = .standard }
                }
                HStack {
                    Text("شفافية الزجاج")
                    Slider(value: $glassLevel, in: 0...1)
                    Text("\(Int(glassLevel * 100))٪")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 42)
                }
            }
            Section("وحدة المسافة") {
                Picker("المسافة", selection: $distanceUnit) {
                    Text("كيلومتر").tag("km")
                    Text("ميل").tag("mi")
                    Text("تلقائي").tag("auto")
                }
                .pickerStyle(.segmented)
            }
            Section("طبقات") {
                Toggle("أبنية ثلاثية الأبعاد", isOn: $show3D)
                Toggle("رادار المطر الحي", isOn: $radarOn)
                    .onChange(of: radarOn) { _, on in
                        if on { Task { radarTS = await GeoService.latestRadarTimestamp() } }
                    }
            }
            Section("منطقة الوصول من موقعي") {
                Picker("المدة", selection: $isoMinutes) {
                    Text("إيقاف").tag(0)
                    Text("10 د").tag(10)
                    Text("20 د").tag(20)
                    Text("30 د").tag(30)
                }
                .pickerStyle(.segmented)
                .onChange(of: isoMinutes) { _, minutes in
                    Task { await updateIsochrone(minutes: minutes) }
                }
            }
        }
        .navigationTitle("الخريطة والطبقات")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helpPage: some View {
        List {
            Section("شلون تستخدم وجهتي؟") {
                Label("ابحث عن أي مكان أو عنوان من شريط البحث تحت", systemImage: "magnifyingglass")
                Label("اضغط مطوّلاً على أي نقطة بالخريطة حتى يثبت دبوس وتطلع بطاقة المكان", systemImage: "mappin.and.ellipse")
                Label("من بطاقة المكان: الاتجاهات، حفظ الموقع، ومشاركته", systemImage: "bookmark")
                Label("بعد رسم المسار اضغط «جيب» للملاحة الصوتية وهاتفك بجيبك", systemImage: "waveform")
                Label("غيّر نمط الخريطة (قياسية، فاتحة، كرتونية، قمر صناعي) من «الخريطة والطبقات»", systemImage: "map")
                Label("زر البوصلة فوق يرجّع الشمال ويركّز على موقعك، وزر الطقس يعرض حرارة موقعك", systemImage: "location.north.fill")
            }
            Section("ملاحظاتك تهمّنا") {
                Link(destination: URL(string: "mailto:id9871456@gmail.com?subject=" + ("ملاحظات وجهتي".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))!) {
                    Label("إرسال ملاحظات للمطوّر", systemImage: "envelope.fill")
                }
                ShareLink(item: "جرّب تطبيق وجهتي — خرائط وملاحة عربية أنيقة") {
                    Label("مشاركة التطبيق مع صديق", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = "id9871456@gmail.com"
                } label: {
                    Label("نسخ إيميل الملاحظات", systemImage: "doc.on.doc")
                }
            }
            Section("مصادر البيانات") {
                Text("الخرائط: © مساهمو OpenStreetMap — الأنماط: VersaTiles وCyclOSM وصور Esri. الطقس: Open-Meteo. المسارات: OSRM. البحث: Photon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("مساعدة وملاحظات")
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
                        Text("خرائط وملاحة عربية للعالم كله").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                HStack { Text("الإصدار"); Spacer(); Text("1.22").foregroundStyle(.secondary) }
                HStack { Text("المطوّر"); Spacer(); Text("عبدالباسط خضير").foregroundStyle(.secondary) }
                HStack { Text("المحرك"); Spacer(); Text("MapLibre").foregroundStyle(.secondary) }
                HStack { Text("مؤثرات بصرية"); Spacer(); Text("مستوحاة من مشاريع rit3zh (MIT)").font(.caption2).foregroundStyle(.secondary) }
            }
            Section {
                Text("وجهتي تطبيق خرائط عالمي بواجهة عربية زجاجية أنيقة: بحث فوري، مسارات بديلة، أنماط خرائط متعددة، أبنية ثلاثية الأبعاد، رادار مطر، وملاحة صوتية تعمل والهاتف في جيبك.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("حول وجهتي")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Offline page

    private var offlinePage: some View {
        List {
            Section {
                Text("نزّل خريطة منطقتك وتصفّحها بدون إنترنت. يُنزَّل النمط الحالي للخريطة بمدى تقريبي 30 كم حول موقعك.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    if let loc = locationService.location {
                        offlineManager.download(styleURL: styleKind.url ?? MapStyleKind.standard.url!,
                                                center: loc.coordinate, name: "منطقتي — \(styleKind.label)")
                    }
                } label: {
                    Label("تنزيل المنطقة حول موقعي", systemImage: "arrow.down.circle.fill")
                }
                .disabled(locationService.location == nil || offlineManager.downloading)
                if offlineManager.downloading {
                    ProgressView(value: offlineManager.fraction) {
                        Text("جارٍ التنزيل… \(Int(offlineManager.fraction * 100))٪")
                    }
                }
                if let error = offlineManager.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
            Section("المناطق المحمّلة") {
                if offlineManager.packs.isEmpty {
                    Text("لا توجد مناطق محمّلة بعد").foregroundStyle(.secondary)
                }
                ForEach(Array(offlineManager.packs.enumerated()), id: \.offset) { _, pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offlineManager.name(of: pack)).font(.subheadline.weight(.medium))
                            Text("\(offlineManager.stateText(of: pack)) • \(offlineManager.sizeText(of: pack))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { offlineManager.delete(pack) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("خرائط بدون إنترنت")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { offlineManager.reload() }
    }

    // MARK: - Notifications page

    private var notificationsPage: some View {
        Form {
            Section {
                Toggle("تنبيه عند الاقتراب من مكان محفوظ (300م)", isOn: $notifSaved)
                    .onChange(of: notifSaved) { _, on in if on { Notify.requestPermission() } }
            } footer: {
                Text("تصلك تنبيهات صوتية وإشعارات أثناء القيادة حتى لا يفوتك خطر أو مكان يهمّك.")
            }
            Section {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("فتح إعدادات إشعارات النظام", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("الإشعارات")
        .navigationBarTitleDisplayMode(.inline)
    }





    private func checkProximity(_ loc: CLLocation) {
        let now = Date()
        func cooling(_ key: String) -> Bool {
            if let last = alertCooldown[key], now.timeIntervalSince(last) < 900 { return true }
            alertCooldown[key] = now
            return false
        }
        if notifSaved {
            for saved in store.places {
                let d = loc.distance(from: CLLocation(latitude: saved.place.latitude, longitude: saved.place.longitude))
                if d < 300, !cooling("saved-\(saved.place.id)") {
                    let text = "اقتربت من مكانك المحفوظ: \(saved.place.name)"
                    voice.announce(text)
                    Notify.fire(title: "وجهتي — مكان محفوظ", body: text)
                }
            }
        }
    }

    // MARK: - Actions

    private var locStageColors: (Color, Color) {
        switch locStage {
        case 2: return (.red, .blue)       // compass stage
        case 3: return (.green, .green)  // 3D stage
        default: return (Color(white: 0.05), Color(white: 0.05))
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
        searchFocused = false
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
        let temp = Place.make(name: "موقع مُحدد",
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
        suggestions = []
        if let first = results.first { select(first); pins = results }
    }

    private func computeRoute() async {
        guard let origin = locationService.location?.coordinate, let dest = selected else { return }
        routeNotice = nil
        loadingRoute = true
        let result = await GeoService.route(from: origin, waypoints: stops.map { $0.coordinate },
                                            to: dest.coordinate, profile: transport.osrmProfile)
        loadingRoute = false
        if result.isEmpty {
            routeNotice = "تعذّر حساب مسار \(transport.label) لهذه الوجهة — جرّب وسيلة أخرى أو وجهة أقرب"
        }
        routes = await GeoService.enrichRoutes(result)
        selectedRouteIndex = 0
        elevations = []
        if let first = result.first {
            elevations = await GeoService.elevations(for: first.coordinates)
        }
    }

    private func clearRoute() {
        routes = []
        elevations = []
        voice.stop()
        followUser = false
    }

    private func updateIsochrone(minutes: Int) async {
        guard minutes > 0, let loc = locationService.location?.coordinate else {
            isoPolygon = []
            return
        }
        isoPolygon = await GeoService.isochrone(center: loc, minutes: minutes,
                                                costing: transport == .walking ? "pedestrian" : "auto")
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
private struct MorphIntroView: View {
    @State private var index = 0
    @State private var morphBlur: CGFloat = 0
    @State private var showTitle = false
    @State private var drift = false

    private let symbols = ["location.fill", "mappin.and.ellipse",
                           "point.topleft.down.to.point.bottomright.curvepath",
                           "mappin.circle.fill"]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.44, blue: 0.72),
                                    Color(red: 0.56, green: 0.38, blue: 0.96),
                                    Color(red: 0.22, green: 0.56, blue: 0.97)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.85).opacity(0.5))
                .frame(width: 300, height: 300).blur(radius: 70)
                .offset(x: drift ? -110 : -60, y: drift ? -330 : -280)
            Circle().fill(Color(red: 0.35, green: 0.75, blue: 1.0).opacity(0.45))
                .frame(width: 320, height: 320).blur(radius: 80)
                .offset(x: drift ? 120 : 70, y: drift ? 300 : 250)

            VStack(spacing: 22) {
                ZStack {
                    ForEach(symbols.indices, id: \.self) { i in
                        Image(systemName: symbols[i])
                            .font(.system(size: 96, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                            .opacity(i == index ? 1 : 0)
                            .scaleEffect(i == index ? 1 : 0.75)
                            .blur(radius: i == index ? morphBlur : 16)
                    }
                }
                .frame(height: 125)
                VStack(spacing: 6) {
                    Text("وجهتي")
                        .font(.system(size: 42, weight: .black)).foregroundStyle(.white)
                    Text("خرائط وملاحة عربية أنيقة")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)
            }
            VStack {
                Spacer()
                Text("من تطوير عبدالباسط خضير")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 26)
            }
        }
        .task { await runSequence() }
    }

    private func runSequence() async {
        withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { drift = true }
        for i in 1..<symbols.count {
            try? await Task.sleep(nanoseconds: 520_000_000)
            withAnimation(.easeIn(duration: 0.16)) { morphBlur = 16 }
            try? await Task.sleep(nanoseconds: 170_000_000)
            index = i
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { morphBlur = 0 }
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        withAnimation(.easeOut(duration: 0.4)) { showTitle = true }
    }
}

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
                Image(systemName: icon).foregroundStyle(Color(white: 0.05))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(place.name).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Spacer()
                Button("اتجاهات") {
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
                let p = Place.make(name: title, address: "موقعي الحالي", lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                saveQuickPlace(p, key: key, isHome: isHome)
                Task {
                    if let resolved = await GeoService.reverse(lat: p.latitude, lon: p.longitude) {
                        saveQuickPlace(Place.make(name: title, address: resolved.address, lat: p.latitude, lon: p.longitude), key: key, isHome: isHome)
                    }
                }
            } label: {
                Label("تعيين \(title) من موقعي الحالي", systemImage: icon)
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
        _name = State(initialValue: place.name == "موقع مُحدد" ? "" : place.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("اسم المكان") {
                    TextField("مثال: مخبز التنور", text: $name)
                }
                Section("النوع") {
                    Picker("النوع", selection: $category) {
                        ForEach(cats, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section("معلومة إضافية (اختياري)") {
                    TextField("ساعات الفتح، رقم، وصف قصير…", text: $note)
                }
                Section {
                    Text(Backend.isConfigured
                         ? "ينشر لكل مستخدمي وجهتي وينحفظ بجهازك."
                         : "ينحفظ بجهازك هسه، وينشر للكل من يشتغل السيرفر المشترك.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("نشر مكان محلي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("نشر") {
                        onPublish(name.trimmingCharacters(in: .whitespaces), category, note)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
