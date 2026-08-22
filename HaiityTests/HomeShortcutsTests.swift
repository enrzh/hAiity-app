import XCTest
@testable import Haiity

/// Schnellaktionen des Homescreens — die Rechnung dahinter: Kandidaten-
/// wahl, Menüaufbau und Typ-Auflösung sind pure Logik ohne UIKit-Laufzeit.
final class HomeShortcutsTests: XCTestCase {
    private let day = "2026-08-22"

    private func habit(_ name: String,
                       kind: HabitKind = .checkbox,
                       archivedAt: String? = nil) -> Habit {
        var habit = Habit(name: name)
        habit.kind = kind
        habit.archivedAt = archivedAt
        return habit
    }

    // MARK: – Aufbau

    func testMenuWithoutOpenHabitCarriesTheThreeDestinations() {
        let descriptors = HomeShortcuts.descriptors(habits: [], day: day)

        XCTAssertEqual(descriptors.count, 3)
        XCTAssertEqual(descriptors.map(\.title),
                       ["Neues Habit", "Statistik", "Archiv"])
        XCTAssertTrue(descriptors.allSatisfy { $0.checkHabitID == nil })
    }

    func testOpenHabitLeadsTheMenuWithItsName() {
        let reading = habit("Lesen")
        let sport = habit("Sport")

        let descriptors = HomeShortcuts.descriptors(habits: [reading, sport], day: day)

        XCTAssertEqual(descriptors.first?.checkHabitID, reading.id)
        XCTAssertEqual(descriptors.first?.title, "Lesen")
        XCTAssertEqual(descriptors.count, 4)
    }

    func testDoneArchivedAndDeclinedHabitsAreNotOffered() {
        var done = habit("Lesen")
        done.log[day] = 1
        let archived = habit("Alt", archivedAt: day)
        // Mit NEIN beantwortet: für applyQuickAction erledigt — die
        // Schnellaktion darf ihn nicht versprechen.
        var declined = habit("Kaffee", kind: .yesNo)
        declined.log[day] = Habit.Answer.no
        let open = habit("Sport")

        let candidate = HomeShortcuts.checkOffCandidate([done, archived, declined, open],
                                                        day: day)

        XCTAssertEqual(candidate?.id, open.id)
    }

    func testYesNoWithoutAnswerIsOffered() {
        let yesNo = habit("Glück", kind: .yesNo)

        XCTAssertEqual(HomeShortcuts.checkOffCandidate([yesNo], day: day)?.id, yesNo.id)
    }

    func testRemindersAreNeverOfferedAsCheckOffs() {
        let reminder = Habit(name: "Zähne",
                             itemType: .reminder,
                             reminderMinutes: 8 * 60)

        XCTAssertNil(HomeShortcuts.checkOffCandidate([reminder], day: day))
    }

    func testMenuNeverGrowsPastFourEntries() {
        let habits = (1...6).map { habit("Habit \($0)") }

        XCTAssertEqual(HomeShortcuts.descriptors(habits: habits, day: day).count, 4)
    }

    // MARK: – Typ-Auflösung

    func testLinkTypesRoundTripThroughTheirDestinations() {
        for destination in [AppDestination.habits, .more, .stats, .archive, .search, .create] {
            let host = destination.url.host!
            let type = "haiity.link.\(host)"

            XCTAssertEqual(HomeShortcuts.linkURL(forType: type), destination.url,
                           "type \(type) muss auf \(destination) zurückführen")
        }
    }

    func testCheckTypeCarriesItsHabitID() {
        let id = UUID()

        XCTAssertEqual(HomeShortcuts.checkHabitID(forType: "haiity.check.\(id.uuidString)"), id)
        XCTAssertNil(HomeShortcuts.linkURL(forType: "haiity.check.\(id.uuidString)"))
    }

    func testForeignAndBrokenTypesResolveToNil() {
        XCTAssertNil(HomeShortcuts.linkURL(forType: "com.other.app.action"))
        XCTAssertNil(HomeShortcuts.linkURL(forType: "haiity.link.unknown"))
        XCTAssertNil(HomeShortcuts.linkURL(forType: "haiity.link."))
        XCTAssertNil(HomeShortcuts.checkHabitID(forType: "haiity.check.not-a-uuid"))
        XCTAssertNil(HomeShortcuts.checkHabitID(forType: "haiity.link.new"))
    }
}
