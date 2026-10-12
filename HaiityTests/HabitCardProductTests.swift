import SwiftUI
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class HabitCardProductTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_GB")
        return value
    }

    private let today = "2026-10-07"

    private func habit(kind: HabitKind = .checkbox) -> Habit {
        var value = Habit(name: "Read", recurrence: Recurrence(target: kind == .quantity ? 3 : nil),
                          kind: kind)
        value.createdAt = "2026-05-01"
        value.log["2026-10-05"] = 1
        value.log["2026-10-06"] = 1
        return value
    }

    private func card(_ habit: Habit, collapsed: Bool = false,
                      onDetails: (() -> Void)? = nil) -> HabitCard {
        HabitCard(habit: habit, collapsed: collapsed, showsMonthLabels: false,
                  onToggleDay: { _ in }, onBackfill: {}, onIncrement: {}, onClear: {},
                  onMarkDone: {}, onEdit: {}, onArchive: {}, calendar: calendar,
                  now: DayKey.date(from: today, calendar: calendar)!, onDetails: onDetails)
    }

    private func reminderRow(_ habit: Habit, now: Date) -> ReminderRow {
        ReminderRow(habit: habit, onToggle: {}, onEdit: {}, onArchive: {}, onRevert: {},
                    now: now, calendar: calendar)
    }

    private func compactRow(_ habit: Habit) -> SearchResultRow {
        SearchResultRow(habit: habit, onEdit: {},
                        now: DayKey.date(from: today, calendar: calendar)!, calendar: calendar)
    }

    private func snapshot(_ habit: Habit, width: CGFloat = 300) -> GridCalendar.Snapshot {
        GridCalendar.snapshot(habit: habit, weeks: ContributionChart.bandMetrics(width: width).weeks,
                              today: today, calendar: calendar)
    }

    func testDisplayableStaleSnapshotChecksOffImmediatelyWithoutRebuildingHistory() {
        let previous = habit()
        let cached = snapshot(previous)
        var current = previous
        current.log[today] = 1
        let beforeKey = GridCalendar.HabitSnapshotKey(habit: previous, weeks: cached.weeks,
                                                     today: today, calendar: calendar)
        let request = GridCalendar.HabitSnapshotKey(habit: current, weeks: cached.weeks,
                                                    today: today, calendar: calendar)
        XCTAssertTrue(beforeKey.canDisplaySnapshot(for: request))
        XCTAssertNotEqual(beforeKey, request)
        let calculations = GridCalendar.computeCount
        let displayed = HabitCard.currentDaySnapshot(cached, previous: previous,
                                                     habit: current, calendar: calendar)
        XCTAssertEqual(GridCalendar.computeCount, calculations)
        XCTAssertEqual(displayed.filledCount, cached.filledCount + 1)
        XCTAssertEqual(displayed.levels.last?[3], 2, "Wednesday follows two completed days")
        assertOnlyTodayChanged(cached, displayed)
        XCTAssertEqual(previous.log[today], nil)
        XCTAssertEqual(current.log[today], 1)
        XCTAssertEqual(HabitCard.currentDaySnapshot(cached, previous: previous,
                                                   habit: current, calendar: calendar), displayed,
                       "Rendering repeatedly must not accumulate a second completion")
    }

    func testUndoCorrectsAStaleCompletedSnapshotImmediately() {
        var previous = habit()
        previous.log[today] = 1
        let cached = snapshot(previous)
        var current = previous
        current.log[today] = nil
        let displayed = HabitCard.currentDaySnapshot(cached, previous: previous,
                                                     habit: current, calendar: calendar)
        XCTAssertEqual(displayed.levels.last?[3], 0)
        XCTAssertEqual(displayed.filledCount, cached.filledCount - 1)
        assertOnlyTodayChanged(cached, displayed)
    }

    func testQuantityPartialCompletionAndUndoKeepActualIntensity() {
        var previous = habit(kind: .quantity)
        previous.log[today] = 1
        let cached = snapshot(previous)
        for (value, intensity, extraCompleted) in [(2, 2, 0), (3, 4, 1), (0, 0, 0)] {
            var current = previous
            current.log[today] = value == 0 ? nil : value
            let displayed = HabitCard.currentDaySnapshot(cached, previous: previous,
                                                         habit: current, calendar: calendar)
            XCTAssertEqual(displayed.levels.last?[3], intensity)
            XCTAssertEqual(displayed.filledCount, cached.filledCount + extraCompleted)
            assertOnlyTodayChanged(cached, displayed)
        }
    }

    func testYesNoDeclineAndUndoNeverBecomeAnEmptyOrCompletedDay() {
        var previous = habit(kind: .yesNo)
        previous.log[today] = Habit.Answer.yes
        let cached = snapshot(previous)
        var declined = previous
        declined.log[today] = Habit.Answer.no
        let displayed = HabitCard.currentDaySnapshot(cached, previous: previous,
                                                     habit: declined, calendar: calendar)
        XCTAssertEqual(displayed.levels.last?[3], Habit.Answer.declinedLevel)
        XCTAssertEqual(displayed.filledCount, cached.filledCount - 1)
        assertOnlyTodayChanged(cached, displayed)
        let restored = HabitCard.currentDaySnapshot(displayed, previous: declined,
                                                    habit: previous, calendar: calendar)
        XCTAssertEqual(restored.levels, cached.levels)
        XCTAssertEqual(restored.filledCount, cached.filledCount)
    }

    func testRecentDisplayDoesNotDiscardOlderHistoryOrChangeReminderPresentation() {
        var current = habit()
        current.log["2026-05-01"] = 1
        let displayed = snapshot(current)
        XCTAssertEqual(displayed.weeks, 20)
        XCTAssertTrue(displayed.keys.last!.contains(today))
        XCTAssertFalse(displayed.keys.flatMap { $0 }.contains("2026-05-01"))
        XCTAssertEqual(current.log["2026-05-01"], 1)
        XCTAssertEqual(GridCalendar.snapshot(habit: current, today: today, calendar: calendar).weeks, 53)
        XCTAssertEqual(ItemPresentation.forItem(current), .habitCard)
        current.itemType = .reminder
        XCTAssertEqual(ItemPresentation.forItem(current), .reminderRow)
    }

    func testRenderedFeedbackChangesOnlyTheActualTodaySquareAndUndoRestoresIt() throws {
        let previous = habit()
        let cached = snapshot(previous)
        var current = previous
        current.log[today] = 1
        let displayed = HabitCard.currentDaySnapshot(cached, previous: previous,
                                                     habit: current, calendar: calendar)
        let view = card(current)
        let before = try render(view.recentGraph(snapshot: cached, viewportWidth: 300))
        let after = try render(view.recentGraph(snapshot: displayed, viewportWidth: 300))
        XCTAssertEqual(before.size, after.size)
        XCTAssertLessThanOrEqual(after.size.height, 190)
        let a = pixels(before), b = pixels(after)
        var changed: [CGPoint] = []
        for y in 0..<before.cgImage!.height {
            for x in 0..<before.cgImage!.width {
                let offset = (y * before.cgImage!.width + x) * 4
                if (0..<3).contains(where: { abs(Int(a[offset + $0]) - Int(b[offset + $0])) > 2 }) {
                    changed.append(CGPoint(x: x, y: y))
                }
            }
        }
        XCTAssertGreaterThan(changed.count, 40, "The shared Canvas must actually paint the check-in")
        XCTAssertLessThanOrEqual(changed.count, 20 * 20)
        let cell = ContributionChart.bandMetrics(width: 300).cell
        let todayRect = CGRect(x: 300 - cell, y: 3 * (cell + GridCell.gap) + 4,
                               width: cell, height: cell).insetBy(dx: -1, dy: -1)
        XCTAssertTrue(changed.allSatisfy { todayRect.contains($0) },
                      "Only Wednesday's square in the last column may change")
        let undone = HabitCard.currentDaySnapshot(displayed, previous: current,
                                                  habit: previous, calendar: calendar)
        let undoImage = try render(view.recentGraph(snapshot: undone, viewportWidth: 300))
        XCTAssertEqual(pixels(undoImage), a)
    }

    func testRecentGraphHeightAndChronologyStayStableAtWideAndNarrowWidths() throws {
        let current = habit()
        let view = card(current)
        for width in [CGFloat(180), 288, 1024] {
            let displayed = snapshot(current, width: width)
            let graph = view.recentGraph(snapshot: displayed, viewportWidth: width)
            let ltr = try render(graph.environment(\.layoutDirection, .leftToRight), width: width)
            let rtl = try render(graph.environment(\.layoutDirection, .rightToLeft), width: width)
            XCTAssertLessThanOrEqual(ltr.size.height, 190,
                                     "The measured window must not expand into giant tiles")
            XCTAssertEqual(ltr.size.width, width)
            XCTAssertEqual(pixels(ltr), pixels(rtl), "The shared graph's chronology must remain left to right")
        }
    }

    func testCalendarBandFillsItsDrawableWidthWithReadableSquareTiles() throws {
        let current = habit()
        for (width, weeks) in [(CGFloat(280), 18), (288, 19), (343, 23), (360, 24),
                               (370, 24), (400, 26), (408, 27), (680, 45)] {
            let displayed = GridCalendar.snapshot(habit: current, weeks: weeks,
                                                   today: today, calendar: calendar)
            let image = try render(card(current).recentGraph(snapshot: displayed,
                                                             viewportWidth: width), width: width)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            XCTAssertLessThan(image.size.height, 125, "The viewport must not stretch a short window into oversized tiles")
            let data = pixels(image)
            for x in [2, Int(width) - 3] {
                let offset = (6 * image.cgImage!.width + x) * 4
                XCTAssertLessThan(data[offset], 250, "Tiles must reach both inner edges, without a centered island")
            }
        }
    }

    func testBandCapacityTracksWidthAndKeepsBothEdgesExact() {
        for (width, weeks) in [(CGFloat(280), 18), (360, 24), (400, 26), (680, 45), (760, 50)] {
            let band = ContributionChart.bandMetrics(width: width)
            XCTAssertEqual(band.weeks, weeks)
            XCTAssertGreaterThanOrEqual(band.cell, 12)
            XCTAssertLessThan(band.cell, 15)
            XCTAssertEqual(CGFloat(band.weeks) * band.cell + CGFloat(band.weeks - 1) * GridCell.gap,
                           width, accuracy: 0.001)
        }
        XCTAssertEqual(ContributionChart.bandMetrics(width: 1024).weeks, 53)
        for width in [CGFloat.zero, -1, .nan, .infinity] {
            XCTAssertEqual(ContributionChart.bandMetrics(width: width).weeks, 1)
            XCTAssertEqual(ContributionChart.bandMetrics(width: width).cell, 12)
        }
    }

    func testResizeRequestsHistoryOnlyWhenTheVisibleColumnCountChanges() {
        let current = habit()
        let a = GridCalendar.HabitSnapshotKey(habit: current,
            weeks: ContributionChart.bandMetrics(width: 300).weeks, today: today, calendar: calendar)
        let fractionalResize = GridCalendar.HabitSnapshotKey(habit: current,
            weeks: ContributionChart.bandMetrics(width: 301).weeks, today: today, calendar: calendar)
        let wider = GridCalendar.HabitSnapshotKey(habit: current,
            weeks: ContributionChart.bandMetrics(width: 345).weeks, today: today, calendar: calendar)
        XCTAssertEqual(a, fractionalResize)
        XCTAssertNotEqual(a, wider)
        XCTAssertFalse(a.canDisplaySnapshot(for: wider), "A resized band must not paint a mismatched cached window")
    }

    func testUnchangedCardsRefreshOnTheirOwnCalendarDayRollover() {
        let before = DayKey.date(from: "2026-10-07", calendar: calendar)!.addingTimeInterval(23 * 3600 + 59 * 60)
        var first = card(habit())
        first.now = before
        var sameDay = first
        sameDay.now = before.addingTimeInterval(20)
        var nextDay = first
        nextDay.now = before.addingTimeInterval(120)
        XCTAssertTrue(first == sameDay)
        XCTAssertFalse(first == nextDay, "The page clock must refresh an unchanged card after midnight")

        var utc = GitHubContributionGraph(days: [], now: before)
        let oldUTC = utc
        utc.now = before.addingTimeInterval(120)
        XCTAssertFalse(oldUTC == utc)
        let snapshot = GitHubContributionSnapshot(username: "example", days: [], fetchedAt: before)
        var github = GitHubContributionCard(snapshot: snapshot, showsUsername: false,
                                             showsMonthLabels: false, openProfile: {}, now: before)
        let oldCard = github
        github.now = before.addingTimeInterval(120)
        XCTAssertFalse(oldCard == github)

        var la = calendar
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        first.calendar = la
        nextDay.calendar = la
        XCTAssertTrue(first == nextDay, "UTC midnight must not replace a card still on the same local day")
    }

    func testReminderRowsRefreshAtTheSameDayAppointmentBoundary() {
        var reminder = habit()
        reminder.itemType = .reminder
        reminder.createdAt = today
        reminder.timeMinutes = 10 * 60
        let due = DayKey.date(from: today, calendar: calendar)!.addingTimeInterval(10 * 3600)
        let before = reminderRow(reminder, now: due.addingTimeInterval(-60))
        let approaching = reminderRow(reminder, now: due.addingTimeInterval(-1))
        let atDue = reminderRow(reminder, now: due)
        let after = reminderRow(reminder, now: due.addingTimeInterval(1))
        XCTAssertEqual(ReminderOccurrenceEngine.state(for: reminder, now: before.now,
                                                       calendar: calendar).overdueCount, 0)
        XCTAssertEqual(ReminderOccurrenceEngine.state(for: reminder, now: atDue.now,
                                                       calendar: calendar).overdueCount, 1)
        XCTAssertTrue(before == approaching, "Ordinary clock ticks must not redraw unchanged rows")
        XCTAssertFalse(before == atDue, "The occurrence becomes due without a day-key change")
        XCTAssertFalse(atDue == after, "The overdue label changes just after the exact due time")
        XCTAssertTrue(after == reminderRow(reminder, now: due.addingTimeInterval(60)))
    }

    func testReminderRowsRefreshWhenDisplayTimeChangesWithoutAnEngineStateChange() {
        var reminder = habit()
        reminder.itemType = .reminder
        reminder.createdAt = today
        let due = ReminderOccurrenceEngine.dueDate(day: today, reminder: reminder,
                                                    calendar: calendar)!
        let before = reminderRow(reminder, now: due.addingTimeInterval(-1))
        let after = reminderRow(reminder, now: due.addingTimeInterval(1))
        XCTAssertEqual(ReminderOccurrenceEngine.state(for: reminder, now: before.now, calendar: calendar),
                       ReminderOccurrenceEngine.state(for: reminder, now: after.now, calendar: calendar),
                       "An all-day reminder's completion boundary remains midnight")
        XCTAssertFalse(before == after, "Equality must also track the rendered occurrence label")
    }

    func testReminderRowsCompareTheFullCalendarWithinTheSameDayAndTimeZone() {
        let first = reminderRow(Habit(name: "Call", itemType: .reminder),
                                now: DayKey.date(from: today, calendar: calendar)!)
        var changed = first
        changed.calendar.firstWeekday = first.calendar.firstWeekday == 1 ? 2 : 1
        XCTAssertEqual(first.calendar.timeZone, changed.calendar.timeZone)
        XCTAssertEqual(DayKey.key(for: first.now, calendar: first.calendar),
                       DayKey.key(for: changed.now, calendar: changed.calendar))
        XCTAssertFalse(first == changed)
        changed = first
        changed.calendar.locale = Locale(identifier: "de_DE")
        XCTAssertFalse(first == changed, "Calendar locale changes must refresh the row")
    }

    func testReminderRowsRefreshWhenTheCheckedOccurrenceLeavesLocalToday() {
        var reminder = habit()
        reminder.itemType = .reminder
        reminder.createdAt = today
        reminder.log = [today: 1]
        let midnight = DayKey.date(from: today, calendar: calendar)!.addingTimeInterval(24 * 3600)
        let before = reminderRow(reminder, now: midnight.addingTimeInterval(-1))
        let after = reminderRow(reminder, now: midnight)
        XCTAssertTrue(ReminderOccurrenceEngine.state(for: reminder, now: before.now, calendar: calendar)
            .isChecked(now: before.now, calendar: calendar))
        XCTAssertFalse(ReminderOccurrenceEngine.state(for: reminder, now: after.now, calendar: calendar)
            .isChecked(now: after.now, calendar: calendar))
        XCTAssertFalse(before == after)
        var compact = compactRow(reminder)
        compact.now = before.now
        var nextDay = compact
        nextDay.now = after.now
        XCTAssertFalse(compact == nextDay)
    }

    func testAddingDetailNavigationRefreshesEquatableCollectionEntries() {
        let legacyCard = card(habit())
        var detailCard = legacyCard
        detailCard.onDetails = {}
        XCTAssertFalse(legacyCard == detailCard, "The footer and name destination change together")
        let legacyReminder = reminderRow(Habit(name: "Call", itemType: .reminder), now: legacyCard.now)
        var detailReminder = legacyReminder
        detailReminder.onDetails = {}
        XCTAssertFalse(legacyReminder == detailReminder)
        let legacyCompact = compactRow(habit())
        var detailCompact = legacyCompact
        detailCompact.onDetails = {}
        XCTAssertFalse(legacyCompact == detailCompact)
    }

    func testCompactReminderClockRefreshDoesNotRedrawUnchangedTrackedHabits() {
        var reminder = habit()
        reminder.itemType = .reminder
        reminder.createdAt = today
        reminder.timeMinutes = 10 * 60
        var before = compactRow(reminder)
        before.now = before.now.addingTimeInterval(10 * 3600 - 1)
        var after = before
        after.now = before.now.addingTimeInterval(2)
        XCTAssertFalse(before == after, "The shared Today/Search row must refresh a same-day clock transition")
        var tracked = compactRow(habit())
        let unchanged = tracked
        tracked.now = tracked.now.addingTimeInterval(60)
        XCTAssertTrue(tracked == unchanged)
        tracked.calendar.firstWeekday = tracked.calendar.firstWeekday == 1 ? 2 : 1
        XCTAssertFalse(tracked == unchanged)
    }

    func testCompactReminderShowsOtherOpenOccurrencesWithoutInflatingTheAction() {
        var reminder = Habit(name: "Call", itemType: .reminder, timeMinutes: 10 * 60)
        reminder.createdAt = "2026-10-05"
        reminder.repeatsWhileIncomplete = true
        var row = compactRow(reminder)
        row.now = row.now.addingTimeInterval(12 * 3600)
        let state = ReminderOccurrenceEngine.state(for: reminder, now: row.now, calendar: calendar)
        XCTAssertEqual(state.overdueCount, 3)
        let occurrence = state.actionable!
        XCTAssertEqual(occurrence.day, "2026-10-05")
        XCTAssertEqual(row.subtitle, ReminderOccurrenceText.label(for: occurrence, includesTime: true,
            now: row.now, calendar: calendar) + " · +2 \(String(localized: "offen"))")
    }

    func testCompactNoStatusReflectsTheCurrentAnswerAndDisappearsOnUndo() {
        var current = habit(kind: .yesNo)
        current.log[today] = Habit.Answer.no
        XCTAssertEqual(compactRow(current).todayAnswer, String(localized: "Heute: Nein"))
        current.log[today] = Habit.Answer.yes
        XCTAssertNil(compactRow(current).todayAnswer)
        current.log[today] = nil
        XCTAssertNil(compactRow(current).todayAnswer)
    }

    func testCompactFlexibleProgressCountsCompletedDaysInTheCurrentPeriod() {
        for (frequency, earlierPeriod) in [(Recurrence.Frequency.weekly, "2026-10-01"),
                                          (.monthly, "2026-09-30"), (.yearly, "2025-12-31")] {
            for kind in [HabitKind.checkbox, .quantity, .yesNo] {
                var current = Habit(name: "Goal", recurrence: Recurrence(frequency: frequency,
                    timesPerPeriod: 3, target: kind == .quantity ? 3 : nil), kind: kind)
                current.createdAt = "2025-01-01"
                current.log = [earlierPeriod: 3, "2026-10-05": 3, "2026-10-06": 3,
                               "2026-10-08": 3, "1900-01-01": 3]
                if kind == .quantity { current.log[today] = 2 }
                if kind == .yesNo {
                    current.log["2026-10-05"] = Habit.Answer.yes
                    current.log["2026-10-06"] = Habit.Answer.no
                }
                let completed = kind == .yesNo ? 1 : 2
                let target = 3
                XCTAssertEqual(compactRow(current).periodProgress,
                               String(localized: "In dieser Periode: \(completed) von \(target) erledigt"))
            }
        }
    }

    func testCompactProgressDoesNotInventAQuotaForFixedOrInactiveItems() {
        XCTAssertNil(compactRow(habit()).periodProgress)
        let reminder = Habit(name: "Call", itemType: .reminder, recurrence: .times(3, per: .weekly))
        XCTAssertNil(compactRow(reminder).periodProgress)
        let future = Habit(name: "Goal", recurrence: .times(3, per: .weekly, start: "2026-10-08"))
        XCTAssertNil(compactRow(future).periodProgress)
        let ended = Habit(name: "Goal", recurrence: Recurrence(frequency: .weekly,
            end: .on("2026-10-06"), timesPerPeriod: 3))
        XCTAssertNil(compactRow(ended).periodProgress)
        let inactive = Habit(name: "Goal", recurrence: .times(3, per: .weekly, interval: 2,
                                                            start: "2026-09-28"))
        XCTAssertNil(compactRow(inactive).periodProgress)
    }

    func testCompactFlexibleProgressKeepsExtraCompletedDaysVisible() {
        var current = Habit(name: "Goal", recurrence: .times(1, per: .weekly))
        current.createdAt = "2026-10-01"
        current.log = ["2026-10-05": 1, "2026-10-06": 1]
        let completed = 2, target = 1
        XCTAssertEqual(compactRow(current).periodProgress,
                       String(localized: "In dieser Periode: \(completed) von \(target) erledigt"))
    }

    func testCompactRowsGrowForAX5WithoutShrinkingTextOrPaintingOutsideTheirWidth() throws {
        for style in AppDesignStyle.allCases {
            var items = HabitKind.allCases.map { habit(kind: $0) }
            items.append(Habit(name: "Call", itemType: .reminder))
            for var current in items {
                current.name = "Read a chapter and reflect before breakfast"
                let content = compactRow(current)
                    .environment(\.appearancePreferences, AppearancePreferences(designStyle: style))
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(width: 288)
                    .fixedSize(horizontal: false, vertical: true)
                let image = try render(content.padding(.horizontal, 8)
                    .background(Color(uiColor: .magenta)), width: 304)
                XCTAssertEqual(image.size.width, 304)
                XCTAssertGreaterThan(image.size.height, Theme.Metrics.hit * 2,
                                     "The identity and actions must stack and grow at AX5")
                let data = pixels(image)
                for y in 1..<(image.cgImage!.height - 1) {
                    for x in [0, 1, 302, 303] {
                        let offset = (y * image.cgImage!.width + x) * 4
                        XCTAssertEqual(Int(data[offset]), 255, accuracy: 2)
                        XCTAssertLessThan(data[offset + 1], 10, "Compact content must stay within its viewport")
                        XCTAssertEqual(Int(data[offset + 2]), 255, accuracy: 2)
                    }
                }
            }
        }
    }

    func testRenderedCardsStayBoundedAndAX5CanGrowWithoutHorizontalOverflow() throws {
        for style in AppDesignStyle.allCases {
            for collapsed in [false, true] {
                for textSize in [DynamicTypeSize.large, .accessibility5] {
                    var current = habit()
                    current.name = "Read a chapter and reflect before breakfast"
                    let content = card(current, collapsed: collapsed, onDetails: {})
                        .environment(\.appearancePreferences, AppearancePreferences(designStyle: style))
                        .environment(\.dynamicTypeSize, textSize)
                        .transaction { $0.disablesAnimations = true }
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(width: 288)
                        .fixedSize(horizontal: false, vertical: true)
                    let image = try render(content.background(Color.white)
                        .padding(.horizontal, 8).background(Color(uiColor: .magenta)), width: 304)
                    XCTAssertEqual(image.size.width, 304)
                    XCTAssertGreaterThan(image.size.height, Theme.Metrics.hit
                        + CGFloat(GridCalendar.rows) * GridCell.size
                        + CGFloat(GridCalendar.rows - 1) * GridCell.gap)
                    if textSize == .large { XCTAssertLessThan(image.size.height, 330) }
                    let data = pixels(image)
                    for y in 0..<image.cgImage!.height {
                        for x in [0, 1, 302, 303] {
                            let offset = (y * image.cgImage!.width + x) * 4
                            let alpha = Int(data[offset + 3])
                            // Fractional image heights can leave a partially covered boundary row.
                            // Interior rows must be opaque; all rows must retain premultiplied magenta.
                            if y > 0 && y < image.cgImage!.height - 1 {
                                XCTAssertEqual(alpha, 255, "Interior edge sample must be opaque")
                            }
                            XCTAssertEqual(Int(data[offset]), alpha, accuracy: 2,
                                           "Card paints outside its narrow viewport")
                            XCTAssertLessThan(data[offset + 1], 10, "Card paints outside its narrow viewport")
                            XCTAssertEqual(Int(data[offset + 2]), alpha, accuracy: 2,
                                           "Card paints outside its narrow viewport")
                        }
                    }
                }
            }
        }
    }

    private func assertOnlyTodayChanged(_ before: GridCalendar.Snapshot,
                                       _ after: GridCalendar.Snapshot,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.keys, after.keys, file: file, line: line)
        XCTAssertEqual(before.marks, after.marks, file: file, line: line)
        for column in before.keys.indices {
            for row in before.keys[column].indices where before.keys[column][row] != today {
                XCTAssertEqual(before.levels[column][row], after.levels[column][row], file: file, line: line)
            }
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat = 300) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: width).background(Color.white))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func pixels(_ image: UIImage) -> [UInt8] {
        let cg = image.cgImage!
        var result = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        result.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height,
                                    bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        return result
    }
}
