import SwiftUI

@main
struct WijhatiApp: App {
    @StateObject private var store = PlacesStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.dark)
        }
    }
}
