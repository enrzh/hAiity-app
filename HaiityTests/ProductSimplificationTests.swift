import XCTest
@testable import Haiity

@MainActor
final class ProductSimplificationTests: XCTestCase {
    func testRoutesWaitForSentenceDismissalIndependentlyOfHabitEditor() {
        var work = RouteWork()
        for destination in [AppDestination.create, .stats, .search] {
            let route = work.begin(destination.effect)
            for phase in [RoutePresentationPhase.requested, .presented] {
                XCTAssertEqual(work.nextStep(for: route, presentation: .init(sentenceCreation: phase)),
                               .dismissSentenceCreation)
            }
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(sentenceCreation: .dismissing)),
                           .waitForSentenceCreationDismissal)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init(editor: .presented)),
                           .dismissEditor)
            XCTAssertEqual(work.nextStep(for: route, presentation: .init()), .apply)
        }
    }

    func testSupersededSentenceDismissalCannotApplyAnOlderRoute() {
        var work = RouteWork()
        let old = work.begin(AppDestination.create.effect)
        let current = work.begin(AppDestination.stats.effect)
        XCTAssertNil(work.nextStep(for: old, presentation: .init()))
        XCTAssertEqual(work.nextStep(for: current, presentation: .init(sentenceCreation: .dismissing)),
                       .waitForSentenceCreationDismissal)
        XCTAssertEqual(work.nextStep(for: current, presentation: .init()), .apply)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("product-\(UUID()).json")
    }

    func testUnchosenFreshAppearanceYieldsToLateLegacyCloudAfterAHabitSave() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        let habit = Habit(name: "Read")
        store.add(habit)
        let savedHabits = store.habits
        var remote = HabitData.empty
        remote.updatedAt = 123
        remote.appearancePreferences = AppearancePreferences(material: .milky, designStyle: .studio)
        store.merge(remote: remote)
        XCTAssertEqual(store.appearancePreferences, remote.appearancePreferences)
        XCTAssertEqual(store.habits, savedHabits)
    }

    func testExplicitLocalChoiceSurvivesLateLegacyCloud() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        store.appearancePreferences = AppearancePreferences(designStyle: .focus)
        var remote = HabitData.empty
        remote.updatedAt = Date().timeIntervalSince1970 + 1000
        store.merge(remote: remote)
        XCTAssertEqual(store.appearancePreferences.designStyle, .focus)
    }

    func testRemoteFreshDefaultCannotReplaceExistingLegacyAppearance() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var local = HabitData.empty
        local.updatedAt = 10
        local.appearance = .dark
        local.appearancePreferences = AppearancePreferences(material: .milky, designStyle: .native)
        try JSONEncoder().encode(local).write(to: url)
        let store = HabitStore(url: url)
        var remote = HabitData.fresh
        remote.updatedAt = 20
        store.merge(remote: remote)
        XCTAssertEqual(store.appearancePreferences, local.appearancePreferences)
        XCTAssertEqual(store.appearance, .dark)
    }

    func testFreshMarkerSurvivesPersistenceAndDefaultsDoNotOverrideEachOther() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        store.add(Habit(name: "Read"))
        let decoded = try JSONDecoder().decode(HabitData.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.appearanceUpdatedAt, 0)
        let reloaded = HabitStore(url: url)
        var remote = HabitData.fresh
        remote.updatedAt = Date().timeIntervalSince1970 + 1000
        remote.appearancePreferences.designStyle = .studio
        reloaded.merge(remote: remote)
        XCTAssertEqual(reloaded.appearancePreferences.designStyle, .quiet)
    }

    func testFreshStoresStartQuietAndPersistThatChoice() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HabitStore(url: url, loadFromDisk: false)
        await store.loadFromDisk()
        XCTAssertEqual(store.appearancePreferences.designStyle, .quiet)
        store.add(Habit(name: "Read"))
        let reloaded = HabitStore(url: url)
        XCTAssertEqual(reloaded.appearancePreferences.designStyle, .quiet)
        XCTAssertEqual(reloaded.habits, store.habits)
        XCTAssertEqual(HabitStore(url: temporaryURL()).appearancePreferences.designStyle, .quiet)
    }

    func testDeferredLoadKeepsEveryExistingStyleAndCustomization() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        for style in AppDesignStyle.allCases {
            var original = HabitData.empty
            original.habits = [Habit(name: "Read")]
            original.appearancePreferences = AppearancePreferences(
                material: .milky, backgroundMode: .gradient,
                gradientStartHex: 0x102030, gradientEndHex: 0x708090,
                backgroundImageFocusX: 0.2, backgroundImageFocusY: 0.8,
                backgroundImageZoom: 2, performanceMode: true, designStyle: style)
            try JSONEncoder().encode(original).write(to: url)
            let store = HabitStore(url: url, loadFromDisk: false)
            await store.loadFromDisk()
            XCTAssertEqual(store.appearancePreferences, original.appearancePreferences)
            XCTAssertEqual(store.habits, original.habits)
        }
    }

    func testLegacyPayloadAndUnknownStyleKeepNativeFallback() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let encoded = try JSONEncoder().encode(HabitData.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "appearancePreferences")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertEqual(HabitStore(url: url).appearancePreferences.designStyle, .native)
        var preferences = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AppearancePreferences.default)) as? [String: Any])
        preferences["designStyle"] = "future-style"
        let decoded = try JSONDecoder().decode(AppearancePreferences.self,
            from: JSONSerialization.data(withJSONObject: preferences))
        XCTAssertEqual(decoded.designStyle, .native)
        XCTAssertEqual(AppearancePreferences.default.designStyle, .native)
    }

    func testCorruptPayloadKeepsItsRecoveryCopyAndLegacyAppearanceFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("product-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("habits.json")
        let bytes = Data("broken existing data".utf8)
        try bytes.write(to: url)
        let store = HabitStore(url: url)
        XCTAssertEqual(store.appearancePreferences.designStyle, .native)
        XCTAssertTrue(store.readFailed)
        XCTAssertTrue(store.persist())
        XCTAssertEqual(HabitStore(url: url).appearancePreferences.designStyle, .native)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("haiity.corrupt.json")), bytes)
    }
}
