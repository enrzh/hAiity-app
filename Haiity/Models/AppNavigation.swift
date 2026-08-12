import Foundation

enum AppTab: Hashable {
    case habits
    case more
    case create
}

enum AppMoreDestination: Equatable {
    case stats
    case archive
}

enum AppDestination: Equatable {
    case habits
    case more
    case stats
    case archive
    case search
    case create

    static func resolve(url: URL) -> AppDestination? {
        guard url.scheme?.lowercased() == "haiity" else { return nil }

        switch url.host?.lowercased() {
        case "habits": return .habits
        case "more": return .more
        case "stats": return .stats
        case "archive": return .archive
        case "search": return .search
        case "new": return .create
        default: return nil
        }
    }

    var selectedTab: AppTab {
        switch self {
        case .habits, .search:
            return .habits
        case .more, .stats, .archive:
            return .more
        case .create:
            return .create
        }
    }
}
