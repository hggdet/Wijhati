import SwiftUI

@main
struct WijhatiApp: App {
    @AppStorage("wijhati.language") private var language = "ar"
    @StateObject private var store = PlacesStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .font(.body)
                .fontDesign(.rounded)
                .buttonStyle(AppPressStyle())
                .foregroundStyle(adaptiveInk)
                .environmentObject(store)
                .environmentObject(location)
                .environment(\.layoutDirection, language == "en" ? .leftToRight : .rightToLeft)
                .environment(\.locale, Locale(identifier: language == "ku" ? "ckb" : language))
        }
    }
}
