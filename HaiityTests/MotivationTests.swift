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

    /// A generated line replaces the body and nothing else. The greeting stays
    /// with the catalog, because it is translated and has to place the name
    /// per language — a job the model must not redo.
    func testGeneratedLineReplacesOnlyTheBody() {
        let pool = Motivation.message(name: "Ada", today: "2026-08-14")
        let generated = Motivation.message(name: "Ada", today: "2026-08-14",
                                           generatedLine: "Heute zählt die nächste Zelle.")
        XCTAssertEqual(generated.title, pool.title)
        XCTAssertEqual(generated.body, "Heute zählt die nächste Zelle.")
    }

    /// A blank or absent generated line must leave the built-in pool serving,
    /// so a failed write can never produce an empty notification.
    func testMissingOrBlankGeneratedLineFallsBackToThePool() {
        let pool = Motivation.message(name: nil, today: "2026-08-14")
        XCTAssertEqual(Motivation.message(name: nil, today: "2026-08-14",
                                          generatedLine: nil).body, pool.body)
        for blank in ["", "   ", "\n"] {
            XCTAssertEqual(Motivation.message(name: nil, today: "2026-08-14",
                                              generatedLine: blank).body, pool.body,
                           "a blank generated line must not reach the notification")
        }
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
        let more = try source("Haiity/Views/MoreNotifications.swift")
        let host = try source("Haiity/Views/MoreView.swift")
        XCTAssertTrue(more.contains("motivationRows"))
        XCTAssertTrue(more.contains("store.motivationMinutes"))
        XCTAssertTrue(more.contains("\"motivation-toggle\""))
        XCTAssertTrue(more.contains("\"motivation-time\""))
        XCTAssertTrue(more.contains("\"motivation-delivery\""))
        XCTAssertTrue(more.contains("Live-Aktivitäten starten"))
        XCTAssertTrue(more.contains("Reminders.ensurePermission()"))
        XCTAssertTrue(more.contains("motivation-source-picker"))
        XCTAssertTrue(more.contains("Reminders.reschedule(store: store)"))
        XCTAssertTrue(more.contains("MotivationActivityManager.shared.reconcile"))
        let manager = try source("Haiity/Services/MotivationActivityManager.swift")
        XCTAssertTrue(manager.contains("source: Motivation.Source = .builtIn"))
        XCTAssertTrue(manager.contains("Motivation.message(name: name, today: dayKey,"))
        let content = try source("Haiity/Views/ContentView.swift")
        XCTAssertTrue(content.contains("source: store.motivationSource"))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.title"))
        XCTAssertTrue(more.contains("NotificationDNDPresentation.symbolName"))
        XCTAssertFalse(more.contains("DND (Do not disturb)"))
        let developer = try source("Haiity/Views/DeveloperView.swift")
        XCTAssertTrue(developer.contains("copy-sync-watermark"))
        XCTAssertFalse(more.contains("ForEach(SyncWatermark.Kind.allCases"))
        XCTAssertTrue(more.contains("notification-actions-toggle"))
        let appearStart = try XCTUnwrap(host.range(of: ".onAppear {"))
        let taskStart = try XCTUnwrap(host.range(of: ".task {",
                                               range: appearStart.upperBound..<host.endIndex))
        let taskEnd = try XCTUnwrap(host.range(of: ".sheet(item: $editingPalette)",
                                             range: taskStart.upperBound..<host.endIndex))
        let appearance = host[appearStart.lowerBound..<taskStart.lowerBound]
        XCTAssertTrue(appearance.contains("store.cloudPreferences?.notificationDND"))
        XCTAssertTrue(appearance.contains("NotificationPromptPreference.state"))
        XCTAssertTrue(appearance.contains("dndCustomDate = until"))
        let timer = host[taskStart.lowerBound..<taskEnd.lowerBound]
        XCTAssertTrue(timer.contains("dndNow = .now"))
        XCTAssertTrue(timer.contains("Task.sleep(for: .seconds(60))"))
    }

    func testMoreNotificationSettingsUseAUnifiedAppleStyleHierarchy() throws {
        let more = try source("Haiity/Views/MoreNotifications.swift")

        XCTAssertTrue(more.contains(".font(.footnote.weight(.semibold))"))
        XCTAssertTrue(more.contains("notificationSymbolSurface"))
        XCTAssertTrue(more.contains("notificationDetailsInset"))
        let glyphStart = try XCTUnwrap(more.range(of: "func notificationSymbolSurface("))
        let labelStart = try XCTUnwrap(more.range(of: "func notificationLabel(",
                                                range: glyphStart.upperBound..<more.endIndex))
        let labelEnd = try XCTUnwrap(more.range(of: "var motivationSourceControl:",
                                              range: labelStart.upperBound..<more.endIndex))
        let glyph = more[glyphStart.lowerBound..<labelStart.lowerBound]
        XCTAssertTrue(glyph.contains(".font(.system(size: 15, weight: .bold))"))
        XCTAssertTrue(glyph.contains("width: Theme.Metrics.glyph"))
        XCTAssertTrue(glyph.contains("height: Theme.Metrics.glyph"))
        XCTAssertFalse(glyph.contains("AppIconBadge("),
                       "notification glyphs must keep their fixed-size surface at AX5")
        let label = more[labelStart.lowerBound..<labelEnd.lowerBound]
        XCTAssertTrue(label.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertFalse(label.contains(".lineLimit("))
        XCTAssertFalse(label.contains(".minimumScaleFactor("))
    }

    /// The retired open-source feed must leave no trace: no URL, no cache, no
    /// fetch, no licence line. This is the regression guard for the decision to
    /// replace a third-party quote repository with the on-device model, and it
    /// fails loudly if any of that wiring is ever reintroduced.
    func testTheRetiredOpenSourceFeedIsFullyGone() throws {
        for path in ["Haiity/Views/MoreView.swift",
                     "Haiity/Views/MoreNotifications.swift",
                     "Haiity/Views/ContentView.swift",
                     "Haiity/Services/Reminders.swift",
                     "Haiity/Services/MotivationActivityManager.swift",
                     "Haiity/Models/HabitStore.swift"] {
            let text = try source(path)
            for retired in ["mubaris", "MotivationFeed", "openSourceMotivationEnabled",
                            "additionalEntries", "MIT-Lizenz"] {
                XCTAssertFalse(text.contains(retired),
                               "\(path) still references the retired feed: \(retired)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Haiity/Models/MotivationFeed.swift").path),
                       "the retired feed file must not come back")
    }

    /// Running the model makes the device warm, so the model may only be reached
    /// from a deliberate tap. The scheduler and the Live Activity both run
    /// without anyone touching anything — a launch, a settings change, a
    /// background reconcile — and both used to be able to write. This is the
    /// regression guard for making that impossible again.
    func testOnlyTheTapCanReachTheModel() throws {
        // The background callers are the real hazard: a launch, a settings
        // change, or a reconcile reaches them with nobody touching anything.
        // A pure cache read is all they may do.
        for path in ["Haiity/Services/Reminders.swift",
                     "Haiity/Services/MotivationActivityManager.swift"] {
            let text = try source(path)
            for writer in ["onDeviceWriter", "writeLine", "rerollLine",
                           "StatsReadingWriter", "MotivationWriter"] {
                XCTAssertFalse(text.contains(writer),
                               "\(path) reaches the model (\(writer)) on a path nobody tapped")
            }
        }

        // On the statistics page the writer may be named, but only as the
        // argument of the one function a tap enters. Every call site has to go
        // through that button wrapper.
        let stats = try source("Haiity/Views/StatsView.swift")
        XCTAssertTrue(stats.contains("stats-reading-action"))
        XCTAssertTrue(stats.contains("StatsReadingDaily.write"))
        let load = try XCTUnwrap(stats.range(of: ".task(id: statsRefreshKey)"))
        let toolbar = try XCTUnwrap(stats.range(of: ".toolbar", range: load.upperBound..<stats.endIndex))
        let lifecycle = stats[load.lowerBound..<toolbar.lowerBound]
        XCTAssertFalse(lifecycle.contains("requestStatsReading("),
                       "page loading must never request generation")
        XCTAssertFalse(lifecycle.contains("StatsReadingDaily.write"))

        // And the settings screen's tap is the only writer there too.
        let more = try source("Haiity/Views/MoreNotifications.swift")
        XCTAssertTrue(more.contains("motivation-write"))
        XCTAssertTrue(more.contains("writeMotivationLine(reroll:"))
    }

    /// The reading block is the affordance, so it cannot be conditional. An
    /// invitation that only appears once it already has a result stays
    /// undiscovered.
    func testTheStatsReadingBlockIsAlwaysRendered() throws {
        let stats = try source("Haiity/Views/StatsView.swift")
        XCTAssertTrue(stats.contains("private var statsReadingCard: some View"))
        // The states live with the feature; the view has to handle every one of
        // them, so an exhaustive switch is what proves there is no dead branch.
        let phase = try source("Haiity/Services/StatsReadingWriter.swift")
        for state in ["case idle", "case working", "case shown(String)",
                      "case unavailable(OnDeviceModelAvailability)", "case failed"] {
            XCTAssertTrue(phase.contains(state), "the phase is missing \(state)")
        }
        for handled in ["case .idle", "case .working", "case .shown",
                        "case .unavailable", "case .failed"] {
            XCTAssertTrue(stats.contains(handled),
                          "the block does not render \(handled)")
        }
        // Placed in the page stack with no `if` around it.
        let stackLines = stats.split(separator: "\n", omittingEmptySubsequences: false)
        guard let index = stackLines.firstIndex(where: { $0.contains("statsReadingCard") && !$0.contains("private var") })
        else {
            return XCTFail("the block is not in the page stack at all")
        }
        XCTAssertFalse(stackLines[index].trimmingCharacters(in: .whitespaces)
            .hasPrefix("if "),
                       "the block must be in the stack without a surrounding condition")
    }

    /// The source control must be honest about why the model is unavailable
    /// rather than offering a choice that silently does nothing.
    func testTheOnDeviceSourceIsOnlyOfferedWhenItCanRun() throws {
        let more = try source("Haiity/Views/MoreNotifications.swift")
        XCTAssertTrue(more.contains("Motivation.Source.allCases.filter"))
        XCTAssertTrue(more.contains("$0 == .builtIn || OnDeviceModel.isAvailable"))
        for reason in ["appleIntelligenceOff", "modelNotReady",
                       "deviceNotEligible", "unsupportedSystem"] {
            XCTAssertTrue(more.contains(reason),
                          "the caption must explain \(reason) instead of hiding it")
        }
    }

    func testMotivationLinesStayShortEnoughForNotifications() {
        XCTAssertTrue(Motivation.lines.allSatisfy { $0.count <= 84 })
    }

    func testMotivationSourceDefaultsToTheBuiltInPoolForLegacyJSON() throws {
        let raw = try XCTUnwrap("{\"version\":2,\"updatedAt\":1,\"habits\":[]}".data(using: .utf8))
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.motivationSource, .builtIn)
    }

    /// A stored `openSourceMotivationEnabled: true` named a source that no
    /// longer exists. It must not be read as a choice between the two surviving
    /// sources, and it must not fail the decode of the whole file.
    func testLegacyOpenSourceFlagBecomesBuiltInRatherThanTheModel() throws {
        let raw = try XCTUnwrap("""
        {"version":2,"updatedAt":1,"habits":[],"openSourceMotivationEnabled":true}
        """.data(using: .utf8))
        let data = try JSONDecoder().decode(HabitData.self, from: raw)
        XCTAssertEqual(data.motivationSource, .builtIn)
    }

    func testUnknownMotivationSourceFallsBackInsteadOfFailingDecode() throws {
        let raw = try XCTUnwrap("""
        {"version":2,"updatedAt":1,"habits":[],"motivationSource":"somethingNewer"}
        """.data(using: .utf8))
        XCTAssertNoThrow(try JSONDecoder().decode(HabitData.self, from: raw))
    }

    func testMotivationSourcePersistsWhenChanged() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("motivation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HabitStore(url: url, loadFromDisk: false)
        store.motivationSource = .onDevice

        XCTAssertEqual(HabitStore(url: url).motivationSource, .onDevice)
    }

    func testNewerRemoteMotivationSourceWins() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("motivation-merge-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        store.motivationSource = .builtIn
        let remote = HabitData(version: HabitData.currentVersion,
                               updatedAt: store.data.updatedAt + 1,
                               summaryMinutes: nil,
                               habits: [],
                               motivationSource: .onDevice)

        store.merge(remote: remote)

        XCTAssertEqual(store.motivationSource, .onDevice)
    }

    func testNewerRemoteHabitMergePreservesAllNotificationModes() {
        for mode in HabitNotificationMode.allCases {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("notification-merge-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: url) }
            let localHabit = Habit(name: "Local", notificationMode: .off)
            var remoteHabit = localHabit
            remoteHabit.notificationMode = mode
            let store = HabitStore(url: url, loadFromDisk: false)
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
