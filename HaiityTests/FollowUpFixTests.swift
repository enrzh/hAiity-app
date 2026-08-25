import XCTest

final class FollowUpFixTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative))
    }

    func testContextMenuOwnsAnIndependentCardHost() throws {
        let source = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(source.contains("GraphContextMenuHub"),
                      "a UIKit host may have only one context interaction")
        XCTAssertTrue(source.contains("register(self)"),
                      "each card must register its own frame and actions")
        XCTAssertTrue(source.contains("activeMenu"),
                      "the hub must resolve the held card before building a preview")
        XCTAssertTrue(source.contains("UITargetedPreview(view: host"),
                      "the transition must target the lifted card, not its list-cell siblings")
        XCTAssertTrue(source.contains("roundedRect: host.bounds"),
                      "the lifted card must retain its own rounded bounds")
        XCTAssertTrue(source.contains("isHidden = false"),
                      "the card host must remain in the overlay layout")
    }

    func testGraphPreviewsFitWithoutAHorizontalScrollGesture() throws {
        let habit = try source("Haiity/Views/HabitCard.swift")
        let github = try source("Haiity/Views/GitHubContributionCard.swift")
        let grid = try source("Haiity/Views/ContributionGrid.swift")

        XCTAssertTrue(habit.contains("weeks: previewWeeks"),
                      "habit previews need a fitted, explicit graph window")
        XCTAssertTrue(habit.contains("showsMonthLabels: false"),
                      "the enlarged graph should spend its height on tiles")
        XCTAssertTrue(github.contains("showsMonthLabels: false"),
                      "GitHub previews should use the same tile-only treatment")
        XCTAssertTrue(grid.contains(".scrollDisabled(!interactive"),
                      "preview grids must not expose a nested scroll view")
    }

    func testHabitToolbarStartsFilterDirectlyAndShowsResetToast() throws {
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(content.contains("ToolbarItem(placement: .topBarLeading) {\n                        habitFilterMenu"),
                      "the leading toolbar item should be the filter menu itself")
        XCTAssertFalse(content.contains("accessibilityIdentifier(\"habit-management\")"),
                       "the old ellipsis management button must be gone")
        XCTAssertTrue(content.contains("filter-toast"),
                      "active filters need a visible toast hint")
        XCTAssertTrue(content.contains("clear-filters"),
                      "the filter toast needs a direct reset action")
    }

    func testSetupExposesNativeCalendarAndReminderPermissionActions() throws {
        let setup = try source("Haiity/Views/ReminderSetupView.swift")

        XCTAssertTrue(setup.contains("setup-calendar-permission"))
        XCTAssertTrue(setup.contains("setup-reminders-permission"))
        XCTAssertTrue(setup.contains("requestCalendarPermission"))
        XCTAssertTrue(setup.contains("requestRemindersPermission"))
        XCTAssertTrue(setup.contains("calendarPermissionCard"))
    }

    func testMultipleDatePickerUsesAHalfHeightSheet() throws {
        let editor = try source("Haiity/Views/EditHabitSheet.swift")

        XCTAssertTrue(editor.contains(".presentationDetents([.medium])"),
                      "additional recurrence dates should use a half-height sheet")
        XCTAssertTrue(editor.contains(".presentationDragIndicator(.visible)"),
                      "the reduced sheet needs an obvious grab affordance")
    }
}
