import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for the daily reminder. Local
/// notifications only — no remote push, no server, no tracking.
///
/// One scheduled trigger ID (`cueflow.daily`), `repeats: true`, fires at the
/// user-picked hour/minute every day. Cancelling and re-scheduling is the
/// way to "change the time".
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let dailyIdentifier = "cueflow.daily"

    /// Asks the user for permission. Returns true if granted. Safe to call
    /// repeatedly — iOS only shows the prompt the first time.
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Replaces any existing daily reminder with one at the given local time.
    func scheduleDailyReminder(hour: Int, minute: Int) async {
        cancelDailyReminder()

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "CueFlow"
        content.body = "Magst du heute ein paar Karten machen?"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyIdentifier,
            content: content,
            trigger: trigger
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
    }

    /// Snapshot of what's currently scheduled. Useful for debugging and the
    /// `LanguageLearningApp` startup re-sync.
    func pendingDailyTimeComponents() async -> DateComponents? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard
            let request = requests.first(where: { $0.identifier == dailyIdentifier }),
            let trigger = request.trigger as? UNCalendarNotificationTrigger
        else { return nil }
        return trigger.dateComponents
    }
}
