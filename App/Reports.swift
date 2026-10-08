import Foundation
import CoreLocation
import UserNotifications

// MARK: - Waze-style road reports (stored locally on device)

struct ReportKind {
    var key: String
    var title: String
    var emoji: String
}

let reportKinds: [ReportKind] = [
    ReportKind(key: "traffic", title: "ازدحام", emoji: "🚗"),
    ReportKind(key: "police", title: "شرطة", emoji: "👮"),
    ReportKind(key: "crash", title: "حادث", emoji: "💥"),
    ReportKind(key: "hazard", title: "خطر", emoji: "⚠️"),
    ReportKind(key: "closure", title: "إغلاق طريق", emoji: "🚧"),
    ReportKind(key: "blocked", title: "ممر مسدود", emoji: "🚦"),
    ReportKind(key: "weather", title: "طقس سيئ", emoji: "🌩"),
    ReportKind(key: "mapissue", title: "مشكلة بالخريطة", emoji: "🗺"),
    ReportKind(key: "animal", title: "حيوان على الطريق", emoji: "🐄"),
    ReportKind(key: "fuel", title: "أسعار وقود", emoji: "⛽"),
]

struct RoadReport: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var confirmedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var kindInfo: ReportKind {
        reportKinds.first { $0.key == kind } ?? reportKinds[3]
    }
    var ageText: String {
        let mins = max(Int(Date().timeIntervalSince(confirmedAt) / 60), 0)
        if mins < 1 { return "الآن" }
        if mins < 60 { return "قبل \(mins) د" }
        return "قبل \(mins / 60) س"
    }
    func asPlace() -> Place {
        Place(id: "report-\(id)", name: "\(kindInfo.emoji) \(kindInfo.title)",
              address: "بلاغ طريق • \(ageText)", latitude: latitude, longitude: longitude,
              phone: nil, website: nil)
    }
}

final class ReportsStore: ObservableObject {
    @Published var reports: [RoadReport] = [] { didSet { persist() } }
    private let key = "wijhati.reports.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([RoadReport].self, from: data) {
            reports = decoded
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    /// Reports younger than 3 hours since last confirmation.
    var activeReports: [RoadReport] {
        reports.filter { Date().timeIntervalSince($0.confirmedAt) < 3 * 3600 }
    }
    @discardableResult
    func add(kind: String, at coordinate: CLLocationCoordinate2D) -> RoadReport {
        let report = RoadReport(id: UUID().uuidString, kind: kind,
                                latitude: coordinate.latitude, longitude: coordinate.longitude,
                                createdAt: Date(), confirmedAt: Date())
        reports.append(report)
        Task { await CommunityStore.uploadReport(report) }
        return report
    }
    func confirm(_ id: String) {
        if let idx = reports.firstIndex(where: { $0.id == id }) {
            reports[idx].confirmedAt = Date()
        }
    }
    func remove(_ id: String) {
        reports.removeAll { $0.id == id }
    }
}

// MARK: - Local notifications helper

enum Notify {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func fire(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
