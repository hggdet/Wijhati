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
    @StateObject private var tripsStore = TripsStore()
    @StateObject private var voice = VoiceGuide()

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

    @State private var showSaved = false
    @State private var showTrips = false
    @State private var showLayers = false
    @State private var show3D = false
    @State private var radarOn = false
    @State private var radarTS: Int?
    @State private var isoMinutes: Int = 0
    @State private var isoPolygon: [CLLocationCoordinate2D] = []

    @State private var weather: GeoService.WeatherNow?
    @State private var elevations: [Double] = []
    @State private var shareItem: SharePayload?
    @State private var recordElapsed: TimeInterval = 0
    @State private var nowTick = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var selectedRoute: RouteData? {
        routes.indices.contains(selectedRouteIndex) ? routes[selectedRouteIndex] : nil
    }
    private var altCoords: [CLLocationCoordinate2D] {
        routes.enumerated().filter { $0.offset != selectedRouteIndex }.first?.element.coordinates ?? []
    }

    var body: some View {
        ZStack(alignment: .top) {
            MapBridge(
                pins: pins,
                routeCoords: selectedRoute?.coordinates ?? [],
                altRouteCoords: altCoords,
                tripCoords: locationService.recordedPoints.map { $0.coordinate },
                isoPolygon: isoPolygon,
                styleKind: styleKind,
                show3D: show3D,
                radarTimestamp: radarOn ? radarTS : nil,
                followUser: followUser,
                centerRequest: centerRequest,
                onSelectPin: { place in select(place) }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                searchBar
                if !suggestions.isEmpty { suggestionsList }
                categoryChips
                if !stops.isEmpty { stopsBar }
                Spacer()
                if locationService.recording { recordingBar }
                if let route = selectedRoute { routeBar(route) }
                sideControlsRow
                if let place = selected, selectedRoute == nil { placeCard(place) }
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
            if let loc = newValue { voice.update(userLocation: loc) }
        }
        .onReceive(tick) { date in
            nowTick = date
            if let start = locationService.recordStartedAt {
                recordElapsed = date.timeIntervalSince(start)
            }
        }
        .sheet(isPresented: $showSaved) { savedSheet }
        .sheet(isPresented: $showTrips) { tripsSheet }
        .sheet(isPresented: $showLayers) { layersSheet }
        .sheet(item: $shareItem) { payload in
            ShareSheet(text: payload.text)
        }
    }

    // MARK: - Top UI

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
        .padding(.vertical, 10)
        .glass(cornerRadius: 22)
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

    private var sideControlsRow: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 9) {
                GlassCircleButton(icon: followUser ? "location.fill" : "location") {
                    followUser.toggle()
                    if followUser, let loc = locationService.location {
                        centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 15)
                    }
                }
                GlassCircleButton(icon: "square.3.layers.3d") { showLayers = true }
                GlassCircleButton(icon: locationService.recording ? "stop.circle.fill" : "record.circle") {
                    toggleRecording()
                }
                .foregroundStyle(locationService.recording ? .red : .blue)
                GlassCircleButton(icon: "bookmark.fill") { showSaved = true }
                GlassCircleButton(icon: "figure.walk.motion") { showTrips = true }
            }
            Spacer()
        }
    }

    // MARK: - Recording

    private var recordingBar: some View {
        HStack(spacing: 14) {
            Circle().fill(.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text("تسجيل رحلة").font(.caption.weight(.bold))
                Text("\(formatDuration(recordElapsed)) • \(formatDistance(locationService.recordedDistance))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let loc = locationService.location {
                Text(String(format: "%.0f كم/س", max(loc.speed, 0) * 3.6)).font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(cornerRadius: 16)
    }

    private func toggleRecording() {
        if locationService.recording {
            if let trip = locationService.stopRecording() {
                tripsStore.add(trip)
            }
        } else {
            locationService.startRecording()
            recordElapsed = 0
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
                        let d = loc.distance(from: CLLocation(coordinate: place.coordinate))
                        Text("يبعد \(formatDistance(d)) عنك").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let w = weather {
                        Text("🌡 \(Int(w.temperature.rounded()))° \(w.label) • شروق \(w.sunrise) • غروب \(w.sunset)")
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
                    Label(store.contains(place) ? "محفوظ" : "حفظ", systemImage: store.contains(place) ? "bookmark.fill" : "bookmark")
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
                    Image(systemName: "square.and.arrow.up")
                        .padding(8).background(Color.white.opacity(0.14), in: Circle())
                }
            }
        }
        .padding(12)
        .glass(cornerRadius: 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: place.id) {
            weather = await GeoService.weather(lat: place.latitude, lon: place.longitude)
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
                Button { voice.stop() } label: {
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

    private var tripsSheet: some View {
        NavigationStack {
            List {
                if tripsStore.trips.isEmpty {
                    Text("لا توجد رحلات مسجلة بعد. اضغط زر التسجيل وابدأ.").foregroundStyle(.secondary)
                }
                ForEach(tripsStore.trips) { trip in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.medium))
                            Text("\(formatDistance(trip.distance)) • \(formatDuration(trip.duration)) • متوسط \(String(format: "%.0f", trip.averageSpeedKmh)) كم/س")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { shareItem = SharePayload(text: trip.gpx()) } label: {
                            Label("GPX", systemImage: "square.and.arrow.up").font(.caption)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { tripsStore.remove(trip) } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("رحلاتي")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showTrips = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var layersSheet: some View {
        NavigationStack {
            Form {
                Section("نمط الخريطة") {
                    Picker("النمط", selection: $styleKind) {
                        ForEach(MapStyleKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
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
            .navigationTitle("الطبقات والمميزات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("إغلاق") { showLayers = false } } }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func select(_ place: Place) {
        selected = place
        suggestions = []
        if !pins.contains(place) { pins = [place] }
        centerRequest = CenterRequest(coordinate: place.coordinate, zoom: 15)
        followUser = false
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
        if let first = results.first {
            centerRequest = CenterRequest(coordinate: loc.coordinate, zoom: 13)
            selected = nil
            _ = first
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

struct GlassCircleButton: View {
    var icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
        }
        .glass(cornerRadius: 21)
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
