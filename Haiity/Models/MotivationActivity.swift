import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Fixed content for one day's motivational Live Activity. The message is
/// captured at start so changing the user's name later does not rewrite it.
struct MotivationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let displayedAt: Date
    }

    let dayKey: String
    let title: String
    let body: String
}
#endif

struct MotivationActivityRequest: Equatable, Sendable {
    let dayKey: String
    let title: String
    let body: String
    let staleDate: Date
}

enum MotivationActivityDecision: Equatable {
    case disabled
    case waiting
    case alreadyShown
    case start(dayKey: String, staleDate: Date)
}

enum MotivationActivityPolicy {
    static func decision(minutes: Int?, now: Date, shownDay: String?,
                         calendar: Calendar) -> MotivationActivityDecision {
        guard let minutes, (0..<24 * 60).contains(minutes) else { return .disabled }

        let dayKey = DayKey.key(for: now, calendar: calendar)
        guard shownDay != dayKey else { return .alreadyShown }
        guard let scheduled = scheduledDate(minutes: minutes,
                                             dayKey: dayKey,
                                             calendar: calendar) else {
            return .disabled
        }
        guard scheduled <= now else { return .waiting }

        return .start(dayKey: dayKey,
                      staleDate: nextMidnight(after: now, calendar: calendar))
    }

    static func scheduledDate(minutes: Int?, dayKey: String,
                              calendar: Calendar) -> Date? {
        guard let minutes, (0..<24 * 60).contains(minutes),
              let date = DayKey.date(from: dayKey, calendar: calendar) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = minutes / 60
        components.minute = minutes % 60
        return calendar.date(from: components)
    }

    static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }
}

enum MotivationActivityStorage {
    static let shownDayKey = "motivationActivityShownDay"

    static func shownDay(in defaults: UserDefaults) -> String? {
        defaults.string(forKey: shownDayKey)
    }

    static func markShown(_ day: String, in defaults: UserDefaults) {
        defaults.set(day, forKey: shownDayKey)
    }

    static func clearShown(in defaults: UserDefaults) {
        defaults.removeObject(forKey: shownDayKey)
    }

    static func productionDefaults() -> UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }
}
