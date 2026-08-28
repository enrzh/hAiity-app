import XCTest
@testable import Haiity

final class ReminderItemTests: XCTestCase {
    func testPresentationPolicyUsesCompactRowsOnlyForReminders() {
        XCTAssertEqual(ItemPresentation.forItem(Habit(name: "Lesen")), .habitCard)
        XCTAssertEqual(ItemPresentation.forItem(Habit(name: "Tabletten", itemType: .reminder)),
                       .reminderRow)
    }

    func testReminderRowHasNoGraphOrSessionFeatures() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        for forbidden in ["ContributionGrid", "Backfill", "HabitSessionManager", "ShareLink"] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
        XCTAssertTrue(source.contains("reminder-check-"))
    }

    func testReminderUsesFullWidthTappableContextPreview() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains(".contextMenu {"),
                      "the native menu must attach to the row surface")
        XCTAssertTrue(source.contains("Label(String(localized: \"Bearbeiten\")"))
        XCTAssertTrue(source.contains("Button(action: onEdit)"),
                      "editing must remain available from the reminder menu")
        XCTAssertFalse(source.contains("GraphContextMenu("),
                       "a transparent overlay would intercept the checkmark")
    }

    func testReminderContextMenuKeepsTheStableRowSurface() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains("static let rowHeight: CGFloat = 64"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: Self.rowHeight)"))
        XCTAssertTrue(source.contains(".contextMenu {"),
                      "the native preview must be built from the tappable row")
    }

    func testReminderUsesTheCardHeightRevealWithFixedDoneAndRevertActions() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        let source = try source("Haiity/Views/ContentView.swift")
        let reminder = try XCTUnwrap(source.range(of: "case .reminderRow:"))
        let habit = try XCTUnwrap(source.range(of: "case .habitCard:"))
        let branch = source[reminder.lowerBound..<habit.lowerBound]

        XCTAssertTrue(row.contains("SwipeRevealPan(shouldBegin:"),
                      "reminders must receive the card-height swipe through the full-surface bridge")
        XCTAssertTrue(row.contains("leadingSwipe"))
        XCTAssertTrue(row.contains("trailingSwipe"))
        XCTAssertFalse(row.contains(".swipeActions(edge:"),
                       "system row buttons do not cover every nested touch surface")
        XCTAssertTrue(row.contains("lhs.leadingSwipe == rhs.leadingSwipe"),
                      "changing saved reveal actions must update an equatable row")
        XCTAssertTrue(branch.contains("let reveal = revealActions(for: habit)"))
        XCTAssertTrue(branch.contains("leadingSwipe: reveal.leading"))
        XCTAssertTrue(branch.contains("trailingSwipe: reveal.trailing"))
    }

    func testReminderPreviewAndRevealShareTheStableRowHeight() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains("static let rowHeight: CGFloat = 64"))
        XCTAssertTrue(row.contains(".frame(maxWidth: .infinity, minHeight: Self.rowHeight)"))
        XCTAssertTrue(row.contains(".contextMenu {"),
                      "the long-press menu must share the tappable row")
    }

    func testReminderUsesItsOwnRevealAndContextMenuHost() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(row.contains("SwipeRevealPan(shouldBegin:"),
                      "reminders need the same full-surface bridge as habits")
        XCTAssertTrue(row.contains("revealOffset"),
                      "reminders must render their own offset reveal surface")
        XCTAssertTrue(row.contains(".contextMenu {"),
                      "the row keeps its non-intercepting long-press menu")
        XCTAssertFalse(row.contains("GraphContextMenu("),
                       "the transparent graph host must not intercept row controls")
    }

    func testReminderUsesTheSharedRevealBridgeForEveryTouchSurface() throws {
        let row = try source("Haiity/Views/ReminderRow.swift")

        XCTAssertTrue(row.contains("SwipeRevealPan(shouldBegin:"),
                      "reminders must use the same reliable full-surface bridge as habits")
        XCTAssertFalse(row.contains(".swipeActions(edge:"),
                       "native row actions lose swipe gestures over tappable controls")
        XCTAssertTrue(row.contains("revealOffset"),
                      "the reminder row must render the card-height reveal surface")
    }

    func testRevealGestureIsOwnedByEachSwiftUISurface() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(reminder.contains("SwipeRevealPan(shouldBegin:"),
                      "the reminder row needs one full-surface UIKit pan host")
        XCTAssertTrue(habit.contains("SwipeRevealPan(shouldBegin:"),
                      "the habit card needs one full-surface UIKit pan host")
        XCTAssertFalse(reminder.contains("DragGesture(minimumDistance:"),
                       "a local SwiftUI drag loses the race to List and nested controls")
        XCTAssertFalse(habit.contains("DragGesture(minimumDistance:"),
                       "a local SwiftUI drag loses the race to List and the graph scroll")
    }

    func testSwipeBridgePreservesNestedControlTapsAndWaitsForTheListScroll() throws {
        let bridge = try source("Haiity/Views/SwipeRevealPan.swift")

        XCTAssertTrue(bridge.contains("pan.cancelsTouchesInView = false"),
                      "the pan must not swallow a nested checkmark tap")
        XCTAssertTrue(bridge.contains("scroll.panGestureRecognizer.require(toFail: pan)"),
                      "the row pan must decide horizontal intent before List scrolls")
        XCTAssertTrue(bridge.contains("activeFrame.contains(location)"),
                      "the pan must validate touches inside this row when the host is shared")
        XCTAssertTrue(bridge.contains("container.hitTest(location, with: nil)"),
                      "the bridge must inspect the actual nested touch surface")
        XCTAssertTrue(bridge.contains("shouldRecognizeSimultaneouslyWith"),
                      "nested controls must not block a horizontal row swipe")
    }

    func testSwipeBridgeDoesNotExcludeGesturesOnTheRowHost() throws {
        let bridge = try source("Haiity/Views/SwipeRevealPan.swift")

        XCTAssertTrue(bridge.contains("otherView is UIScrollView"),
                      "only the enclosing scroll gesture should stay exclusive")
        XCTAssertFalse(bridge.contains("otherView !== container"),
                       "control gestures on the row host must be allowed to coexist")
    }

    func testCustomRevealButtonsExposeStableUIIdentifiers() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")
        let identifier = #".accessibilityIdentifier("reveal-action-\(action.operation.rawValue)")"#

        XCTAssertTrue(reminder.contains(identifier),
                      "reminder reveal actions must remain addressable after a swipe")
        XCTAssertTrue(habit.contains(identifier),
                      "habit reveal actions must remain addressable after a swipe")
    }

    func testRevealActionsAreExposedByCardMotionInsteadOfFadingOrScaling() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")

        for source in [reminder, habit] {
            XCTAssertTrue(source.contains(".transition(.identity)"),
                          "the action underlay must not use SwiftUI's default fade transition")
            XCTAssertFalse(source.contains(".opacity(min(1, exposed /"),
                           "the card motion should reveal actions instead of fading them in")
            XCTAssertFalse(source.contains(".scaleEffect(min(1, 0.9 +"),
                           "the action underlay must keep a stable size while the card moves")
        }
    }

    func testRevealUnderlaysStayMountedBeforeTheFirstDrag() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")

        for source in [reminder, habit] {
            XCTAssertTrue(source.contains(
                "revealButtons(actions: leadingSwipe, alignment: .leading,"
            ))
            XCTAssertTrue(source.contains(
                "revealButtons(actions: trailingSwipe, alignment: .trailing,"
            ))
            XCTAssertTrue(source.contains("exposedWidth:"),
                          "the permanently mounted action layer must be clipped to the exposed strip")
            XCTAssertTrue(source.contains(".allowsHitTesting(revealOffset > 0)"))
            XCTAssertTrue(source.contains(".allowsHitTesting(revealOffset < 0)"))
            XCTAssertFalse(source.contains("if revealOffset != 0 {\n                revealButtons"),
                           "the action layer must not be inserted after the gesture starts")
        }
    }

    func testRevealUnderlaysClipToTheExposedPartOfTranslucentCards() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")

        for source in [reminder, habit] {
            let reveal = try revealRenderer(from: source)

            XCTAssertFalse(reveal.contains(".mask"),
                           "a full-width mask can leave a second translucent layout surface on iOS 27")
            XCTAssertTrue(reveal.contains(
                ".frame(width: exposedWidth, alignment: alignment)"
            ), "the action layer must be sized to the exact card displacement")
            XCTAssertTrue(reveal.contains(".clipped()"),
                          "the exposed action strip must not draw outside its width")
        }
    }

    func testRevealBridgeKeepsTheExistingDecisionAndVelocityRules() throws {
        let reminder = try source("Haiity/Views/ReminderRow.swift")
        let habit = try source("Haiity/Views/HabitCard.swift")

        for source in [reminder, habit] {
            XCTAssertTrue(source.contains("revealShouldBegin"),
                          "the bridge must keep the shared direction rules")
            XCTAssertTrue(source.contains("SwipeReveal.offset"),
                          "the bridge must use the shared rubber-band offset")
            XCTAssertTrue(source.contains("SwipeReveal.resting"),
                          "the bridge must preserve the existing velocity projection")
        }

        let bridge = try source("Haiity/Views/SwipeRevealPan.swift")
        XCTAssertTrue(bridge.contains("pan.velocity(in: container)"),
                      "the UIKit pan must forward velocity to the existing resting rules")
    }

    func testCombinedListBranchesByItemTypeAfterApplyingTheSharedFilter() throws {
        let source = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(source.contains("ItemPresentation.forItem(habit)"))
        XCTAssertTrue(source.contains("ReminderRow("))
        XCTAssertTrue(source.contains("let active = listFilteredHabits"))
    }

    func testEditorOffersAndPersistsItemType() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("@State private var itemType: HabitItemType = .reminder"))
        XCTAssertTrue(source.contains("selection: $itemType"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.habit)"))
        XCTAssertTrue(source.contains(".tag(HabitItemType.reminder)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"item-type-picker\")"))
        XCTAssertTrue(source.contains("itemType = habit.itemType"))
        XCTAssertTrue(source.contains("habit.itemType = itemType"))
    }

    func testEditorOffersAndPersistsCalendarOptOut() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("Toggle(isOn: calendarSyncBinding)"),
                      "the calendar switch must use the entitlement-aware binding")
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"habit-calendar-toggle\")"))
        XCTAssertTrue(source.contains("calendarSyncEnabled = habit.calendarSyncEnabled"))
        XCTAssertTrue(source.contains("habit.calendarSyncEnabled = unlocked && calendarSyncEnabled"),
                      "saving must not restore calendar sync after Pro expiry")
    }

    func testReminderOccurrenceControlsArePresentAndRecurrenceCopyIsRemoved() throws {
        let editor = try editorSource()
        let row = try source("Haiity/Views/ReminderRow.swift")
        let content = try source("Haiity/Views/ContentView.swift")

        XCTAssertTrue(editor.contains("repeats-while-incomplete-toggle"))
        XCTAssertTrue(editor.contains("repeatsWhileIncomplete = habit.repeatsWhileIncomplete"))
        XCTAssertTrue(editor.contains(
            "habit.repeatsWhileIncomplete = itemType == .reminder ? repeatsWhileIncomplete : true"
        ))
        XCTAssertTrue(content.contains("reminder-early-completion-confirm"))
        XCTAssertFalse(row.contains("RecurrenceText.summary"))
        XCTAssertTrue(editor.contains("itemType == .reminder && draft.frequency != .once"))
    }

    func testReminderLongPressMenuIncludesRevert() throws {
        let source = try source("Haiity/Views/ReminderRow.swift")
        XCTAssertTrue(source.contains("Rückgängig"))
        XCTAssertTrue(source.contains("onRevert"))
        XCTAssertTrue(source.contains("Löschen"))
        XCTAssertTrue(source.contains("onDelete"))
    }

    func testHabitEditorOffersDeleteForExistingItems() throws {
        let editor = try editorSource()
        let card = try source("Haiity/Views/HabitCard.swift")

        XCTAssertTrue(editor.contains("delete-habit"))
        XCTAssertTrue(editor.contains("store.remove(habit.id)"))
        XCTAssertTrue(card.contains("handler: onDelete"))
    }

    func testEditorKeepsTheSharedHabitSettings() throws {
        let source = try editorSource()

        for section in ["recurrenceSection", "durationSection", "kindSection", "colorSection"] {
            XCTAssertTrue(source.contains(section), "missing shared editor section: \(section)")
        }
    }

    func testHabitAndReminderEditorOfferConfirmedDelete() throws {
        let source = try editorSource()
        XCTAssertTrue(source.contains("showingDeleteConfirmation"))
        XCTAssertTrue(source.contains("delete-habit"))
        XCTAssertTrue(source.contains("store.remove(habit.id)"))
        XCTAssertTrue(source.contains("role: .destructive"))
    }

    func testReminderModeHidesHabitKindControls() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("if itemType == .habit { kindSection.settingsListRow() }"),
                      "the habit-only kind controls must be conditionally mounted")
        XCTAssertTrue(source.contains("itemType == .habit ? Habit.resolvedKind"),
                      "saving a reminder must not persist a habit kind")
        XCTAssertTrue(source.contains(": .checkbox"),
                      "reminders must use the internal checkbox representation")
    }

    func testOnlyNewTrackedHabitsUseTheFreeLimit() throws {
        let source = try editorSource()

        XCTAssertTrue(source.contains("ProGate.maySaveTrackedHabit"))
        XCTAssertTrue(source.contains("existingIsTracked: existing?.isTrackedHabit == true"))
        XCTAssertTrue(source.contains("targetIsTracked: itemType == .habit"))
        XCTAssertTrue(source.contains("store.activeTrackedHabits.count"))
        XCTAssertTrue(source.contains("paywall = .habits"))
    }

    private func editorSource() throws -> String {
        try source("Haiity/Views/EditHabitSheet.swift")
    }

    private func revealRenderer(from source: String) throws -> String {
        guard let declaration = source.range(of: "private func revealButtons") else {
            throw XCTSkip("Reveal renderer unavailable in source contract")
        }
        guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
            XCTFail("Reveal renderer has no opening brace")
            return ""
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[declaration.lowerBound...index])
                }
            default: break
            }
            index = source.index(after: index)
        }

        XCTFail("Reveal renderer has unbalanced braces")
        return ""
    }

    private func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url)
        }
        let resource = url.deletingPathExtension().lastPathComponent
        let bundle = Bundle(for: ReminderItemTests.self)
        guard let bundledURL = bundle.url(forResource: resource, withExtension: "txt") else {
            throw XCTSkip("Source contract unavailable in checkout and test bundle")
        }
        return try String(contentsOf: bundledURL)
    }
}
