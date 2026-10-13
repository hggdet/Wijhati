import Foundation
import UserNotifications

// MARK: - Local notifications helper
enum Notify {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func fire(title: String,
                     body: String,
                     symbol: String = "bell.fill",
                     tone: InAppNoticeTone = .neutral) {
        Task { @MainActor in
            InAppNoticeCenter.shared.show(title: title, message: body, symbol: symbol, tone: tone)
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
