import Foundation
import UserNotifications
import os

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.haydenfd.memcheck", category: "notifications")
    private var notifiedStates = Set<MemoryHealthState>()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                let status = await center.notificationSettings().authorizationStatus.rawValue
                logger.error("Notification permission failed (status \(status)): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func entered(_ state: MemoryHealthState) {
        if state == .normal {
            notifiedStates.removeAll()
        } else {
            guard notifiedStates.insert(state).inserted else { return }
        }

        let content = UNMutableNotificationContent()
        switch state {
        case .normal:
            content.title = "Memory looks good again"
            content.body = "Memory pressure has returned to normal."
        case .warning:
            content.title = "Memory pressure is high"
            content.body = "Quit apps you don't need if your Mac feels slow."
            content.sound = .default
        case .critical:
            content.title = "Memory pressure is critical"
            content.body = "Quit memory-heavy apps now to reduce slowdowns."
            content.sound = .default
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
            } catch {
                logger.error("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(notification.request.content.sound == nil ? [.banner] : [.banner, .sound])
    }
}
