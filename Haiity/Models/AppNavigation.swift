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

struct AppRouteEffect: Equatable {
    let tab: AppTab
    let morePage: AppMoreDestination?
    let opensSearch: Bool
    let opensCreate: Bool
}

/// Identifies the latest accepted route. Delayed UI work keeps the token it
/// was created with and must not apply after a newer route supersedes it.
struct RouteWork {
    struct Item: Equatable {
        let generation: Int
        let effect: AppRouteEffect
        let requiresCreateDismissal: Bool
    }

    private var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    mutating func begin(_ effect: AppRouteEffect, createIsPresented: Bool) -> Item {
        let generation = begin()
        return Item(generation: generation,
                    effect: effect,
                    requiresCreateDismissal: createIsPresented && !effect.opensCreate)
    }

    func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    func isCurrent(_ item: Item) -> Bool {
        isCurrent(item.generation)
    }

    func canDeliverAfterCreateDismissal(_ item: Item) -> Bool {
        item.requiresCreateDismissal && isCurrent(item)
    }
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
        case "more", "sync": return .more
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

    var effect: AppRouteEffect {
        switch self {
        case .habits:
            .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: false)
        case .more:
            .init(tab: .more, morePage: nil, opensSearch: false, opensCreate: false)
        case .stats:
            .init(tab: .more, morePage: .stats, opensSearch: false, opensCreate: false)
        case .archive:
            .init(tab: .more, morePage: .archive, opensSearch: false, opensCreate: false)
        case .search:
            .init(tab: .habits, morePage: nil, opensSearch: true, opensCreate: false)
        case .create:
            .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: true)
        }
    }
}
