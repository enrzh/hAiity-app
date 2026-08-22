import Foundation

struct HabitTimeZoneOption: Identifiable, Equatable, Sendable {
    let identifier: String
    let name: String
    let offset: String

    var id: String { identifier }
}

/// One timezone policy for persistence, date calculations, and the editor.
/// `device` is a real selectable value; nil on a habit means "use the global
/// default", while nil globally means the device timezone.
enum HabitTimeZone {
    static let deviceIdentifier = "device"

    static func sanitizedIdentifier(_ identifier: String?) -> String? {
        guard let value = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if value == deviceIdentifier { return deviceIdentifier }
        return TimeZone(identifier: value) == nil ? nil : value
    }

    static func timeZone(identifier: String?) -> TimeZone {
        guard let identifier = sanitizedIdentifier(identifier),
              identifier != deviceIdentifier,
              let timeZone = TimeZone(identifier: identifier) else {
            return .current
        }
        return timeZone
    }

    static func calendar(identifier: String?, base: Calendar = .current) -> Calendar {
        var calendar = base
        guard let identifier = sanitizedIdentifier(identifier),
              identifier != deviceIdentifier else {
            return calendar
        }
        if let timeZone = TimeZone(identifier: identifier) {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    static func calendar(for habit: Habit,
                         defaultIdentifier: String?,
                         base: Calendar = .current) -> Calendar {
        calendar(identifier: habit.timeZoneIdentifier ?? defaultIdentifier, base: base)
    }

    static func today(for habit: Habit,
                      defaultIdentifier: String?,
                      now: Date = .now,
                      base: Calendar = .current) -> String {
        DayKey.key(for: now,
                   calendar: calendar(for: habit,
                                      defaultIdentifier: defaultIdentifier,
                                      base: base))
    }

    static func displayName(for identifier: String?) -> String {
        guard let identifier = sanitizedIdentifier(identifier),
              identifier != deviceIdentifier,
              let timeZone = TimeZone(identifier: identifier) else {
            return String(localized: "Gerätezeitzone")
        }
        return timeZone.localizedName(for: .generic, locale: .current) ?? identifier
    }

    static func selectionLabel(for identifier: String?, defaultIdentifier: String?) -> String {
        guard let identifier else {
            return String(localized: "Standard")
        }
        if identifier == deviceIdentifier {
            return String(localized: "Gerätezeitzone")
        }
        return displayName(for: identifier)
    }

    static let options: [HabitTimeZoneOption] = {
        let locale = Locale.current
        return TimeZone.knownTimeZoneIdentifiers
            .filter { !$0.hasPrefix("Etc/") }
            .compactMap { identifier in
                guard let timeZone = TimeZone(identifier: identifier) else { return nil }
                let name = timeZone.localizedName(for: .generic, locale: locale) ?? identifier
                let seconds = timeZone.secondsFromGMT()
                let sign = seconds >= 0 ? "+" : "-"
                let absolute = abs(seconds)
                let hours = absolute / 3600
                let minutes = (absolute % 3600) / 60
                return HabitTimeZoneOption(identifier: identifier,
                                           name: name,
                                           offset: String(format: "GMT%@%02d:%02d",
                                                          sign, hours, minutes))
            }
            .sorted {
                if $0.name.localizedStandardCompare($1.name) == .orderedSame {
                    return $0.identifier < $1.identifier
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }()
}
