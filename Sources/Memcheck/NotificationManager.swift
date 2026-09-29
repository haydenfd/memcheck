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
                logger.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func entered(_ state: MemoryHealthState) {
        if state == .normal {
            notifiedStates.removeAll()
            return
        }
        guard notifiedStates.insert(state).inserted else { return }

        let content = UNMutableNotificationContent()
        content.title = state == .critical ? "Memory pressure is critical" : "Memory pressure is elevated"
        content.body = state == .critical
            ? "Consider closing memory-intensive applications."
            : "Some applications may begin using significant swap."
        content.sound = .default
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
        completionHandler([.banner, .sound])
    }
}
