import UserNotifications

enum NotificationHelper {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { print("[Notifications] Permission error: \(error)") }
            print("[Notifications] Permission granted: \(granted)")
        }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[Notifications] Failed to send: \(error)") }
        }
    }
}
