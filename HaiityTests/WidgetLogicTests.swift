import XCTest
import WidgetKit
@testable import Haiity

/// Die Rechnungen hinter den Widgets: welcher Habit steht drin, was sagt die
/// Statuszeile, wie voll ist der Tagesring, wie viele Zeilen passen in die
/// Übersicht und wie groß werden die Rasterzellen.
///
/// Alles hier ist rein — es braucht keinen Widget-Prozess und keine Fläche.
/// Genau deshalb steht die Logik in `WidgetLogic`/`GraphLayout` und nicht in
/// den Views: WidgetKit lässt sich nicht fernsteuern, diese Zahlen schon.
final class WidgetLogicTests: GridTestCase {

    // 2026-08-09 ist ein Sonntag (Anker der übrigen Testdateien).
    private let today = "2026-08-09"

    private func named(_ name: String,
                       recurrence: Recurrence = .daily,
                       log: [String: Int] = [:],
                       kind: HabitKind? = nil,
                       archived: String? = nil) -> Habit {
        var h = habit(log, recurrence: recurrence, createdAt: "2026-01-01")
        h.name = name
        if let kind { h.kind = kind }
        h.archivedAt = archived
        return h
    }

    // MARK: – Welcher Habit steht im Widget?

    func testResolveFallsBackToFirstActiveWhenUnset() {
        let a = named("A"), b = named("B")
        XCTAssertEqual(WidgetLogic.resolve(habits: [a, b], selected: nil)?.id, a.id)
    }

    func testResolvePicksTheSelectedHabit() {
        let a = named("A"), b = named("B")
        XCTAssertEqual(WidgetLogic.resolve(habits: [a, b], selected: b.id)?.id, b.id)
    }

    /// Ein gelöschter (oder auf diesem Gerät nie angelegter) Habit darf das
    /// Widget nicht leer zurücklassen.
    func testResolveFallsBackWhenSelectionIsGone() {
        let a = named("A")
        XCTAssertEqual(WidgetLogic.resolve(habits: [a], selected: UUID())?.id, a.id)
    }

    /// Archivierte zählen nirgends mit — auch dann nicht, wenn genau sie
    /// ausgewählt waren.
    func testResolveSkipsArchived() {
        let archived = named("Alt", archived: today)
        let active = named("Neu")
        XCTAssertEqual(WidgetLogic.resolve(habits: [archived, active], selected: nil)?.id, active.id)
        XCTAssertEqual(WidgetLogic.resolve(habits: [archived, active], selected: archived.id)?.id, active.id)
    }

    func testResolveWithoutHabitsIsNil() {
        XCTAssertNil(WidgetLogic.resolve(habits: [], selected: nil))
    }

    func testLargeResolverKeepsExplicitOrderAndFillsAutomaticSlots() {
        let a = named("A"), b = named("B"), c = named("C")
        let result = WidgetLogic.resolveLargeItems(
            habits: [a, b, c], selectedIDs: [b.id, nil, a.id], limit: 3,
            unlocked: true, today: today, calendar: cal)
        XCTAssertEqual(result.map(\.id), [b.id, c.id, a.id])
    }

    func testLargeResolverDeduplicatesExplicitAndAutomaticItems() {
        let a = named("A"), b = named("B")
        let result = WidgetLogic.resolveLargeItems(
            habits: [a, b], selectedIDs: [a.id, a.id, nil, nil], limit: 4,
            unlocked: true, today: today, calendar: cal)
        XCTAssertEqual(result.map(\.id), [a.id, b.id])
    }

    func testLargeResolverDropsArchivedDeletedAndProHiddenSelections() {
        let archived = named("Archived", archived: today)
        let live = named("Live")
        let result = WidgetLogic.resolveLargeItems(
            habits: [archived, live], selectedIDs: [archived.id, UUID()], limit: 2,
            unlocked: true, today: today, calendar: cal)
        XCTAssertEqual(result.map(\.id), [live.id])
    }

    func testLargeResolverAppliesFreeLimitWhenProIsLocked() {
        let habits = (1...5).map { named("H\($0)") }
        let result = WidgetLogic.resolveLargeItems(
            habits: habits, selectedIDs: habits.suffix(2).map(\.id), limit: 6,
            unlocked: false, today: today, calendar: cal)
        XCTAssertEqual(result.count, HabitVisibility.freeHabitLimit)
        XCTAssertTrue(result.allSatisfy { resultHabit in
            habits.prefix(HabitVisibility.freeHabitLimit).contains { $0.id == resultHabit.id }
        })
    }

    func testLargeResolverReturnsNoItemsForEmptyVisibleStore() {
        XCTAssertTrue(WidgetLogic.resolveLargeItems(
            habits: [], selectedIDs: [nil, nil, nil, nil], limit: 4,
            unlocked: true, today: today, calendar: cal).isEmpty)
    }

    func testLargeResolverUsesUnlockedSnapshotForRecommendation() {
        let visible = named("Visible")
        let filler = [named("Filler 1"), named("Filler 2")]
        var hidden = named("Hidden", log: [today: 1])
        for offset in 1...20 {
            hidden.log[DayKey.shifted(today, by: -offset, calendar: cal)!] = 1
        }

        let result = WidgetLogic.resolveLargeItems(
            habits: [visible] + filler + [hidden], selectedIDs: [nil], limit: 1,
            unlocked: false, today: today, calendar: cal)

        XCTAssertEqual(result.map(\.id), [visible.id])
    }

    func testWidgetsIncludeReminderItemsButGraphsRemainTrackedOnly() {
        var reminder = named("Tabletten", log: [today: 1])
        reminder.itemType = .reminder
        let tracked = named("Lesen")

        XCTAssertEqual(WidgetLogic.resolve(habits: [reminder, tracked], selected: reminder.id)?.id,
                       reminder.id)
        XCTAssertEqual(WidgetLogic.progress(habits: [reminder, tracked],
                                            today: today, calendar: cal).due, 1)
        XCTAssertEqual(WidgetLogic.roster([reminder, tracked], limit: 3).visible.map(\.name),
                       ["Tabletten", "Lesen"])
        XCTAssertEqual(WidgetLogic.resolveTrackedHabit(habits: [reminder, tracked],
                                                        selected: reminder.id)?.id,
                       tracked.id)
    }

    func testGraphResolutionHasATrackedHabitOnlyPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("HaiityWidget/WidgetLogic.swift"))
        XCTAssertTrue(source.contains("static func resolveTrackedHabit"))
    }

    func testMainWidgetCanResolveReminderAsAStandaloneToDo() {
        var reminder = named("Tabletten")
        reminder.itemType = .reminder

        XCTAssertEqual(WidgetLogic.resolve(habits: [reminder], selected: reminder.id)?.id,
                       reminder.id)
        XCTAssertEqual(WidgetLogic.status(habit: reminder, today: today, calendar: cal), .open)
    }

    // MARK: – Die Empfehlung: wer steht drin, wenn nichts eingestellt ist?

    /// Nicht der erste der Liste, sondern der mit der LÄNGSTEN laufenden
    /// Serie. Die Liste ist nach Anlagedatum sortiert — der zuerst angelegte
    /// Habit ist oft genau der, der längst eingeschlafen ist.
    func testRecommendedPicksTheLongestCurrentStreak() {
        let stale = named("Alt", log: run(days: 40, endingAt: "2026-01-10"))
        let live = named("Aktiv", log: run(days: 12, endingAt: today))
        let recommended = WidgetLogic.recommended(habits: [stale, live],
                                                  today: today, calendar: cal)
        XCTAssertEqual(recommended?.id, live.id)
    }

    /// Eine abgerissene Serie zählt nicht: 40 Tage, die gestern endeten,
    /// verlieren gegen 3, die heute noch laufen.
    func testRecommendedIgnoresBrokenStreaksHoweverLong() {
        let broken = named("Lang", log: run(days: 40, endingAt: "2026-08-07"))
        let short = named("Kurz", log: run(days: 3, endingAt: today))
        XCTAssertEqual(WidgetLogic.recommended(habits: [broken, short],
                                               today: today, calendar: cal)?.id,
                       short.id)
    }

    /// Gleichstand — der Normalfall in einem frischen Store, in dem jede
    /// Serie 0 ist — muss STABIL sein: sonst zeigt dasselbe Widget bei jedem
    /// Timeline-Aufbau einen anderen Habit.
    func testRecommendedIsStableOnATie() {
        let a = named("A"), b = named("B")
        XCTAssertEqual(WidgetLogic.recommended(habits: [a, b], today: today, calendar: cal)?.id, a.id)
        XCTAssertEqual(WidgetLogic.recommended(habits: [a, b], today: today, calendar: cal)?.id, a.id)
        let sameRun = run(days: 5, endingAt: today)
        let c = named("C", log: sameRun), d = named("D", log: sameRun)
        XCTAssertEqual(WidgetLogic.recommended(habits: [c, d], today: today, calendar: cal)?.id, c.id)
    }

    /// Ein archivierter Habit mit Rekordserie darf nicht empfohlen werden.
    func testRecommendedSkipsArchivedEvenWithTheLongestStreak() {
        let archived = named("Archiv", log: run(days: 90, endingAt: today), archived: today)
        let active = named("Aktiv", log: run(days: 2, endingAt: today))
        XCTAssertEqual(WidgetLogic.recommended(habits: [archived, active],
                                               today: today, calendar: cal)?.id,
                       active.id)
    }

    func testRecommendedWithoutHabitsIsNil() {
        XCTAssertNil(WidgetLogic.recommended(habits: [], today: today, calendar: cal))
        let archived = named("Archiv", archived: today)
        XCTAssertNil(WidgetLogic.recommended(habits: [archived], today: today, calendar: cal))
    }

    /// Und das Widget benutzt sie auch: ohne Einstellung steht der empfohlene
    /// Habit drin, mit Einstellung schlägt die Auswahl sie.
    func testResolveFallsBackToTheRecommendation() {
        let stale = named("Alt", log: run(days: 40, endingAt: "2026-01-10"))
        let live = named("Aktiv", log: run(days: 12, endingAt: today))
        XCTAssertEqual(WidgetLogic.resolve(habits: [stale, live], selected: nil,
                                           today: today, calendar: cal)?.id,
                       live.id)
        XCTAssertEqual(WidgetLogic.resolve(habits: [stale, live], selected: stale.id,
                                           today: today, calendar: cal)?.id,
                       stale.id)
    }

    // MARK: – Heute: fällig, erledigt oder frei?

    func testStatusOpenWhenScheduledAndUnchecked() {
        let h = named("Lesen")
        XCTAssertEqual(WidgetLogic.status(habit: h, today: today, calendar: cal), .open)
    }

    func testStatusDoneWhenCheckedOff() {
        let h = named("Lesen", log: [today: 1])
        XCTAssertEqual(WidgetLogic.status(habit: h, today: today, calendar: cal), .done)
    }

    /// Der Kern der Termin-Treue: Mo/Mi/Fr an einem Sonntag ist NICHT „heute
    /// noch offen", sondern frei — und der nächste Termin ist der Montag (2).
    func testStatusFreeWhenNotScheduledToday() {
        let h = named("Sport", recurrence: .weekdays([2, 4, 6]))
        XCTAssertEqual(WidgetLogic.status(habit: h, today: today, calendar: cal), .free(next: 2))
    }

    /// Ein Bonus-Check-in an einem freien Tag zählt (GoalEngine) — und soll
    /// auch so aussehen. „Erledigt" schlägt „frei".
    func testStatusDoneBeatsFree() {
        let h = named("Sport", recurrence: .weekdays([2, 4, 6]), log: [today: 1])
        XCTAssertEqual(WidgetLogic.status(habit: h, today: today, calendar: cal), .done)
    }

    /// Eine Regel ohne Termine (Alt-Form „alle sieben Tage Ruhetag") hat
    /// keinen nächsten Termin — der Text darf keinen erfinden.
    func testStatusFreeWithoutAnyFurtherOccurrence() {
        let h = named("Nichts", recurrence: .weekdays([]))
        XCTAssertEqual(WidgetLogic.status(habit: h, today: today, calendar: cal), .free(next: nil))
    }

    /// Mengen-Habits zählen erst ab dem Ziel als erledigt.
    func testStatusQuantityNeedsTheTarget() {
        let partial = named("Wasser", recurrence: Recurrence(target: 3), log: [today: 2])
        let full = named("Wasser", recurrence: Recurrence(target: 3), log: [today: 3])
        XCTAssertEqual(WidgetLogic.status(habit: partial, today: today, calendar: cal), .open)
        XCTAssertEqual(WidgetLogic.status(habit: full, today: today, calendar: cal), .done)
    }

    func testSummaryForCheckboxUsesStatusAndStreak() {
        let habit = named("Lesen", log: [today: 1])

        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: cal)

        XCTAssertEqual(summary.kind, .checkbox)
        XCTAssertEqual(summary.status, .done)
        XCTAssertEqual(summary.metricText, String(localized: "✓ Heute erledigt"))
        XCTAssertEqual(summary.metricSymbol, "checkmark.circle.fill")
    }

    func testSummaryForQuantityShowsCurrentAndTargetBeforeCompletion() {
        let habit = named("Wasser", recurrence: Recurrence(target: 3),
                          log: [today: 2], kind: .quantity)

        let summary = WidgetLogic.summary(habit: habit, today: today, calendar: cal)

        XCTAssertEqual(summary.kind, .quantity)
        XCTAssertEqual(summary.value, 2)
        XCTAssertEqual(summary.target, 3)
        XCTAssertEqual(summary.metricText, "2/3")
        XCTAssertEqual(summary.status, .open)
    }

    func testSummaryForYesNoDistinguishesYesNoAndOpen() {
        var yesNo = named("Zucker", kind: .yesNo)
        XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .open)

        yesNo.log[today] = Habit.Answer.no
        XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .no)

        yesNo.log[today] = Habit.Answer.yes
        XCTAssertEqual(WidgetLogic.summary(habit: yesNo, today: today, calendar: cal).answer, .yes)
    }

    func testSummaryForReminderUsesOpenAndFreeStates() {
        var due = named("Tabletten")
        due.itemType = .reminder

        var notDue = named("Arzt", recurrence: .weekdays([2, 4, 6]))
        notDue.itemType = .reminder

        let dueSummary = WidgetLogic.summary(habit: due, today: today, calendar: cal)
        let notDueSummary = WidgetLogic.summary(habit: notDue, today: today, calendar: cal)

        XCTAssertEqual(dueSummary.kind, .reminder)
        XCTAssertEqual(dueSummary.status, .open)
        XCTAssertEqual(dueSummary.metricText, String(localized: "Heute noch offen"))
        XCTAssertEqual(notDueSummary.kind, .reminder)
        XCTAssertEqual(notDueSummary.status, .free(next: 2))
        XCTAssertTrue(notDueSummary.metricText.contains(
            RecurrenceText.shortWeekdayName(2, calendar: cal)))
    }

    func testGitHubWidgetDaysKeepAValidEmptySnapshotStable() {
        let snapshot = GitHubContributionSnapshot(username: "enrzh",
                                                  days: [],
                                                  fetchedAt: Date(timeIntervalSince1970: 0))
        let anchor = DayKey.date(from: today, calendar: cal)!

        let days = WidgetLogic.gitHubWidgetDays(snapshot: snapshot, anchor: anchor, calendar: cal)

        XCTAssertEqual(days.count, 371)
        XCTAssertEqual(days.first?.level, 0)
        XCTAssertEqual(days.last?.level, 0)
        XCTAssertEqual(days.last?.date, today)
    }

    func testGitHubWidgetContentDistinguishesMissingFromValidEmptySnapshots() {
        let anchor = DayKey.date(from: today, calendar: cal)!
        let empty = GitHubContributionSnapshot(username: "enrzh",
                                               days: [],
                                               fetchedAt: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(WidgetLogic.gitHubWidgetContent(snapshot: nil,
                                                       anchor: anchor,
                                                       calendar: cal),
                       .connectPrompt)
        XCTAssertEqual(WidgetLogic.gitHubWidgetContent(snapshot: empty,
                                                       anchor: anchor,
                                                       calendar: cal),
                       .graph(days: WidgetLogic.gitHubWidgetDays(snapshot: empty,
                                                                 anchor: anchor,
                                                                 calendar: cal)))
    }

    func testOverviewInteractiveActionsAreOutsideTheFullCardLink() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/RosterWidgetView.swift"))
        let rowStart = try XCTUnwrap(source.range(of: "private func row("))
        let actionsStart = try XCTUnwrap(source.range(of: "private func actionButtons",
                                                      range: rowStart.upperBound..<source.endIndex))
        let row = source[rowStart.lowerBound..<actionsStart.lowerBound]
        let linkCount = row.components(separatedBy:
            "Link(destination: HaiityWidgetLink.habit(habit.id))").count - 1

        XCTAssertEqual(linkCount, 3,
                       "the graph, title, and metadata may navigate, but a link must not cover widget buttons")
    }

    func testOverviewUsesTheItemNegativePaletteForNo() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "HaiityWidget/RosterWidgetView.swift"))

        XCTAssertTrue(source.contains("palette.negative(dark: dark)"),
                      "No must use the habit palette instead of gray metadata")
        XCTAssertTrue(source.contains("private func statusTint"))
    }

    // MARK: – … und der Satz dazu

    func testStatusTextsAreDistinct() {
        let texts = [WidgetLogic.statusText(.done, calendar: cal),
                     WidgetLogic.statusText(.open, calendar: cal),
                     WidgetLogic.statusText(.free(next: 2), calendar: cal),
                     WidgetLogic.statusText(.free(next: nil), calendar: cal)]
        XCTAssertEqual(Set(texts).count, texts.count, "Jeder Zustand braucht seinen eigenen Satz")
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }

    /// „Frei bis Mo" — der Wochentag muss wirklich drinstehen, sonst ist der
    /// Satz nur eine andere Art, nichts zu sagen.
    func testFreeTextNamesTheNextWeekday() {
        let text = WidgetLogic.statusText(.free(next: 2), calendar: cal)
        XCTAssertTrue(text.contains(RecurrenceText.shortWeekdayName(2, calendar: cal)), text)
    }

    // MARK: – Tagesring

    func testProgressCountsOnlyHabitsDueToday() {
        let due = named("Lesen")
        let doneToday = named("Meditation", log: [today: 1])
        // Mo/Mi/Fr — an diesem Sonntag nicht fällig, steht in keiner Zahl.
        let free = named("Sport", recurrence: .weekdays([2, 4, 6]))
        let p = WidgetLogic.progress(habits: [due, doneToday, free], today: today, calendar: cal)
        XCTAssertEqual(p.due, 2)
        XCTAssertEqual(p.met, 1)
        XCTAssertEqual(p.fraction, 0.5, accuracy: 0.0001)
        XCTAssertFalse(p.isFree)
        XCTAssertFalse(p.isComplete)
    }

    func testProgressIgnoresArchived() {
        let p = WidgetLogic.progress(habits: [named("Alt", archived: today), named("Neu")],
                                     today: today, calendar: cal)
        XCTAssertEqual(p.due, 1)
    }

    /// Ein Tag ohne Termin ist VOLL, nicht leer — ein leerer Ring am Ruhetag
    /// läse sich wie ein Versäumnis.
    func testProgressWithoutDueHabitsIsFullAndFree() {
        let free = named("Sport", recurrence: .weekdays([2, 4, 6]))
        let p = WidgetLogic.progress(habits: [free], today: today, calendar: cal)
        XCTAssertEqual(p.due, 0)
        XCTAssertTrue(p.isFree)
        XCTAssertEqual(p.fraction, 1, accuracy: 0.0001)
        XCTAssertFalse(p.isComplete, "Ohne fälligen Habit gibt es nichts zu erfüllen")
    }

    func testProgressCompleteIsExactlyOne() {
        let p = WidgetLogic.progress(habits: [named("A", log: [today: 1]), named("B", log: [today: 1])],
                                     today: today, calendar: cal)
        XCTAssertTrue(p.isComplete)
        XCTAssertEqual(p.fraction, 1, accuracy: 0.0001)
    }

    /// Bonus-Check-ins an freien Tagen dürfen den Ring nicht über 100 %
    /// treiben — sie stehen in keinem der beiden Werte.
    func testProgressNeverExceedsOne() {
        let bonus = named("Sport", recurrence: .weekdays([2, 4, 6]), log: [today: 1])
        let p = WidgetLogic.progress(habits: [bonus, named("A", log: [today: 1])],
                                     today: today, calendar: cal)
        XCTAssertEqual(p.due, 1)
        XCTAssertEqual(p.met, 1)
        XCTAssertLessThanOrEqual(p.fraction, 1)
    }

    // MARK: – Übersicht

    func testRosterKeepsListOrderAndCountsTheRest() {
        let habits = (1...9).map { named("H\($0)") }
        let split = WidgetLogic.roster(habits, limit: WidgetLogic.rosterRowsMedium)
        XCTAssertEqual(split.visible.map(\.name), ["H1", "H2", "H3"])
        XCTAssertEqual(split.overflow, 6)
    }

    func testRosterWithoutOverflow() {
        let split = WidgetLogic.roster([named("A"), named("B")], limit: WidgetLogic.rosterRowsLarge)
        XCTAssertEqual(split.visible.count, 2)
        XCTAssertEqual(split.overflow, 0)
    }

    func testRosterIgnoresArchivedInBothNumbers() {
        let habits = [named("A"), named("Alt", archived: today), named("B"), named("C"), named("D")]
        let split = WidgetLogic.roster(habits, limit: 3)
        XCTAssertEqual(split.visible.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(split.overflow, 1)
    }

    func testRosterWithZeroLimitShowsNothingButStillCounts() {
        let split = WidgetLogic.roster([named("A"), named("B")], limit: 0)
        XCTAssertTrue(split.visible.isEmpty)
        XCTAssertEqual(split.overflow, 2)
    }

    func testRosterLimitGrowsWithTheFamily() {
        XCTAssertEqual(WidgetLogic.rosterLimit(for: .systemMedium), WidgetLogic.rosterRowsMedium)
        XCTAssertEqual(WidgetLogic.rosterLimit(for: .systemLarge), WidgetLogic.rosterRowsLarge)
        XCTAssertGreaterThan(WidgetLogic.rosterRowsLarge, WidgetLogic.rosterRowsMedium)
    }

    // MARK: – Timeline

    func testNextMidnightIsTomorrowsStartOfDay() {
        let noon = DayKey.date(from: today, calendar: cal)!.addingTimeInterval(12 * 3600)
        let next = WidgetLogic.nextMidnight(after: noon, calendar: cal)
        XCTAssertEqual(DayKey.key(for: next, calendar: cal), "2026-08-10")
        XCTAssertEqual(cal.startOfDay(for: next), next)
    }

    func testNextMidnightUsesSavedDefaultTimeZone() {
        var savedCalendar = cal
        savedCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var deviceCalendar = cal
        deviceCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = Date(timeIntervalSince1970: 1_786_344_658) // 2026-08-10 06:50 UTC / Aug 9 23:50 PDT

        let next = WidgetLogic.nextMidnight(after: instant, calendar: savedCalendar)
        let deviceNext = WidgetLogic.nextMidnight(after: instant, calendar: deviceCalendar)

        XCTAssertEqual(DayKey.key(for: next, calendar: savedCalendar), "2026-08-10")
        XCTAssertEqual(DayKey.key(for: next, calendar: deviceCalendar), "2026-08-10")
        XCTAssertEqual(DayKey.key(for: deviceNext, calendar: deviceCalendar), "2026-08-11")
        XCTAssertNotEqual(next, deviceNext)
        XCTAssertEqual(next, savedCalendar.startOfDay(for: next))
    }

    func testLargeTimelineReadsOneStoreSnapshotForEntryAndRefresh() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("HaiityWidget/HaiityWidget.swift"))
        let timeline = try XCTUnwrap(source.range(of: "static func largeTimeline"))
        let suffix = source[timeline.lowerBound...]
        let end = suffix.range(of: "    /// EIN Lesevorgang")?.lowerBound ?? suffix.endIndex
        let implementation = suffix[..<end]
        XCTAssertEqual(implementation.components(separatedBy: "HabitStore.read").count - 1, 1)
        XCTAssertTrue(implementation.contains("data: data"))
        XCTAssertTrue(implementation.contains("calendar: calendar"))
    }

    // MARK: – Rastergeometrie

    /// Die drei echten Homescreen-Flächen ABZÜGLICH der Innenränder (16 pt),
    /// so wie WidgetKit sie einem Widget übergibt.
    private static let canvases: [(name: String, size: CGSize)] = [
        ("klein", CGSize(width: 138, height: 138)),
        ("mittel", CGSize(width: 332, height: 138)),
        ("groß", CGSize(width: 332, height: 350)),
    ]

    /// Klein: die Zellen füllen die HÖHE, die Wochenzahl fällt aus der Breite.
    func testTrailingFillsTheCanvasWithoutOverflowing() {
        let layout = GraphLayout.trailing(width: 138, height: 60)
        XCTAssertGreaterThan(layout.weeks, 8)
        XCTAssertLessThanOrEqual(layout.contentWidth, 138.5)
        XCTAssertLessThanOrEqual(layout.contentHeight, 60.5)
        XCTAssertGreaterThan(layout.cell, layout.gap, "Zellen müssen größer sein als ihre Lücke")
    }

    /// Mehr Breite heißt mehr Wochen — nie weniger.
    func testTrailingWeeksGrowWithWidth() {
        let narrow = GraphLayout.trailing(width: 138, height: 60)
        let wide = GraphLayout.trailing(width: 332, height: 60)
        XCTAssertGreaterThan(wide.weeks, narrow.weeks)
    }

    func testTrailingNeverExceedsTheYear() {
        let layout = GraphLayout.trailing(width: 4000, height: 60)
        XCTAssertEqual(layout.weeks, 53)
        XCTAssertLessThanOrEqual(layout.contentWidth, 4000)
    }

    /// Der Kern des GitHub-Aussehens: das Band füllt die BREITE randlos aus.
    /// Ein Rest von einer ganzen Zelle wäre ein sichtbarer Streifen Leere und
    /// genau das, was dieses Widget nicht mehr tun soll.
    func testTrailingLeavesNoEmptyStripOnTheRealCanvases() {
        for (name, size) in Self.canvases {
            let layout = GraphLayout.trailing(width: size.width, height: size.height)
            XCTAssertLessThanOrEqual(layout.contentWidth, size.width + 0.5, name)
            XCTAssertGreaterThan(layout.contentWidth, size.width - layout.pitch,
                                 "\(name): rechts bleibt eine ganze Spalte leer")
        }
    }

    /// Und die HÖHE: sieben Zeilen, kein Streifen oben oder unten. Ein Rest
    /// von mehr als einer halben Zelle hieße, die Zelle ist zu klein
    /// gerechnet.
    func testTrailingCellComesFromTheHeight() {
        for (name, size) in Self.canvases {
            let layout = GraphLayout.trailing(width: size.width, height: size.height)
            XCTAssertLessThanOrEqual(layout.contentHeight, size.height + 0.5, name)
            XCTAssertGreaterThan(layout.contentHeight, size.height - layout.pitch / 2,
                                 "\(name): das Band füllt die Höhe nicht")
            // Höhe ÷ 7, minus Lücke — die Zelle hängt an der HÖHE, nicht an
            // der Wochenzahl. Die letzte Stauchung auf die Breite darf sie
            // nur noch um wenige Prozent verkleinern, nie mehr.
            XCTAssertEqual(layout.cell, size.height / 7 - layout.gap,
                           accuracy: layout.pitch * 0.1, name)
        }
    }

    /// Eine hohe Fläche bekommt GRÖSSERE Zellen, nicht mehr Wochen — genau
    /// der Handel, den das gewickelte Layout vorher andersherum gemacht hat.
    func testTallerCanvasMeansBiggerCellsNotMoreWeeks() {
        let medium = GraphLayout.trailing(width: 332, height: 138)
        let large = GraphLayout.trailing(width: 332, height: 350)
        XCTAssertGreaterThan(large.cell, medium.cell * 2)
        XCTAssertLessThan(large.weeks, medium.weeks)
    }

    /// Immer genau sieben Zeilen — es gibt keine zweite Reihe Bänder mehr,
    /// in der die Chronologie springen könnte.
    func testTrailingIsAlwaysExactlySevenRows() {
        for (name, size) in Self.canvases {
            let layout = GraphLayout.trailing(width: size.width, height: size.height)
            XCTAssertEqual(layout.contentHeight,
                           CGFloat(GraphLayout.rows) * layout.pitch - layout.gap,
                           accuracy: 0.001, name)
        }
    }

    /// Lesbarkeitsboden: die Lücke bleibt sichtbar UND kleiner als die Zelle.
    /// Fällt eines von beidem, verläuft das Raster zu einer Fläche.
    func testTrailingCellsStayDistinctAtEverySize() {
        for height in stride(from: 20.0, through: 360.0, by: 10.0) {
            for width in [76.0, 138.0, 172.0, 332.0] {
                let layout = GraphLayout.trailing(width: width, height: height)
                XCTAssertGreaterThanOrEqual(layout.gap, 0.5, "\(width)×\(height)")
                XCTAssertGreaterThan(layout.cell, layout.gap, "\(width)×\(height)")
                XCTAssertGreaterThanOrEqual(layout.weeks, 1, "\(width)×\(height)")
                XCTAssertLessThanOrEqual(layout.contentWidth, width + 0.5, "\(width)×\(height)")
                XCTAssertLessThanOrEqual(layout.contentHeight, height + 0.5, "\(width)×\(height)")
            }
        }
    }

    /// Der Eckradius wächst mit der Zelle — ein fester 2-pt-Radius wäre auf
    /// einer 40-pt-Zelle ein scharfes Quadrat.
    func testRadiusScalesWithTheCell() {
        let small = GraphLayout.trailing(width: 138, height: 138)
        let large = GraphLayout.trailing(width: 332, height: 350)
        XCTAssertGreaterThan(large.radius, small.radius)
        XCTAssertLessThan(large.radius, large.cell / 2, "Aus dem Quadrat darf kein Kreis werden")
    }

    func testTrailingSurvivesAZeroSizedCanvas() {
        let layout = GraphLayout.trailing(width: 0, height: 0)
        XCTAssertEqual(layout.weeks, 1)
        XCTAssertGreaterThan(layout.cell, 0)
        XCTAssertGreaterThan(layout.gap, 0)
    }

    // MARK: – Sperrbildschirm ohne Farbe

    /// Auf dem Sperrbildschirm überlebt nur HELLIGKEIT. Die fünf Stufen
    /// müssen deshalb streng steigen und weit genug auseinanderliegen —
    /// sonst sind sie nach der Umrechnung eine Fläche.
    func testMonochromeRampIsStrictlyIncreasing() {
        let steps = WidgetInk.opacities
        XCTAssertEqual(steps.count, 5)
        for i in 1..<steps.count {
            XCTAssertGreaterThan(steps[i], steps[i - 1])
            XCTAssertGreaterThanOrEqual(steps[i] - steps[i - 1], WidgetInk.minimumStep,
                                        "Stufe \(i) liegt zu dicht an \(i - 1)")
        }
        XCTAssertGreaterThan(steps[0], 0, "Die leere Zelle muss sichtbar bleiben")
        XCTAssertEqual(steps[4], 1, accuracy: 0.0001)
    }

    func testMonochromeRampClampsOutOfRangeLevels() {
        XCTAssertEqual(WidgetInk.opacity(-3), WidgetInk.opacities[0])
        XCTAssertEqual(WidgetInk.opacity(99), WidgetInk.opacities[4])
    }

    // MARK: – Homescreen mit kräftigerer Farbe

    func testHomeWidgetLiftsCompletedLevelsWithoutChangingEmptyOrDeclinedCells() {
        XCTAssertEqual(HomeWidgetInk.mappedLevel(0), 0)
        XCTAssertEqual(HomeWidgetInk.mappedLevel(1), 3)
        XCTAssertEqual(HomeWidgetInk.mappedLevel(2), 4)
        XCTAssertEqual(HomeWidgetInk.mappedLevel(3), 4)
        XCTAssertEqual(HomeWidgetInk.mappedLevel(4), 4)
        XCTAssertEqual(HomeWidgetInk.mappedLevel(Habit.Answer.declinedLevel),
                       Habit.Answer.declinedLevel)
    }

    func testHomeWidgetBackgroundTintStaysSubtleAndIsStrongerInDarkMode() {
        XCTAssertGreaterThan(HomeWidgetInk.darkBackgroundOpacity,
                             HomeWidgetInk.lightBackgroundOpacity)
        XCTAssertGreaterThan(HomeWidgetInk.lightBackgroundOpacity, 0)
        XCTAssertLessThanOrEqual(HomeWidgetInk.darkBackgroundOpacity, 0.2)
    }

    // MARK: – Der Eintrag

    func testEntryResolvesItsOwnHabit() {
        let a = named("A"), b = named("B")
        let entry = HaiityEntry(date: .now, habits: [a, b], selected: b.id)
        XCTAssertEqual(entry.habit?.id, b.id)
        XCTAssertEqual(HaiityEntry(date: .now, habits: [a, b]).habit?.id, a.id)
    }

    /// Der Platzhalter muss etwas ZEIGEN — ein leerer Galerie-Eintrag ist
    /// der Grund, warum Leute ein Widget nicht ablegen.
    func testDemoEntryHasHabitsAndHistory() {
        let demo = HaiityEntry.demo
        XCTAssertGreaterThanOrEqual(demo.habits.count, 3)
        XCTAssertNotNil(demo.habit)
        XCTAssertGreaterThan(demo.habits[0].checkInCount(), 100)
    }
}
