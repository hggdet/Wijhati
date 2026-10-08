import Foundation
import CoreLocation

// MARK: - Timed live location sharing (link opens the public viewer page)
final class LiveShareService: ObservableObject {
    @Published var active = false
    @Published var endsAt: Date?
    @Published var sessionID: String?
    private var lastUpload: Date = .distantPast
    private var timer: Timer?

    var shareText: String {
        guard let sessionID else { return "" }
        return "تابع موقعي الحي من تطبيق وجهتي 📍\nhttps://hggdet.github.io/Wijhati/live.html?s=\(sessionID)"
    }

    func start(minutes: Int) {
        sessionID = UUID().uuidString.prefix(12).lowercased()
        endsAt = Date().addingTimeInterval(Double(minutes) * 60)
        active = true
        lastUpload = .distantPast
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, let endsAt = self.endsAt, Date() > endsAt else { return }
            self.stop()
        }
    }

    func moved(to location: CLLocation) {
        guard active, let sessionID, let endsAt else { return }
        guard Date().timeIntervalSince(lastUpload) > 12 else { return }
        lastUpload = Date()
        Task {
            await Backend.upsert(table: "live_locations", payload: [
                "id": sessionID,
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "updated_at": ISOTime.string(Date()),
                "expires_at": ISOTime.string(endsAt)
            ])
        }
    }

    func stop() {
        active = false
        endsAt = nil
        timer?.invalidate()
        timer = nil
    }

    var remainingText: String {
        guard let endsAt else { return "" }
        let mins = max(Int(endsAt.timeIntervalSinceNow / 60), 0)
        return mins >= 1 ? "باقي \(mins) دقيقة" : "تنتهي خلال ثوانٍ"
    }
}
