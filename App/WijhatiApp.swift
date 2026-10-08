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

    @AppStorage("wijhati.language") private var language = "ar"
    @StateObject private var store = PlacesStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(language)
                .font(.body.weight(.bold))
                .foregroundStyle(adaptiveInk)
                .environmentObject(store)
                .environmentObject(location)
                .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
                .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
        }
    }
}
