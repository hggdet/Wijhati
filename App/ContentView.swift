import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct CategoryItem: Identifiable {
    var id: String { title }
    var title: String
    var query: String
    var icon: String
}

struct ContentView: View {
    @EnvironmentObject var store: PlacesStore
    @EnvironmentObject var location: LocationService
    @StateObject private var search = SearchService()
    @StateObject private var voice = VoiceGuide()

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661),
                           latitudinalMeters: 20000, longitudinalMeters: 20000))
    @State private var mapStyleKind: Int = 0
    @State private var selected: PlaceResult?
    @State private var routes: [MKRoute] = []
    @State private var routeIndex: Int = 0
    @State private var transport: TransportChoice = .driving
    @State private var nearbyResults: [PlaceResult] = []
    @State private var activeCategory: String?
    @State private var showSaved = false
    @State private var navigating = false
    @State private var isRouting = false
    @State private var routeError: String?

    private let categories: [CategoryItem] = [
        CategoryItem(title: "مطاعم", query: "restaurant", icon: "fork.knife"),
        CategoryItem(title: "كافيهات", query: "cafe", icon: "cup.and.saucer.fill"),
        CategoryItem(title: "فنادق", query: "hotel", icon: "bed.double.fill"),
        CategoryItem(title: "مستشفيات", query: "hospital", icon: "cross.case.fill"),
        CategoryItem(title: "صيدليات", query: "pharmacy", icon: "pills.fill"),
        CategoryItem(title: "محطات وقود", query: "gas station", icon: "fuelpump.fill"),
        CategoryItem(title: "حدائق", query: "park", icon: "tree.fill"),
        CategoryItem(title: "تسوق", query: "mall", icon: "bag.fill")
    ]

    private var currentRoute: MKRoute? {
        routes.indices.contains(routeIndex) ? routes[routeIndex] : nil
    }

    private var mapStyle: MapStyle {
        switch mapStyleKind {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic, emphasis: .muted)
        }
    }

    private var referenceCoordinate: CLLocationCoordinate2D {
        location.location?.coordinate ?? CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                UserAnnotation()
                if let selected {
                    Marker(selected.name, coordinate: selected.coordinate)
                        .tint(.pink)
                }
                ForEach(store.places) { place in
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(place.isFavorite ? .orange : .teal)
                }
                ForEach(nearbyResults) { place in
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(.blue)
                }
                if let route = currentRoute {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }
            }
            .mapStyle(mapStyle)
            .ignoresSafeArea()

            VStack(spacing: 10) {
                searchBar
                if !search.query.isEmpty && !search.completions.isEmpty {
                    completionsPanel
                }
                categoryChips
                Spacer()
                sideControls
                bottomPanel
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if voice.active {
                pocketOverlay
            }
        }
        .onAppear {
            location.request()
        }
        .onChange(of: location.location) { _, newValue in
            if navigating, let loc = newValue {
                voice.update(location: loc)
                if !voice.active {
                    navigating = false
                }
            }
        }
    }

    // MARK: - Top UI

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("ابحث عن مكان أو عنوان", text: $search.query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit { Task { await runTextSearch() } }
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glass(cornerRadius: 26)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var completionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.completions.prefix(6), id: \.title) { item in
                Button {
                    Task {
                        if let place = await search.resolve(item) {
                            selectPlace(place)
                            search.query = ""
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                Divider().opacity(0.4)
            }
        }
        .glass(cornerRadius: 22)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    Button {
                        Task { await loadCategory(cat) }
                    } label: {
                        Label(cat.title, systemImage: cat.icon)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(GlassButtonStyle())
                    .foregroundStyle(activeCategory == cat.title ? Color.orange : Color.primary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var sideControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                controlButton(icon: "location.fill") { centerOnUser() }
                controlButton(icon: mapStyleKind == 0 ? "map" : (mapStyleKind == 1 ? "globe.americas.fill" : "photo")) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        mapStyleKind = (mapStyleKind + 1) % 3
                    }
                }
                controlButton(icon: showSaved ? "bookmark.fill" : "bookmark") {
                    withAnimation { showSaved.toggle() }
                }
            }
        }
    }

    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .glass(cornerRadius: 22)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }

    // MARK: - Bottom panels

    @ViewBuilder
    private var bottomPanel: some View {
        if navigating, let route = currentRoute {
            navigationCard(route)
        } else if let selected {
            placeCard(selected)
        } else if showSaved {
            savedPanel
        }
    }

    private func placeCard(_ place: PlaceResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).font(.title3.weight(.bold))
                    if !place.address.isEmpty {
                        Text(place.address).font(.caption).foregroundStyle(.secondary)
                    }
                    if let userLoc = location.location {
                        let d = userLoc.distance(from: CLLocation(latitude: place.coordinate.latitude,
                                                                    longitude: place.coordinate.longitude))
                        Text("يبعد عنك \(formatDistance(d))")
                            .font(.caption.weight(.medium)).foregroundStyle(.teal)
                    }
                }
                Spacer()
                Button {
                    selected = nil
                    routes = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            Picker("وسيلة النقل", selection: $transport) {
                ForEach(TransportChoice.allCases) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: transport) { _, _ in
                if selected != nil { Task { await getDirections() } }
            }

            if isRouting {
                HStack { ProgressView(); Text("جارٍ حساب المسار...").font(.caption) }
            } else if !routes.isEmpty {
                routeAlternatives
            }
            if let routeError {
                Text(routeError).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await getDirections() }
                } label: {
                    Label("الاتجاهات", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(GlassButtonStyle())

                Button {
                    let saved = place.asSavedPlace
                    _ = store.toggle(saved)
                } label: {
                    Label(store.contains(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude) ? "محفوظ" : "حفظ",
                          systemImage: store.contains(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(GlassButtonStyle())

                ShareLink(item: place.appleMapsURL) {
                    Label("مشاركة", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassButtonStyle())

                if let phone = place.phone,
                   let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Label("اتصال", systemImage: "phone.fill")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
            .font(.subheadline)

            if let route = currentRoute {
                HStack(spacing: 8) {
                    Button {
                        startNavigation(route)
                    } label: {
                        Label("ابدأ الملاحة", systemImage: "location.north.line.fill")
                    }
                    .buttonStyle(GlassButtonStyle())
                    Button {
                        voice.start(route: route)
                    } label: {
                        Label("ملاحة بالجيب", systemImage: "waveform")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(16)
        .glass(cornerRadius: 28)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var routeAlternatives: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(routes.indices, id: \.self) { i in
                let r = routes[i]
                Button {
                    routeIndex = i
                } label: {
                    HStack {
                        Image(systemName: i == routeIndex ? "checkmark.circle.fill" : "circle")
                        Text(r.name.isEmpty ? "مسار \(i + 1)" : r.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(formatDuration(r.expectedTravelTime)) · \(formatDistance(r.distance))")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(i == routeIndex ? Color.blue.opacity(0.22) : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func navigationCard(_ route: MKRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "location.north.fill").foregroundStyle(.blue)
                Text(voice.currentInstruction.isEmpty ? "اتبع المسار" : voice.currentInstruction)
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 14) {
                Label(formatDuration(route.expectedTravelTime), systemImage: "clock")
                Label(formatDistance(route.distance), systemImage: "road.lanes")
                Spacer()
                Button("إنهاء") {
                    navigating = false
                    voice.stop()
                }
                .buttonStyle(GlassButtonStyle())
            }
            .font(.subheadline)
        }
        .padding(16)
        .glass(cornerRadius: 26)
    }

    private var savedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("أماكني المحفوظة").font(.headline)
            if store.places.isEmpty {
                Text("لا توجد أماكن محفوظة بعد. ابحث عن مكان واضغط «حفظ».")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.places) { place in
                            HStack {
                                Button {
                                    selectPlace(PlaceResult(saved: place))
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name).font(.subheadline.weight(.semibold))
                                        Text(place.address).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    store.setFavorite(place, !place.isFavorite)
                                } label: {
                                    Image(systemName: place.isFavorite ? "star.fill" : "star")
                                        .foregroundStyle(.orange)
                                }
                                Button {
                                    store.remove(place)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(16)
        .glass(cornerRadius: 26)
    }

    private var pocketOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.teal)
                    .rotationEffect(.degrees(-location.heading))
                Text(voice.currentInstruction)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal)
                if voice.distanceToNext > 0 {
                    Text(formatDistance(voice.distanceToNext))
                        .font(.title.weight(.heavy))
                        .foregroundStyle(.white)
                }
                Button {
                    voice.stop()
                    navigating = false
                } label: {
                    Text("إيقاف الملاحة")
                        .font(.headline)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(Color.red, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, 10)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func centerOnUser() {
        if let loc = location.location {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                camera = .region(MKCoordinateRegion(center: loc.coordinate,
                                                    latitudinalMeters: 2500,
                                                    longitudinalMeters: 2500))
            }
        } else {
            location.request()
        }
    }

    private func selectPlace(_ place: PlaceResult) {
        selected = place
        routes = []
        routeError = nil
        showSaved = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            camera = .region(MKCoordinateRegion(center: place.coordinate,
                                                latitudinalMeters: 2200,
                                                longitudinalMeters: 2200))
        }
    }

    private func runTextSearch() async {
        let region = MKCoordinateRegion(center: referenceCoordinate,
                                        latitudinalMeters: 60000,
                                        longitudinalMeters: 60000)
        let results = await search.searchText(search.query, near: region)
        if let first = results.first {
            nearbyResults = results
            selectPlace(first)
        }
    }

    private func loadCategory(_ category: CategoryItem) async {
        activeCategory = category.title
        let results = await search.nearby(categoryQuery: category.query, near: referenceCoordinate)
        nearbyResults = results
        if let first = results.first {
            withAnimation {
                camera = .region(MKCoordinateRegion(center: first.coordinate,
                                                    latitudinalMeters: 6000,
                                                    longitudinalMeters: 6000))
            }
        }
    }

    private func getDirections() async {
        guard let destination = selected else { return }
        isRouting = true
        routeError = nil
        defer { isRouting = false }

        let request = MKDirections.Request()
        if let userLoc = location.location {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLoc.coordinate))
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: referenceCoordinate))
        }
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = transport.mkType
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            routes = response.routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime }
            routeIndex = 0
            if let route = routes.first {
                withAnimation {
                    camera = .rect(route.polyline.boundingMapRect.insetBy(dx: -3000, dy: -3000))
                }
            }
        } catch {
            routeError = "تعذّر حساب المسار لهذه الوجهة بهذه الوسيلة."
        }
    }

    private func startNavigation(_ route: MKRoute) {
        navigating = true
        voice.start(route: route)
        centerOnUser()
    }
}
