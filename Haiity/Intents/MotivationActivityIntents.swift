import AppIntents
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

@available(iOS 17.0, *)
struct DismissMotivationActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Ausblenden"
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MotivationActivityControl.endAll()
        return .result()
    }
}

enum MotivationActivityControl {
    static func endAll() async {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            for activity in Activity<MotivationActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
