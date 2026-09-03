import Foundation

enum GitHubPreferences {
    static let showsUsernameKey = "github.showsUsername"
    static let showsMonthLabelsKey = "github.showsMonthLabels"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    static var showsUsername: Bool {
        showsUsername(in: defaults)
    }

    static func showsUsername(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showsUsernameKey) as? Bool ?? true
    }

    static func setShowsUsername(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: showsUsernameKey)
    }

    static var showsMonthLabels: Bool {
        showsMonthLabels(in: defaults)
    }

    static func showsMonthLabels(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: showsMonthLabelsKey) as? Bool ?? true
    }

    static func setShowsMonthLabels(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: showsMonthLabelsKey)
    }
}
