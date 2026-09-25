import XCTest
@testable import Haiity

/// The sentence path is the one place a language model fills in product fields,
/// so the tests are about the two things that can go wrong: a time being
/// misread, and a name that is not a name.
final class CreateHabitIntentTests: XCTestCase {

    // MARK: - The no-model time strip

    /// A clock time in a sentence is a fact, so it has to survive the model's
    /// involvement. `stripTime` is the deterministic half of that.
    func testAClockTimeIsFoundAndTakenOutOfTheName() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "morgens um 7:30 Wasser trinken")
        XCTAssertEqual(minutes, 7 * 60 + 30)
        XCTAssertFalse(name.contains("7:30"), "the time must not stay in the name")
        XCTAssertTrue(name.lowercased().contains("wasser"), "the thing itself must remain")
    }

    func testTheWrittenGermanHourFormIsUnderstood() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "jeden Tag 7 Uhr lesen")
        XCTAssertEqual(minutes, 7 * 60)
        XCTAssertTrue(name.lowercased().contains("lesen"))
    }

    func testDotSeparatedTimesAreUnderstood() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "Yoga um 18.15").minutes, 18 * 60 + 15)
    }

    func testEveningHoursAreUnderstood() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "call at 7 PM").minutes, 19 * 60)
    }

    /// Midnight and noon must not roll over into the wrong day.
    func testBoundaryHoursSurvive() {
        XCTAssertEqual(CreateItemDraft.stripTime(from: "mitternacht 00:30").minutes, 30)
        XCTAssertEqual(CreateItemDraft.stripTime(from: "mittag 12:00").minutes, 12 * 60)
        XCTAssertEqual(CreateItemDraft.stripTime(from: "23:45 ruhen").minutes, 23 * 60 + 45)
    }

    /// A sentence with no time in it must come through untouched. This is the
    /// path that decides NOT to guess, and it is the one most likely to be
    /// broken by an over-eager pattern.
    func testASentenceWithoutATimeIsLeftAlone() {
        for sentence in ["Wasser trinken", "Every morning stretch for ten minutes",
                         "täglich yoga", "morning pages"] {
            let (name, minutes) = CreateItemDraft.stripTime(from: sentence)
            XCTAssertNil(minutes, "\\(sentence) has no time")
            XCTAssertEqual(name, sentence, "\\(sentence) must not be rewritten")
        }
    }

    /// "Ten minutes" is a duration, not a clock time. Reading it as 10:00 would
    /// silently set the wrong notification.
    func testADurationIsNotMistakenForATime() {
        let (name, minutes) = CreateItemDraft.stripTime(from: "zehn minuten meditieren")
        XCTAssertNil(minutes)
        XCTAssertEqual(name.lowercased(), "zehn minuten meditieren")
    }

    /// A number that is not a valid hour must not be consumed.
    func testAnImpossibleHourIsNotTreatedAsATime() {
        XCTAssertNil(CreateItemDraft.stripTime(from: "99:99 lesen").minutes)
    }

    // MARK: - Reading without the model

    /// With the model switched off the sentence is still usable: a name, and a
    /// time if there was one. That is the honest degraded path.
    func testReadingWithoutTheModelStillProducesAUsableDraft() async {
        let draft = await CreateItemDraft.read(from: "morgens um 7:30 Wasser trinken",
                                               useModel: false)
        XCTAssertEqual(draft.minutes, 7 * 60 + 30)
        XCTAssertTrue(draft.name.lowercased().contains("wasser"))
        XCTAssertEqual(draft.emoji, "")
        XCTAssertFalse(draft.isReminder, "a bare sentence is a habit, not a one-off")
    }

    /// A sentence that is nothing but a time still needs a name. It must not
    /// produce an empty habit row.
    func testAnEmptyNameFallsBackToTheSentence() {
        let (name, _) = CreateItemDraft.stripTime(from: "07:00")
        XCTAssertFalse(name.isEmpty, "a name must survive even if the time was all there was")
    }

    // MARK: - Model output checks

    @available(iOS 26.0, *)
    func testAModelNameIsStrippedOfQuotesAndSentencePunctuation() {
        XCTAssertEqual(CreateItemWriter.validatedName("„Wasser trinken“"), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("\"Wasser trinken\""), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("Wasser trinken."), "Wasser trinken")
        XCTAssertEqual(CreateItemWriter.validatedName("  Wasser  "), "Wasser")
    }

    /// A model that echoed the whole sentence instead of extracting a name must
    /// be rejected, not stored as a habit name.
    @available(iOS 26.0, *)
    func testAnEchoedSentenceIsRejectedAsAName() {
        let sentence = String(repeating: "etwas ", count: 40)
        XCTAssertNil(CreateItemWriter.validatedName(sentence))
    }

    @available(iOS 26.0, *)
    func testAnEmptyOrOversizedNameIsRejected() {
        XCTAssertNil(CreateItemWriter.validatedName(""))
        XCTAssertNil(CreateItemWriter.validatedName("   "))
        let long = String(repeating: "a", count: CreateItemWriter.maxNameScalars + 1)
        XCTAssertNil(CreateItemWriter.validatedName(long))
    }

    /// One emoji or none. A list of options is not an emoji.
    @available(iOS 26.0, *)
    func testOnlyExactlyOneEmojiIsAccepted() {
        XCTAssertEqual(CreateItemWriter.validatedEmoji("💧"), "💧")
        XCTAssertEqual(CreateItemWriter.validatedEmoji(" 💧 "), "💧")
        XCTAssertEqual(CreateItemWriter.validatedEmoji("💧🏃"), "")
        XCTAssertEqual(CreateItemWriter.validatedEmoji("water"), "")
        XCTAssertEqual(CreateItemWriter.validatedEmoji(""), "")
    }

    // MARK: - The draft

    func testTheDraftProducesTheStoredHabitShape() {
        let draft = CreateItemDraft(name: "Wasser", emoji: "💧", minutes: 7 * 60,
                                    isReminder: false)
        let habit = draft.makeHabit()
        XCTAssertEqual(habit.name, "Wasser")
        XCTAssertEqual(habit.emoji, "💧")
        XCTAssertEqual(habit.timeMinutes, 7 * 60)
        XCTAssertEqual(habit.itemType, .habit)
    }

    func testAReminderDraftProducesAReminder() {
        let draft = CreateItemDraft(name: "Anruf", emoji: "", minutes: 15 * 60,
                                    isReminder: true)
        XCTAssertEqual(draft.makeHabit().itemType, .reminder)
        XCTAssertEqual(draft.kind, .reminder)
    }

    // MARK: - The repeat rule

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// The bug this whole section exists for: the draft's rule was never passed
    /// to `Habit`, and `Habit.init` defaults to `.daily`. So every sentence —
    /// including "jeden Montag" — became a daily habit and the person never saw
    /// it, because the preview also hard-coded "täglich".
    func testTheRepeatRuleReachesTheStoredHabit() {
        let schedule = CreateItemSchedule(frequency: "weekly", interval: 1,
                                          weekdays: [2], timesPerPeriod: 0,
                                          dayOfMonth: 0, month: 0, startDay: "")
        let habit = CreateItemDraft(name: "Wasser trinken", emoji: "💧",
                                    minutes: 7 * 60, schedule: schedule).makeHabit()
        XCTAssertEqual(habit.recurrence.frequency, .weekly)
        XCTAssertEqual(habit.recurrence.weekdays, [2])
        XCTAssertNotEqual(habit.recurrence, .daily,
                          "a weekly sentence must not be stored as a daily habit")
    }

    func testNamedWeekdaysBecomeTheDaysTheyName() {
        // 1 = Sunday … 7 = Saturday, the same numbering `Calendar` uses.
        let mondayAndThursday = CreateItemSchedule(
            frequency: "weekly", interval: 1, weekdays: [2, 5], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "")
        let rule = mondayAndThursday.recurrence
        XCTAssertEqual(rule.frequency, .weekly)
        XCTAssertEqual(rule.weekdays, [2, 5])
        XCTAssertTrue(rule.isScheduled(on: "2026-08-10", calendar: calendar), "a Monday")
        XCTAssertTrue(rule.isScheduled(on: "2026-08-13", calendar: calendar), "a Thursday")
        XCTAssertFalse(rule.isScheduled(on: "2026-08-11", calendar: calendar), "not a Tuesday")
    }

    /// The weekday numbering is stated in the prompt, so the prompt and the app
    /// have to agree. Getting this wrong teaches the model to put habits on the
    /// wrong day, which is worse than not reading the schedule at all.
    func testTheWeekdayNumberingThePromptGivesIsTheAppsNumbering() {
        var english = calendar
        english.locale = Locale(identifier: "en_US")
        // (Calendar weekday, English name, a date in August 2026 with that weekday)
        let cases: [(Int, String, String)] = [
            (1, "Sunday", "2026-08-16"),
            (2, "Monday", "2026-08-10"),
            (5, "Thursday", "2026-08-13"),
            (6, "Friday", "2026-08-14"),
            (7, "Saturday", "2026-08-15"),
        ]
        for (weekday, name, day) in cases {
            XCTAssertEqual(RecurrenceText.weekdayName(weekday, calendar: english), name)
            let rule = CreateItemSchedule(
                frequency: "weekly", interval: 1, weekdays: [weekday], timesPerPeriod: 0,
                dayOfMonth: 0, month: 0, startDay: "").recurrence
            XCTAssertTrue(rule.isScheduled(on: day, calendar: calendar),
                          "weekday \(weekday) must land on a \(name)")
        }
    }

    /// "Werktags" is five days, not one — the model has to be able to say so.
    func testWeekdaysCanNameEveryWorkingDay() {
        let weekdays = CreateItemSchedule(
            frequency: "weekly", interval: 1, weekdays: [2, 3, 4, 5, 6],
            timesPerPeriod: 0, dayOfMonth: 0, month: 0, startDay: "")
        XCTAssertEqual(weekdays.recurrence.weekdays.count, 5)
    }

    func testAFlexibleCountBecomesTheCount() {
        let threeTimes = CreateItemSchedule(
            frequency: "weekly", interval: 1, weekdays: [], timesPerPeriod: 3,
            dayOfMonth: 0, month: 0, startDay: "")
        let rule = threeTimes.recurrence
        XCTAssertEqual(rule.timesPerPeriod, 3)
        XCTAssertTrue(rule.isScheduled(on: "2026-08-10", calendar: calendar),
                      "a flexible week is active on any of its days")
    }

    /// "Every 2 weeks" has no named day, and the engine only fills in days when
    /// the rule is flexible. Without that it matches nothing at all — a habit
    /// that silently never fires, and reads "Keine Termine" in the editor.
    func testAnIntervalWithNoNamedDayStillSchedules() {
        let everyTwoWeeks = CreateItemSchedule(
            frequency: "weekly", interval: 2, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "")
        let rule = everyTwoWeeks.recurrence
        XCTAssertEqual(rule.interval, 2)
        XCTAssertEqual(rule.timesPerPeriod, 1, "one occurrence in an active fortnight")
        XCTAssertTrue(rule.isScheduled(on: "2026-08-10", calendar: calendar),
                      "the rule must actually reach a day, not just look well formed")
    }

    func testMonthlyKeepsTheDayOfTheMonth() {
        let rent = CreateItemSchedule(
            frequency: "monthly", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 15, month: 0, startDay: "")
        let rule = rent.recurrence
        XCTAssertEqual(rule.frequency, .monthly)
        XCTAssertTrue(rule.isScheduled(on: "2026-08-15", calendar: calendar))
        XCTAssertFalse(rule.isScheduled(on: "2026-08-16", calendar: calendar))
    }

    func testYearlyKeepsTheMonth() {
        let gifts = CreateItemSchedule(
            frequency: "yearly", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 24, month: 12, startDay: "")
        let rule = gifts.recurrence
        XCTAssertEqual(rule.frequency, .yearly)
        XCTAssertEqual(rule.month, 12)
        XCTAssertTrue(rule.isScheduled(on: "2026-12-24", calendar: calendar))
        XCTAssertFalse(rule.isScheduled(on: "2026-11-24", calendar: calendar))
    }

    func testAOneOffKeepsItsDate() {
        let once = CreateItemSchedule(
            frequency: "once", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "2027-03-14")
        let rule = once.recurrence
        XCTAssertEqual(rule.frequency, .once)
        XCTAssertTrue(rule.isScheduled(on: "2027-03-14", calendar: calendar))
        XCTAssertFalse(rule.isScheduled(on: "2027-03-15", calendar: calendar))
    }

    /// "Once" with no date can only mean from today. A `.once` rule with no start
    /// matches no day whatsoever, so a habit would be created that never appears.
    func testAOneOffWithoutADateFallsBackToTodayRatherThanNever() {
        let once = CreateItemSchedule(
            frequency: "once", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "")
        let rule = once.recurrence
        XCTAssertEqual(rule.start, DayKey.today())
        XCTAssertTrue(rule.isScheduled(on: DayKey.today(), calendar: calendar),
                      "a one-off must land somewhere, not on no day at all")
    }

    /// An unrecognised frequency has to become daily. A schedule that is merely
    /// absent is recoverable; one that is plausible and wrong is not.
    func testAnUnknownFrequencyBecomesDaily() {
        for raw in ["", "Daily", " every day ", "taeglich", "sometimes", "7"] {
            let schedule = CreateItemSchedule(
                frequency: raw, interval: 1, weekdays: [2], timesPerPeriod: 0,
                dayOfMonth: 0, month: 0, startDay: "")
            XCTAssertEqual(schedule.frequency, .daily, "\\(raw) should not be trusted")
        }
    }

    /// Case and spacing come from a model, so they cannot be assumed.
    func testFrequencyIsReadCaseAndSpaceInsensitively() {
        let schedule = CreateItemSchedule(
            frequency: "  Weekly ", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "")
        XCTAssertEqual(schedule.frequency, .weekly)
    }

    /// Every out-of-range value is dropped rather than clamped into meaning. A
    /// weekday 9 or a 99th of the month is a model miscount, not a request.
    func testImpossibleValuesAreDroppedRatherThanClamped() {
        let schedule = CreateItemSchedule(
            frequency: "weekly", interval: 0, weekdays: [0, 2, 8, -1],
            timesPerPeriod: -4, dayOfMonth: 99, month: 13, startDay: "not-a-day")
        XCTAssertEqual(schedule.interval, 1, "a zero interval still means every week")
        XCTAssertEqual(schedule.weekdays, [2])
        XCTAssertEqual(schedule.timesPerPeriod, 0)
        XCTAssertEqual(schedule.dayOfMonth, 0)
        XCTAssertEqual(schedule.month, 0)
        XCTAssertNil(schedule.startDay, "an unparseable date is worse than none")
    }

    func testAValidStartDayIsKept() {
        let schedule = CreateItemSchedule(
            frequency: "once", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: " 2027-03-14 ")
        XCTAssertEqual(schedule.startDay, "2027-03-14")
    }

    /// A draft with no schedule is daily, and that is what the no-model path
    /// produces. The deterministic parser reads a clock time and nothing else,
    /// so it must not start claiming a repeat it did not parse.
    func testTheNoModelPathDoesNotInventARepeat() async {
        let draft = await CreateItemDraft.read(from: "jeden Montag lesen", useModel: false)
        XCTAssertEqual(draft.schedule, .daily)
        XCTAssertEqual(draft.makeHabit().recurrence, .daily)
    }

    // MARK: - The schedule contract, in the source

    /// The prompt used to tell the model to strip "every morning" and gave it
    /// nowhere to put it, which is why the repeat was always wrong. Both halves
    /// of that sentence have to stay: the strip and the field it goes into.
    func testThePromptPutsTheScheduleSomewhereInsteadOfThrowingItAway() throws {
        let source = try scheduleSourceURL("Haiity/Services/CreateItemWriter.swift")
        let writer = try String(contentsOf: source, encoding: .utf8)

        XCTAssertTrue(writer.contains("weekdays"),
                      "the model has to be given a field for named days")
        XCTAssertTrue(writer.contains("timesPerPeriod"),
                      "the model has to be given a field for a flexible count")
        XCTAssertTrue(writer.contains("interval"),
                      "the model has to be given a field for the period count")
        // The worked examples are the part that actually carries the behaviour,
        // so a prompt rewrite cannot quietly drop them.
        for example in ["jeden Montag und Donnerstag", "3 mal pro Woche",
                        "alle zwei Wochen", "einmal am 14. März",
                        "jeden Monat am 15.", "jedes Jahr im Dezember"] {
            XCTAssertTrue(writer.contains(example),
                          "the prompt lost its worked example: \(example)")
        }
        // A date in the past is the failure that produced a one-off which could
        // never fire, so the prompt has to rule it out at the source as well as
        // the mapping repairing it.
        XCTAssertTrue(writer.contains("never be in the past"),
                      "the prompt must forbid a past date, not just say which year to use")
    }

    /// The preview used to append a hard-coded "täglich", so it showed a daily
    /// habit even when the parse behind it was right.
    func testThePreviewNoLongerHardCodesDaily() throws {
        let source = try scheduleSourceURL("Haiity/Views/SpeakToCreateSheet.swift")
        let sheet = try String(contentsOf: source, encoding: .utf8)
        let subtitle = try XCTUnwrap(sheet.range(of: "func draftSubtitle"))
        let body = sheet[subtitle.upperBound...].prefix(900)

        XCTAssertFalse(body.contains("String(localized: \"täglich\")"),
                       "the preview must show the actual rule, not a fixed one")
        XCTAssertTrue(body.contains("RecurrenceText.pattern"),
                      "the preview should reuse the one tested recurrence sentence")
    }

    private func scheduleSourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    // MARK: - Writing through the store the list is watching

    /// The habit has to land in the instance the list is already observing, not
    /// merely on disk.
    ///
    /// This is the "it didn't create the entry, it only shows up after a
    /// restart" bug. A second `HabitStore` on the same file writes the habit
    /// perfectly well, so nothing errors and nothing looks wrong — but the list
    /// is bound to the first instance, and the only re-read runs when the app
    /// comes back to the foreground.
    @MainActor
    func testTheHabitLandsInTheStoreThatWasPassedIn() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("create-saver-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url)

        let outcome = await CreateItemSaver.save(
            CreateItemDraft(name: "Wasser trinken", emoji: "💧", minutes: 7 * 60),
            into: store)

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(store.habits.count, 1,
                       "the store the list observes must see the habit immediately")
        XCTAssertEqual(store.habits.first?.name, "Wasser trinken")
        // And it is genuinely on disk too, so a restart agrees with the screen.
        XCTAssertEqual(HabitStore(url: url).habits.count, 1)
    }

    /// The sheet has a store handed to it and used to ignore it, which is what
    /// let the saver quietly open its own. Cheap to check, easy to regress.
    func testTheSpeakSheetSavesIntoTheStoreItWasGiven() throws {
        let source = try scheduleSourceURL("Haiity/Views/SpeakToCreateSheet.swift")
        let sheet = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(sheet.contains("save(draft, into: store)"),
                      "the sheet must write through the store the list is observing")
        XCTAssertFalse(sheet.contains("save(draft)"),
                       "saving without the store is the bug this replaces")
    }

    // MARK: - A date that has already gone

    /// A one-off in the past is a habit that can never fire — it appears on no
    /// day at all — so the day moves to the next time that month and day come
    /// round. Said in September, "einmal am 14. März" is the March coming.
    func testAPastOneOffMovesToWhenThatDayComesRoundAgain() throws {
        let past = CreateItemSchedule(
            frequency: "once", interval: 1, weekdays: [], timesPerPeriod: 0,
            dayOfMonth: 0, month: 0, startDay: "2020-03-14")
        let rule = past.recurrence
        let start = try XCTUnwrap(rule.start)

        XCTAssertGreaterThan(start, DayKey.today(calendar: calendar),
                             "a one-off must never be left in the past")
        XCTAssertTrue(start.hasSuffix("-03-14"),
                      "the month and day the person said are kept, got \(start)")
        XCTAssertTrue(rule.isScheduled(on: start, calendar: calendar),
                      "and it has to land on a real day")
    }

    /// A future date is left exactly as it was — the roll-forward is a repair,
    /// not a transformation.
    func testAFutureOneOffIsLeftAlone() {
        XCTAssertEqual(CreateItemSchedule.upcoming("2099-12-24", calendar: calendar), "2099-12-24")
    }

    func testTodayIsLeftAlone() {
        let today = DayKey.today(calendar: calendar)
        XCTAssertEqual(CreateItemSchedule.upcoming(today, calendar: calendar), today)
    }

    /// 29 February in a common year has to become the 28th, not roll into March.
    /// `Calendar` would silently give the 1st of March, and then the person asked
    /// for the 29th and got something else entirely.
    func testTheTwentyNinthOfFebruaryIsClampedInsideItsMonth() {
        // 2027 is not a leap year.
        let moved = CreateItemSchedule.upcoming("2024-02-29", calendar: calendar)
        XCTAssertEqual(moved, "2027-02-28")
        XCTAssertTrue(DayKey.isValid(moved, calendar: calendar))
    }

    /// A date far enough back still has to end up ahead of today, not give up.
    func testAVeryOldDateStillLandsInTheFuture() {
        let moved = CreateItemSchedule.upcoming("1999-07-04", calendar: calendar)
        XCTAssertGreaterThan(moved, DayKey.today(calendar: calendar))
    }

    func testAnUnparseableDateFallsBackToToday() {
        XCTAssertEqual(CreateItemSchedule.upcoming("not-a-day", calendar: calendar),
                       DayKey.today(calendar: calendar))
    }

    // MARK: - The free allowance

    /// The Shortcut path is a creation path, so the free habit limit has to
    /// apply to it exactly as it does in the editor. This is the test that stops
    /// a shortcut from becoming a way around the paywall.
    func testTheFreeHabitLimitAppliesToTheShortcutToo() {
        let free = ProGate.freeHabitLimit
        for count in 0..<free {
            XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                       targetIsTracked: true,
                                                       activeCount: count,
                                                       unlocked: false),
                          "count \\(count) should still be inside the free allowance")
        }
        XCTAssertFalse(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                    targetIsTracked: true,
                                                    activeCount: free,
                                                    unlocked: false),
                       "the limit must hold for a shortcut-created habit")
        // A reminder stays free, and unlocking lifts the limit.
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                   targetIsTracked: false,
                                                   activeCount: free + 10,
                                                   unlocked: false))
        XCTAssertTrue(ProGate.maySaveTrackedHabit(existingIsTracked: false,
                                                   targetIsTracked: true,
                                                   activeCount: free + 10,
                                                   unlocked: true))
    }

    private func sourceURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    // MARK: - Published surface

    /// Both intents stay reachable from the Shortcuts editor, and the one that
    /// needs the model says so where a person will read it before building an
    /// automation around it.
    func testBothCreateIntentsArePublishedWithHonestDescriptions() throws {
        let source = try String(contentsOf: sourceURL("Haiity/Intents/CreateHabitIntent.swift"))
        XCTAssertTrue(source.contains("struct CreateHabitIntent: AppIntent"))
        XCTAssertTrue(source.contains("struct CreateItemFromTextIntent: AppIntent"))
        XCTAssertTrue(source.contains("Benötigt ein unterstütztes Gerät"),
                      "the model-backed intent must state its requirement up front")
    }

    /// Regression guard for ITMS-90626.
    ///
    /// Apple's Siri metadata validation rejects an App Intent description that
    /// contains a brand or platform name. Build 216 was refused for containing
    /// "Apple"; "iOS" is on the same blocklist and went too. That validation
    /// cannot be run locally, and a refusal costs a whole build and review
    /// cycle — so the blocklist is checked here instead of discovered on App
    /// Store Connect.
    func testNoAppIntentMetadataMentionsABrandOrPlatform() throws {
        let blocked = ["apple", "siri", "iphone", "ipad", "macbook", "ios",
                       "itunes", "icloud", "app store", "airpods", "vision pro"]
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Haiity/Intents")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(files.isEmpty, "the intents directory must exist for this guard to mean anything")

        for name in files where name.hasSuffix(".swift") {
            let raw = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            // A comment is documentation. Only the code the validator actually
            // reads is checked, otherwise this test would forbid the very note
            // that explains why the terms are forbidden.
            let metadata = raw.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            // Extract the CONTENTS of double-quoted literals properly. Splitting
            // the file on a quote character would also match identifiers such as
            // `AppIntents`, and quote parity breaks on anything escaped.
            let literal = try NSRegularExpression(pattern: "\"((?:[^\"\\\\]|\\\\.)*)\"")
            let range = NSRange(metadata.startIndex..<metadata.endIndex, in: metadata)
            for match in literal.matches(in: metadata, range: range) {
                guard let found = Range(match.range(at: 1), in: metadata) else { continue }
                let lower = metadata[found].lowercased()
                for term in blocked where lower.contains(term) {
                    XCTFail("\(name) mentions \"\(term)\" in App Intent metadata: \(metadata[found].prefix(90))")
                }
            }
        }
    }

    /// An `AppShortcut` phrase may only interpolate an `AppEntity`, because Siri
    /// builds its corpus from the entities it can offer. A free-text `String`
    /// parameter has no such list, so a phrase naming one does not work — it
    /// emits an "unresolved variable" warning for every utterance and silently
    /// contributes nothing. That was 187 build warnings; this is the guard.
    func testNoShortcutPhraseInterpolatesAFreeTextParameter() throws {
        let shortcuts = try String(contentsOf: sourceURL("Haiity/Intents/HaiityShortcuts.swift"))
        for phrase in ["\\.$name", "\\.$text", "\\.$title", "\\.$query"] {
            XCTAssertFalse(shortcuts.contains(phrase),
                           "a Siri phrase cannot interpolate the free-text parameter \(phrase)")
        }
        // The entity-based phrases are the ones that resolve, and they stay.
        XCTAssertTrue(shortcuts.contains("\\.$habit"))
        XCTAssertTrue(shortcuts.contains("intent: CheckOffHabitIntent()"))
        XCTAssertTrue(shortcuts.contains("intent: HabitStatusIntent()"))
        // And the reason is written down, so nobody helpfully re-adds them.
        XCTAssertTrue(shortcuts.contains("may only interpolate an `AppEntity`"),
                      "the reason for omitting these phrases must be documented in the file")
    }
}
