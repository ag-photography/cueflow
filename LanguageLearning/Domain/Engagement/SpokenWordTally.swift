import Foundation

/// Today's "laut gesprochen" counter shared by Sprint, Arcade and Profile.
/// Day-bucketed so it resets at midnight without a cleanup job.
enum SpokenWordTally {
    static let countKey = "spokenWordsCount"
    static let dayKey = "spokenWordsDayIndex"

    static func dayIndex(for date: Date = .now, calendar: Calendar = .current) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSinceReferenceDate / 86_400)
    }

    /// Adds the words in `text` and returns how many were counted.
    @discardableResult
    static func record(_ text: String, defaults: UserDefaults = .standard, now: Date = .now) -> Int {
        let today = dayIndex(for: now)
        if defaults.integer(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: countKey)
        }
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        defaults.set(defaults.integer(forKey: countKey) + words, forKey: countKey)
        return words
    }
}
