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
    @StateObject private var reportsStore = ReportsStore()
    @StateObject private var offlineManager = OfflineManager()

    @AppStorage("wijhati.tempUnit") private var tempUnit = "c"
    @AppStorage("wijhati.appearance") private var appearance = "auto"
    @AppStorage("wijhati.distanceUnit") private var distanceUnit = "auto"
    @AppStorage("wijhati.notifReports") private var notifReports = true
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
    @State private var showReportSheet = false
    @State private var reportSelectedID: String?
    @State private var reportThanks = false
    @State private var categoryNotice: String?
    @State private var currentStreet: String?
    @State private var streetAnchor: CLLocation?
    @State private var streetFetchedAt: Date?
    @State private var alertCooldown: [String: Date] = [:]

    private var allPins: [Place] {
        pins + reportsStore.activeReports.map { $0.asPlace() }
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
                northReset: northReset,
                onSelectPin: { place in select(place) },
                onLongPress: { coordinate in handleLongPress(coordinate) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                statusPills
                if showWeatherDetail, let w = localWeather { weatherDetailCard(w) }
                Spacer()
                if let categoryNotice {
                    Text(categoryNotice)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glass(cornerRadius: 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if reportThanks {
                    Text("شكراً! بلاغك انحفظ ويظهر على الخريطة 🙏")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .glass(cornerRadius: 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack {
                    Button { showReportSheet = true } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.orange)
                            .frame(width: 52, height: 52)
                    }
                    .glass(cornerRadius: 26)

                    Spacer()

                    Button {
                        followUser = false
                        if let loc = locationService.location {
                            centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.blue)
                            .frame(width: 52, height: 52)
                    }
                    .glass(cornerRadius: 26)
                }
                bottomStack
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if voice.active { pocketOverlay }
        }
        .onAppear {
            locationService.request()
            if let loc = locationService.location {
                centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 13)
            }
        }
        .onChange(of: locationService.location) { _, newValue in
            guard let loc = newValue else { return }
            voice.update(userLocation: loc)
            updateCurrentStreet(loc)
            refreshLocalWeatherIfNeeded(loc.coordinate)
            checkProximity(loc)
        }
        .preferredColorScheme(schemeOverride)
        .sheet(isPresented: $showSaved) { savedSheet }
        .sheet(isPresented: $showReportSheet) { reportSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(item: $shareItem) { payload in
            ShareSheet(text: payload.text)
        }
    }

    @ViewBuilder
    private var statusPills: some View {
        if !voice.active, currentStreet != nil || (locationService.location?.speed ?? -1) > 3 {
            HStack(spacing: 6) {
                Spacer()
                if let street = currentStreet {
                    Label(street, systemImage: "road.lanes")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glass(cornerRadius: 14)
                }
                if let loc = locationService.location, loc.speed > 3 {
                    Text("\(Int((loc.speed * 3.6).rounded())) كم/س")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glass(cornerRadius: 14)
                }
                Spacer()
            }
            .transition(.opacity)
        }
    }

    private func updateCurrentStreet(_ loc: CLLocation) {
        if let anchor = streetAnchor, let at = streetFetchedAt,
           loc.distance(from: anchor) < 75, Date().timeIntervalSince(at) < 30 { return }
        streetAnchor = loc
        streetFetchedAt = Date()
        Task {
            if let name = await GeoService.currentStreet(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) {
                currentStreet = name
            }
        }
    }

    // MARK: - Top bar (weather + compass)

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { showWeatherDetail.toggle(); refreshLocalWeatherIfNeeded(locationService.location?.coordinate, force: true) } label: {
                VStack(spacing: 1) {
                    Image(systemName: "cloud.sun.fill").font(.system(size: 15))
                    Text(localWeather.map { displayTemp($0.temperature) } ?? "—")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(width: 46, height: 46)
            }
            .glass(cornerRadius: 23)

            Spacer()

            Button {
                northReset += 1
            } label: {
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 11)).foregroundStyle(.red).offset(y: -8)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 11)).foregroundStyle(.secondary).offset(y: 8)
                    Circle().fill(Color.primary).frame(width: 4, height: 4)
                }
                .rotationEffect(.degrees(-locationService.heading))
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

    // MARK: - Bottom stack

    private var bottomStack: some View {
        VStack(spacing: 8) {
            if let rid = reportSelectedID, let report = reportsStore.activeReports.first(where: { $0.id == rid }) {
                reportCard(report)
            } else if let place = selected, selectedRoute == nil { placeCard(place) }
            if let route = selectedRoute { routeBar(route) }
            if !stops.isEmpty { stopsBar }
            if !suggestions.isEmpty { suggestionsList }
            categoryChips
            HStack(spacing: 8) {
                searchBar
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 46, height: 46)
                }
                .glass(cornerRadius: 23)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("ابحث عن مكان أو عنوان", text: $query)
                .font(.subheadline)
                .onSubmit { Task { await runSearch() } }
                .onChange(of: query) { _, newValue in
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard query == newValue else { return }
                        if newValue.trimmingCharacters(in: .whitespaces).count >= 3 {
                            suggestions = await GeoService.search(newValue, near: locationService.location?.coordinate, limit: 6)
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
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .glass(cornerRadius: 23)
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { place in
                Button { select(place); suggestions = [] } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            if !place.address.isEmpty {
                                Text(place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                Divider().opacity(0.4)
            }
        }
        .glass(cornerRadius: 18)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(categories) { cat in
                    Button { Task { await loadCategory(cat) } } label: {
                        Label(cat.title, systemImage: cat.icon).fixedSize()
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 2)
        }
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
                Label(formatDuration(route.duration), systemImage: "clock")
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
        }
        .padding(12)
        .glass(cornerRadius: 20)
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
                                .foregroundStyle(saved.isFavorite ? .yellow : .blue)
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
                        Button { shareItem = SharePayload(text: text) } label: {
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
                    ForEach(MapStyleKind.allCases, id: \.self) { kind in
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
                Button {
                    shareItem = SharePayload(text: "جرّب تطبيق وجهتي — خرائط وملاحة عربية أنيقة 🗺")
                } label: {
                    Label("مشاركة التطبيق مع صديق", systemImage: "square.and.arrow.up")
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
                HStack { Text("الإصدار"); Spacer(); Text("1.8").foregroundStyle(.secondary) }
                HStack { Text("المطوّر"); Spacer(); Text("عبدالباسط خضير").foregroundStyle(.secondary) }
                HStack { Text("المحرك"); Spacer(); Text("MapLibre").foregroundStyle(.secondary) }
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
                Toggle("تنبيه عند الاقتراب من بلاغ طريق", isOn: $notifReports)
                    .onChange(of: notifReports) { _, on in if on { Notify.requestPermission() } }
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

    // MARK: - Road reports UI

    private var reportSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(reportKinds, id: \.key) { kind in
                        Button { submitReport(kind) } label: {
                            VStack(spacing: 7) {
                                Text(kind.emoji).font(.system(size: 34))
                                    .frame(width: 64, height: 64)
                                    .glass(cornerRadius: 32)
                                Text(kind.title).font(.caption.weight(.medium)).foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .navigationTitle("شنو شفت بالطريق؟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showReportSheet = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func reportCard(_ report: RoadReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(report.kindInfo.emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.kindInfo.title).font(.headline)
                    Text("بلاغ طريق • \(report.ageText)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { reportSelectedID = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 7) {
                Button {
                    reportsStore.confirm(report.id)
                    reportSelectedID = nil
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("بعده موجود", systemImage: "hand.thumbsup.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                }
                Button {
                    reportsStore.remove(report.id)
                    reportSelectedID = nil
                } label: {
                    Label("زال خلاص", systemImage: "hand.thumbsdown")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func submitReport(_ kind: ReportKind) {
        let coordinate = locationService.location?.coordinate
            ?? selected?.coordinate
            ?? CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661)
        reportsStore.add(kind: kind.key, at: coordinate)
        showReportSheet = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { reportThanks = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { reportThanks = false }
        }
    }

    private func checkProximity(_ loc: CLLocation) {
        let now = Date()
        func cooling(_ key: String) -> Bool {
            if let last = alertCooldown[key], now.timeIntervalSince(last) < 900 { return true }
            alertCooldown[key] = now
            return false
        }
        if notifReports {
            for report in reportsStore.activeReports {
                let d = loc.distance(from: CLLocation(latitude: report.latitude, longitude: report.longitude))
                if d < 600, !cooling("rep-\(report.id)") {
                    let text = "تنبيه: \(report.kindInfo.title) على بعد \(fmtDist(d))"
                    voice.announce(text)
                    Notify.fire(title: "وجهتي — تنبيه طريق", body: text)
                }
            }
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

    private func select(_ place: Place) {
        if place.id.hasPrefix("report-") {
            reportSelectedID = String(place.id.dropFirst("report-".count))
            selected = nil
            suggestions = []
            return
        }
        reportSelectedID = nil
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

    private func loadCategory(_ cat: Category) async {
        guard let loc = locationService.location else { return }
        searching = true
        let results = await GeoService.nearby(amenity: cat.key, group: cat.group, near: loc.coordinate)
        searching = false
        pins = results
        if !results.isEmpty {
            centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 13)
            selected = nil
        } else {
            categoryNotice = "ما لقينا \(cat.title) قريبة منك حالياً"
            Task { try? await Task.sleep(nanoseconds: 2_600_000_000); categoryNotice = nil }
        }
    }

    private func computeRoute() async {
        guard let origin = locationService.location?.coordinate, let dest = selected else { return }
        loadingRoute = true
        let result = await GeoService.route(from: origin, waypoints: stops.map { $0.coordinate },
                                            to: dest.coordinate, profile: transport.osrmProfile)
        loadingRoute = false
        routes = result
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
