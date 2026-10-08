import SwiftUI
import MapLibre

@main
struct WijhatiApp: App {
    init() {
        // Generous tile cache (512 MB): places the user already viewed
        // reload instantly instead of downloading again.
        MLNOfflineStorage.shared.setMaximumAmbientCacheSize(512 * 1024 * 1024) { _ in }
        MapStyleKind.prepareArabicStyles()
    }

    @StateObject private var store = PlacesStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        }
    }
}
