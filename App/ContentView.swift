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

    @AppStorage("wijhati.tempUnit") private var tempUnit = "c"

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

    private var selectedRoute: RouteData? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }
    private var altCoords: [CLLocationCoordinate2D] {
        routes.enumerated().filter { $0.offset != selectedRouteIndex }.first?.element.coordinates ?? []
    }

    private func displayTemp(_ celsius: Double) -> String {
        if tempUnit == "f" { return "\(Int((celsius * 9 / 5 + 32).rounded()))°F" }
        return "\(Int(celsius.rounded()))°C"
    }

    var body: some View {
        ZStack {
            MapBridge(
                pins: pins,
                routeCoords: selectedRoute?.coordinates ?? [],
                altRouteCoords: altCoords,
                tripCoords: [],
                isoPolygon: isoPolygon,
                styleKind: styleKind,
                show3D: show3D,
                radarTimestamp: radarOn ? radarTS : nil,
                followUser: followUser,
                centerRequest: centerRequest,
                northReset: northReset,
                onSelectPin: { place in select(place) },
                onLongPress: { coordinate in handleLongPress(coordinate) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                if showWeatherDetail, let w = localWeather { weatherDetailCard(w) }
                Spacer()
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
            refreshLocalWeatherIfNeeded(loc.coordinate)
        }
        .sheet(isPresented: $showSaved) { savedSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(item: $shareItem) { payload in
            ShareSheet(text: payload.text)
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
                followUser = false
                if let loc = locationService.location {
                    centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
                }
            } label: {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 17, weight: .semibold))
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
            if let place = selected, selectedRoute == nil { placeCard(place) }
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
                Label(formatDistance(route.distance), systemImage: "arrow.triangle.swap")
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
                        Text("يبعد \(formatDistance(d)) عنك").font(.caption2).foregroundStyle(.secondary)
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
                    Text(formatDistance(voice.distanceToNext)).font(.headline).foregroundStyle(.gray)
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
                Section {
                    Button {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showSaved = true }
                    } label: {
                        Label("أماكني المحفوظة", systemImage: "bookmark.fill")
                    }
                }
                Section("حول التطبيق") {
                    HStack {
                        Text("التطبيق")
                        Spacer()
                        Text("وجهتي — Wijhati").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("الإصدار")
                        Spacer()
                        Text("1.2").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("المطوّر")
                        Spacer()
                        Text("عبدالباسط خضير").foregroundStyle(.secondary)
                    }
                    Text("تطبيق خرائط عالمي ببيانات OpenStreetMap ومحرك MapLibre، صُمم وبُني بحب للملاحة العربية.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showSettings = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func select(_ place: Place) {
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
