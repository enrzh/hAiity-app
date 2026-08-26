import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

protocol MotivationActivityClient: Sendable {
    func activeDayKeys() async -> Set<String>
    func start(_ request: MotivationActivityRequest) async throws
    func end(dayKey: String?) async
}

enum MotivationActivityClientError: Error {
    case activitiesDisabled
}

actor MotivationActivityManager {
    static let shared = MotivationActivityManager(
        client: ActivityKitMotivationActivityClient(),
        defaults: MotivationActivityStorage.productionDefaults())

    private let client: MotivationActivityClient
    private let defaults: UserDefaults
    private var startingDayKeys = Set<String>()

    init(client: MotivationActivityClient, defaults: UserDefaults) {
        self.client = client
        self.defaults = defaults
    }

    func reconcile(motivationMinutes: Int?, name: String?,
                   delivery: MotivationDelivery = .liveActivity,
                   now: Date = .now,
                   calendar: Calendar = .current) async {
        let today = DayKey.key(for: now, calendar: calendar)
        let activeDays = await client.activeDayKeys()

        for day in activeDays where day != today {
            await client.end(dayKey: day)
        }

        guard delivery == .liveActivity else {
            await client.end(dayKey: nil)
            MotivationActivityStorage.clearShown(in: defaults)
            return
        }

        let decision = MotivationActivityPolicy.decision(
            minutes: motivationMinutes,
            now: now,
            shownDay: MotivationActivityStorage.shownDay(in: defaults),
            calendar: calendar)

        switch decision {
        case .disabled:
            await client.end(dayKey: nil)
            MotivationActivityStorage.clearShown(in: defaults)

        case .waiting, .alreadyShown:
            if activeDays.contains(today) {
                MotivationActivityStorage.markShown(today, in: defaults)
            }

        case let .start(dayKey, staleDate):
            guard !activeDays.contains(dayKey) else {
                MotivationActivityStorage.markShown(dayKey, in: defaults)
                return
            }
            // Actor isolation does not prevent re-entry while the ActivityKit
            // request is suspended. Reserve the day before awaiting so two
            // foreground callbacks cannot create duplicate activities.
            guard startingDayKeys.insert(dayKey).inserted else { return }

            let message = Motivation.message(name: name, today: dayKey)
            let request = MotivationActivityRequest(dayKey: dayKey,
                                                     title: message.title,
                                                     body: message.body,
                                                     staleDate: staleDate)
            do {
                try await client.start(request)
                MotivationActivityStorage.markShown(dayKey, in: defaults)
            } catch {
                NSLog("MotivationActivity: start failed: %@", String(describing: error))
                await MainActor.run {
                    NotificationDeliveryIssueCenter.note(.reminderScheduleFailed)
                }
            }
            startingDayKeys.remove(dayKey)
        }
    }
}

struct ActivityKitMotivationActivityClient: MotivationActivityClient {
    func activeDayKeys() async -> Set<String> {
        #if canImport(ActivityKit)
        return Set(Activity<MotivationActivityAttributes>.activities.map {
            $0.attributes.dayKey
        })
        #else
        return []
        #endif
    }

    func start(_ request: MotivationActivityRequest) async throws {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw MotivationActivityClientError.activitiesDisabled
        }
        let attributes = MotivationActivityAttributes(dayKey: request.dayKey,
                                                       title: request.title,
                                                       body: request.body)
        let content = ActivityContent(
            state: MotivationActivityAttributes.ContentState(displayedAt: .now),
            staleDate: request.staleDate)
        // This remains the serverless ActivityKit path. A terminated app cannot start a Live Activity
        // from a local notification when `pushType` stays nil, so the notification fallback remains the serverless behavior
        // until an explicit backend is approved.
        _ = try Activity.request(attributes: attributes,
                                 content: content,
                                 pushType: nil)
        #endif
    }

    func end(dayKey: String?) async {
        #if canImport(ActivityKit)
        for activity in Activity<MotivationActivityAttributes>.activities {
            guard dayKey == nil || activity.attributes.dayKey == dayKey else { continue }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
