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

    private func card(_ habit: Habit, collapsed: Bool = false) -> HabitCard {
        HabitCard(habit: habit, collapsed: collapsed, showsMonthLabels: false,
                  onToggleDay: { _ in }, onBackfill: {}, onIncrement: {}, onClear: {},
                  onMarkDone: {}, onEdit: {}, onArchive: {}, calendar: calendar)
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
        for (width, weeks) in [(CGFloat(280), 18), (360, 24), (400, 26), (680, 45)] {
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

    func testRenderedCardsStayBoundedAndAX5CanGrowWithoutHorizontalOverflow() throws {
        for style in AppDesignStyle.allCases {
            for collapsed in [false, true] {
                for textSize in [DynamicTypeSize.large, .accessibility5] {
                    var current = habit()
                    current.name = "Read a chapter and reflect before breakfast"
                    let content = card(current, collapsed: collapsed)
                        .environment(\.appearancePreferences, AppearancePreferences(designStyle: style))
                        .environment(\.dynamicTypeSize, textSize)
                        .transaction { $0.disablesAnimations = true }
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(width: 288)
                        .fixedSize(horizontal: false, vertical: true)
                    let image = try render(content.background(Color.white)
                        .padding(.horizontal, 8).background(Color(uiColor: .magenta)), width: 304)
                    XCTAssertEqual(image.size.width, 304)
                    XCTAssertGreaterThan(image.size.height, 180)
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
