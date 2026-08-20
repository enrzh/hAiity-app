import XCTest
@testable import Haiity

final class NotificationActionTests: XCTestCase {
    func testNotificationDelegateOnlyPersistsAppOpeningActions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Haiity/Services/NotificationPresenter.swift"))

        XCTAssertTrue(source.contains("NotificationActionRouter.post"))
        XCTAssertFalse(source.contains("NotificationActionRouter.deliverPending()"),
                       "UIKit notification callbacks must never drive SwiftUI presentation")
        XCTAssertFalse(source.contains("MainActor.run"),
                       "notification actions must not enter the main actor during UIKit state restoration")
        XCTAssertTrue(source.contains("return"),
                      "the delegate should return after persisting an app-opening action")
    }

    func testAppOpeningActionIsNotDeliveredSynchronously() {
        let request = NotificationActionRequest(
            action: .edit,
            target: NotificationHabitTarget(
                habitID: UUID(),
                day: "2026-08-20"))
        _ = NotificationActionRouter.takePending()

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: NotificationActionRouter.pendingDidChange,
            object: nil,
            queue: nil) { _ in
                received = true
            }
        defer {
            NotificationCenter.default.removeObserver(observer)
            _ = NotificationActionRouter.takePending()
        }

        NotificationActionRouter.post(request)

        XCTAssertFalse(received,
                       "notification actions must not synchronously interrupt UIKit state restoration")
    }
}
