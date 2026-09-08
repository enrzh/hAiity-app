import XCTest
@testable import Haiity

final class MotivationTests: XCTestCase {
    func testPoolHas288CombinationsAndMatchingOpeners() {
        XCTAssertEqual(Motivation.openersNamed.count, 12)
        XCTAssertEqual(Motivation.openersPlain.count, 12)
        XCTAssertEqual(Motivation.lines.count, 24)
        XCTAssertEqual(Motivation.openersNamed.count * Motivation.lines.count, 288)
        XCTAssertTrue(Motivation.openersNamed.allSatisfy { $0.contains("%@") })
        XCTAssertTrue(Motivation.openersPlain.allSatisfy { !$0.contains("%@") })
        XCTAssertTrue(Motivation.lines.allSatisfy { !$0.contains("%@") })
    }

    func testMessageIsStableForTheDayAndHandlesAnOptionalName() {
        let named = Motivation.message(name: "Mo", today: "2026-08-14")
        XCTAssertEqual(named.title, Motivation.message(name: "Mo", today: "2026-08-14").title)
        XCTAssertEqual(named.body, Motivation.message(name: "Mo", today: "2026-08-14").body)
        XCTAssertTrue(named.title.contains("Mo"))
        XCTAssertFalse(named.title.contains("%@"))

        let plain = Motivation.message(name: nil, today: "2026-08-14")
        XCTAssertEqual(plain.title, Motivation.message(name: "", today: "2026-08-14").title)
        XCTAssertEqual(named.body, plain.body)
        XCTAssertFalse(plain.title.contains("%@"))
    }

    func testAdditionalMatchingEntriesAreStableAndEmptyFallsBack() {
        let entries = [MotivationFeedEntry(text: "Cached one", language: "en", author: nil),
                       MotivationFeedEntry(text: "Cached two", language: "en-US", author: nil)]
        let first = Motivation.message(name: nil, today: "2026-08-14", additionalEntries: entries,
                                       languageCode: "en")
        let repeated = Motivation.message(name: nil, today: "2026-08-14", additionalEntries: entries,
                                          languageCode: "en")
        XCTAssertEqual(first.title, repeated.title)
        XCTAssertEqual(first.body, repeated.body)
        XCTAssertTrue(["Cached one", "Cached two"].contains(first.body))
        XCTAssertEqual(Motivation.message(name: nil, today: "2026-08-14", additionalEntries: [],
                                          languageCode: "de").body,
                       Motivation.message(name: nil, today: "2026-08-14", languageCode: "de").body)
    }

    func testSaltedIndicesCoverMostCombinationsAcrossThreeYears() {
        var pairs = Set<String>()
        var day = "2026-01-01"
        for _ in 0..<1095 {
            let opener = Motivation.index(for: day, salt: Motivation.openerSalt, count: 12)
            let line = Motivation.index(for: day, salt: Motivation.lineSalt, count: 24)
            pairs.insert("\(opener)-\(line)")
            day = DayKey.shifted(day, by: 1) ?? day
        }
        XCTAssertGreaterThanOrEqual(pairs.count, 250,
                                    "hash salts have become correlated again")
    }

    func testMoreCarriesTheOptInSettingAndTimePicker() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("motivationRows"))
        XCTAssertTrue(more.contains("store.motivationMinutes"))
        XCTAssertTrue(more.contains("\"motivation-toggle\""))
        XCTAssertTrue(more.contains("\"motivation-time\""))
        XCTAssertTrue(more.contains("\"motivation-delivery\""))
        XCTAssertTrue(more.contains("Live-Aktivitäten starten"))
        XCTAssertTrue(more.contains("Reminders.ensurePermission()"))
        XCTAssertTrue(more.contains("motivation-open-source-toggle"))
        XCTAssertTrue(more.contains("MotivationFeed.refreshIfNeeded"))
        XCTAssertTrue(more.contains("MotivationFeedCache.clear"))
        XCTAssertTrue(more.contains("Reminders.reschedule(store: store)"))
        XCTAssertTrue(more.contains("MotivationActivityManager.shared.reconcile"))
        XCTAssertTrue(more.contains("Fehler – integrierte Nachrichten bleiben aktiv"))
        XCTAssertTrue(more.contains("letzter Bestand bleibt aktiv"))
        XCTAssertTrue(more.contains("MIT-Lizenz"))
        XCTAssertTrue(more.contains("https://github.com/mubaris/motivate"))
        XCTAssertTrue(more.contains("guard store.openSourceMotivationEnabled else"))
        XCTAssertTrue(more.contains("throw CancellationError()"))
        XCTAssertTrue(more.contains("openSourceMotivationEnabled"))
        let manager = try source("Haiity/Services/MotivationActivityManager.swift")
        XCTAssertTrue(manager.contains("additionalEntries: [MotivationFeedEntry] = []"))
        XCTAssertTrue(manager.contains("Motivation.message(name: name, today: dayKey,"))
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("additionalEntries: MotivationFeedCache.load"))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.title"))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.symbolName"))
        XCTAssertFalse(more.contains("DND (Do not disturb)"))
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(developer.contains("copy-sync-watermark"))
        XCTAssertFalse(more.contains("ForEach(SyncWatermark.Kind.allCases"))
        XCTAssertTrue(more.contains("notification-actions-toggle"))
    }

    func testMoreNotificationSettingsUseAUnifiedAppleStyleHierarchy() throws {
        let more = try source("Haiity/Views/MoreView.swift")

        XCTAssertTrue(more.contains(".font(.footnote.weight(.semibold))"))
        XCTAssertTrue(more.contains("notificationSymbolSurface"))
        XCTAssertTrue(more.contains("notificationDetailsInset"))
    }

    func testMotivationSourceLinkCannotOwnTheWholeNotificationGroup() throws {
        let more = try source("Haiity/Views/MoreView.swift")

        XCTAssertTrue(more.contains("UIApplication.shared.open(motivationSourceURL)"))
        XCTAssertTrue(more.contains("Label(String(localized: \"Quelle: mubaris/motivate · MIT-Lizenz\")"),
                      "the source label must remain visible")
        XCTAssertTrue(more.contains("Button(action: openMotivationSource)"),
                      "the source action must be an explicit local control")
        XCTAssertTrue(more.contains(".buttonStyle(.borderless)"),
                      "the source button must keep its intrinsic hit target")
        XCTAssertFalse(more.contains(".onTapGesture(perform: openMotivationSource)"),
                       "a gesture on the source label can expand across the List row")
        XCTAssertFalse(more.contains("Link(destination: URL(string: \"https://github.com/mubaris/motivate\")!"),
                       "a SwiftUI Link can expand its hit region across the List row")
    }

    func testDoNotDisturbUsesOneLocalizedPresentationSource() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        let reminders = try source("Haiity/Services/Reminders.swift")

        XCTAssertTrue(reminders.contains("enum NotificationDNDPresentation"))
        XCTAssertTrue(reminders.contains("static let symbolName = \"moon.zzz.fill\""))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.title"))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.symbolName"))
        XCTAssertFalse(more.contains("String(localized: \"Do not disturb\")"))
        XCTAssertFalse(more.contains("systemImage: \"moon.zzz.fill\""))
    }

    func testDoNotDisturbSuppressesOnlyWhileActive() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(Reminders.shouldScheduleNotifications(
            state: .active(.twoHours, now: now), now: now))
        XCTAssertFalse(Reminders.shouldScheduleNotifications(
            state: .active(.untilDisabled, now: now), now: now.addingTimeInterval(365 * 24 * 60 * 60)))
        XCTAssertTrue(Reminders.shouldScheduleNotifications(
            state: .active(.twoHours, now: now), now: now.addingTimeInterval(2 * 60 * 60)))
    }

    func testApplyingDNDReschedulesImmediately() throws {
        let more = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("NotificationPromptPreference.state = state"))
        XCTAssertTrue(more.contains("await Reminders.reschedule(store: store)"))
    }

    func testMotivationLinesStayShortEnoughForNotifications() {
        XCTAssertTrue(Motivation.lines.allSatisfy { $0.count <= 84 })
    }

    func testOpenSourceMotivationDefaultsOffForLegacyJSON() throws {
        let raw = try XCTUnwrap("{\"version\":2,\"updatedAt\":1,\"habits\":[]}".data(using: .utf8))
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertFalse(data.openSourceMotivationEnabled)
    }

    func testOpenSourceMotivationPersistsWhenEnabled() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("motivation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url, loadFromDisk: false)
        store.openSourceMotivationEnabled = true

        XCTAssertTrue(HabitStore(url: url).openSourceMotivationEnabled)
    }

    func testNewerRemoteOpenSourceMotivationSettingWins() {
        let store = HabitStore(loadFromDisk: false)
        store.openSourceMotivationEnabled = false
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: 2,
                               summaryMinutes: nil,
                               habits: [],
                               openSourceMotivationEnabled: true)

        store.merge(remote: remote)

        XCTAssertTrue(store.openSourceMotivationEnabled)
    }

    func testNewerRemoteHabitMergePreservesAllNotificationModes() {
        for mode in HabitNotificationMode.allCases {
            var localHabit = Habit(name: "Local", notificationMode: .off)
            var remoteHabit = localHabit
            remoteHabit.notificationMode = mode
            let store = HabitStore(loadFromDisk: false)
            store.add(localHabit)
            let remote = HabitData(version: HabitData.currentVersion,
                                   updatedAt: store.data.updatedAt + 1,
                                   summaryMinutes: nil, habits: [remoteHabit])

            store.merge(remote: remote)

            XCTAssertEqual(store.habits.first?.notificationMode, mode)
        }
    }

    func testTargetAndCatalogCarryMotivation() throws {
        let yml = try source("project.yml")
        XCTAssertTrue(yml.contains("Haiity/Models/Motivation.swift"))

        let data = try Data(contentsOf: root.appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for key in ["Tägliche Motivation",
                    "Jeden Tag ein anderer kurzer Gedanke aus deinem Raster — ruhig, ohne Druck."] {
            XCTAssertNotNil(strings[key], "fehlt im Katalog: \(key)")
        }
    }

    func testDoNotDisturbHasGermanAndEnglishCatalogValues() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Haiity/Localizable.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["Do not disturb"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let english = try XCTUnwrap(localizations["en"] as? [String: Any])
        let german = try XCTUnwrap(localizations["de"] as? [String: Any])
        XCTAssertEqual((english["stringUnit"] as? [String: Any])?["value"] as? String,
                       "Do not disturb")
        XCTAssertEqual((german["stringUnit"] as? [String: Any])?["value"] as? String,
                       "Nicht stören")
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative))
    }
}
