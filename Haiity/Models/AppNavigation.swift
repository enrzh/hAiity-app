import Foundation

enum AppTab: Hashable {
    case stats
    case habits
    case more
    case create
    case search
}

struct AppTabLayerState: Equatable {
    let opacity: Double
    let allowsHitTesting: Bool
    let accessibilityHidden: Bool
    let zIndex: Double
}

extension AppTabLayerState {
    init(tab: AppTab, selectedTab: AppTab) {
        let selected = tab == selectedTab
        self.init(opacity: selected ? 1 : 0,
                  allowsHitTesting: selected,
                  accessibilityHidden: !selected,
                  zIndex: selected ? 1 : 0)
    }
}

enum AppMoreDestination: Equatable {
    case archive, about, developer, appearance, habitBehavior, github
}

struct AppRouteEffect: Equatable {
    let tab: AppTab
    let morePage: AppMoreDestination?
    let opensSearch: Bool
    let opensCreate: Bool
    let habitID: UUID?
    let runsNativeSyncCleanup: Bool

    init(tab: AppTab,
         morePage: AppMoreDestination?,
         opensSearch: Bool,
         opensCreate: Bool,
         habitID: UUID? = nil,
         runsNativeSyncCleanup: Bool = false) {
        self.tab = tab
        self.morePage = morePage
        self.opensSearch = opensSearch
        self.opensCreate = opensCreate
        self.habitID = habitID
        self.runsNativeSyncCleanup = runsNativeSyncCleanup
    }
}

enum RoutePresentationPhase: Equatable {
    case absent
    case requested
    case presented
    case dismissing
}

struct RoutePresentation: Equatable {
    var create: RoutePresentationPhase = .absent
    var editor: RoutePresentationPhase = .absent
    var sentenceCreation: RoutePresentationPhase = .absent
    /// Das Kaufblatt. KEINE Route öffnet es — es ist immer nur im Weg, und
    /// zwar als oberste Präsentation: ein Deep-Link, der es stehen lässt,
    /// schaltet den Bereich darunter um und sperrt den Nutzer auf einer
    /// Kaufseite ein, die zu seinem Tipp gar nicht mehr gehört.
    var paywall: RoutePresentationPhase = .absent
    var more: RoutePresentationPhase = .absent
    var morePage: AppMoreDestination? = nil
}

struct CreateCoverPresentation: Equatable {
    private(set) var dismissalIsOwed = false

    func phase(requested: Bool) -> RoutePresentationPhase {
        if requested { return dismissalIsOwed ? .presented : .requested }
        return dismissalIsOwed ? .dismissing : .absent
    }

    mutating func didPresent() {
        dismissalIsOwed = true
    }

    mutating func didDismiss() {
        dismissalIsOwed = false
    }
}

/// Identifies the latest accepted route. Delayed UI work keeps the token it
/// was created with and must not apply after a newer route supersedes it.
struct RouteWork {
    struct Item: Equatable {
        let generation: Int
        let effect: AppRouteEffect
    }

    enum Step: Equatable {
        case dismissPaywall
        case waitForPaywallDismissal
        case dismissEditor
        case waitForEditorDismissal
        case dismissSentenceCreation
        case waitForSentenceCreationDismissal
        case dismissCreate
        case waitForCreateDismissal
        case dismissMore
        case waitForMoreDismissal
        case keepCurrentMorePage
        case apply
    }

    private var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    mutating func begin(_ effect: AppRouteEffect) -> Item {
        let generation = begin()
        return Item(generation: generation, effect: effect)
    }

    func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    func isCurrent(_ item: Item) -> Bool {
        isCurrent(item.generation)
    }

    func nextStep(for item: Item, presentation: RoutePresentation) -> Step? {
        guard isCurrent(item) else { return nil }

        // Zuerst das Kaufblatt: es liegt über allem, und keine Route will es.
        switch presentation.paywall {
        case .requested, .presented: return .dismissPaywall
        case .dismissing: return .waitForPaywallDismissal
        case .absent: break
        }

        switch presentation.sentenceCreation {
        case .requested, .presented: return .dismissSentenceCreation
        case .dismissing: return .waitForSentenceCreationDismissal
        case .absent: break
        }

        switch presentation.editor {
        case .requested, .presented: return .dismissEditor
        case .dismissing: return .waitForEditorDismissal
        case .absent: break
        }

        if !item.effect.opensCreate {
            switch presentation.create {
            case .requested: return .dismissCreate
            case .presented: return .dismissCreate
            case .dismissing: return .waitForCreateDismissal
            case .absent: break
            }
        }

        switch presentation.more {
        case .requested:
            return .dismissMore
        case .presented:
            if item.effect.morePage == presentation.morePage,
               item.effect.morePage != nil {
                return .keepCurrentMorePage
            }
            return .dismissMore
        case .dismissing:
            return .waitForMoreDismissal
        case .absent:
            return .apply
        }
    }
}

enum AppDestination: Equatable {
    case habits
    case habit(UUID)
    case more
    case stats
    case archive
    case search
    case create
    case cleanup

    static func resolve(url: URL) -> AppDestination? {
        guard url.scheme?.lowercased() == "haiity" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let habitID = components?.queryItems?
            .first(where: { $0.name == "habit" })?
            .value
            .flatMap(UUID.init(uuidString:))

        switch url.host?.lowercased() {
        case "habits": return habitID.map(AppDestination.habit) ?? .habits
        case "more", "sync": return .more
        case "stats": return .stats
        case "archive": return .archive
        case "search": return .search
        case "new": return .create
        case "cleanup": return .cleanup
        default: return nil
        }
    }

    /// Die Tür, durch die dieses Ziel erreicht wird — dieselben Links, die
    /// auch von außen ankommen (`onOpenURL`). Schnellaktionen des
    /// Homescreens parken genau diese URL.
    var url: URL {
        let host: String
        switch self {
        case .habits: host = "habits"
        case .habit(let id):
            var components = URLComponents()
            components.scheme = "haiity"
            components.host = "habits"
            components.queryItems = [URLQueryItem(name: "habit", value: id.uuidString)]
            return components.url!
        case .more: host = "more"
        case .stats: host = "stats"
        case .archive: host = "archive"
        case .search: host = "search"
        case .create: host = "new"
        case .cleanup: host = "cleanup"
        }
        return URL(string: "haiity://\(host)")!
    }

    var selectedTab: AppTab {
        switch self {
        case .habits, .habit:
            return .habits
        case .search:
            return .search
        case .stats:
            return .stats
        case .more, .archive, .cleanup:
            return .more
        case .create:
            return .create
        }
    }

    var effect: AppRouteEffect {
        switch self {
        case .habits:
            .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: false)
        case .habit(let id):
            .init(tab: .habits, morePage: nil, opensSearch: false,
                  opensCreate: false, habitID: id)
        case .more:
            .init(tab: .more, morePage: nil, opensSearch: false, opensCreate: false)
        case .stats:
            .init(tab: .stats, morePage: nil, opensSearch: false, opensCreate: false)
        case .archive:
            .init(tab: .more, morePage: .archive, opensSearch: false, opensCreate: false)
        case .search:
            .init(tab: .search, morePage: nil, opensSearch: true, opensCreate: false)
        case .create:
            .init(tab: .habits, morePage: nil, opensSearch: false, opensCreate: true)
        case .cleanup:
            .init(tab: .more, morePage: nil, opensSearch: false, opensCreate: false,
                  runsNativeSyncCleanup: true)
        }
    }
}
