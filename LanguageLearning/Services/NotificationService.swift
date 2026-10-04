import Foundation
import UserNotifications
import UIKit

/// Wraps `UNUserNotificationCenter` for the daily reminder. Local
/// notifications only — no remote push, no server, no tracking.
///
/// A finite seven-day horizon of non-repeating requests honors selected study
/// days and can omit today after completion. Opening the app refreshes it.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let dailyIdentifier = "cueflow.daily"
    private let weeklyIdentifier = "cueflow.weekly-recap"
    private var dailyGeneration = UUID()
    private var dailyRequestIDs: Set<String> = []
    func installRouting() { UNUserNotificationCenter.current().delegate = self }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String,
              let url = URL(string: route), url.scheme == "cueflow" else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }

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
    func scheduleDailyReminder(hour: Int, minute: Int, episode: LearningEpisode? = nil,
                               completedToday: Bool = false, weekdays: [Int]? = nil) async {
        cancelDailyReminder()
        let generation = dailyGeneration
        let calendar = Calendar.current
        let now = Date.now
        for offset in 0..<7 {
            guard generation == dailyGeneration else { return }
            guard !(offset == 0 && completedToday),
                  let day = calendar.date(byAdding: .day, value: offset, to: now),
                  weekdays?.contains(calendar.component(.weekday, from: day)) ?? true,
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), date > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "CueFlow"
            // Future/offline reminders never assert that something is still due.
            content.body = episode.map { "Zeit für eine kurze Alltagssituation? \($0.title)" } ?? "Zeit für eine kleine Sprachpause? Eine kurze Runde reicht."
            content.userInfo = ["route": episode.map { "cueflow://episode/\($0.id)" } ?? "cueflow://practice"]
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = dailyIdentifier + ".\(generation.uuidString).\(offset)"
            dailyRequestIDs.insert(identifier)
            try? await UNUserNotificationCenter.current().add(.init(identifier: identifier, content: content, trigger: trigger))
            if generation != dailyGeneration {
                // A newer schedule/off action won while UNUserNotificationCenter
                // was awaiting. Unique generation IDs cannot remove its requests.
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                return
            }
        }
    }

    func cancelDailyReminder() {
        dailyGeneration = UUID()
        let known = Array(dailyRequestIDs)
        dailyRequestIDs.removeAll()
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: known + [dailyIdentifier] + (0..<7).map { dailyIdentifier + ".\($0)" })
        Task {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let stale = pending.filter { $0.identifier.hasPrefix(dailyIdentifier) && !dailyRequestIDs.contains($0.identifier) }.map(\.identifier)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    func scheduleWeeklyRecap(_ summary: WeeklyRecapSummary) async {
        cancelWeeklyRecap()
        var components = DateComponents()
        components.weekday = 1
        components.hour = 10

        let content = UNMutableNotificationContent()
        content.title = "Deine CueFlow-Woche"
        content.body = summary.notificationBody
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: weeklyIdentifier,
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func cancelWeeklyRecap() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [weeklyIdentifier])
    }

    /// Snapshot of what's currently scheduled. Useful for debugging and the
    /// `LanguageLearningApp` startup re-sync.
    func pendingDailyTimeComponents() async -> DateComponents? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard
            let request = requests.first(where: { $0.identifier.hasPrefix(dailyIdentifier) }),
            let trigger = request.trigger as? UNCalendarNotificationTrigger
        else { return nil }
        return trigger.dateComponents
    }

    func refreshLearningReminder(settings: AppSettings, experience: LearningExperience) async {
        guard settings.dailyReminderEnabled else { cancelDailyReminder(); return }
        let language = settings.activeLanguageCode
        let preference = experience.preference(for: language)
        let next = experience.dueEpisode(language: language) ?? EpisodeLibrary.recommendation(language: language,
            purpose: preference.purpose, focusNames: [], completed: experience.completed(in: language))
        let done = experience.runs.contains { $0.language == language && $0.completedAt.map { Calendar.current.isDateInToday($0) } == true }
        await scheduleDailyReminder(hour: settings.dailyReminderHour, minute: settings.dailyReminderMinute,
            episode: next, completedToday: done, weekdays: preference.effectiveStudyWeekdays)
    }
}
