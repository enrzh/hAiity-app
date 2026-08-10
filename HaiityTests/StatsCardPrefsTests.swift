import XCTest
@testable import Haiity

/// Auswahl der Statistik-Karten: Standard, Obergrenze zwei, tolerantes
/// Codable und die Ablage in UserDefaults — plus der Such-Zug (SearchPull),
/// der aus Fingerweg und Zeilenbewegung entscheidet.
final class StatsCardPrefsTests: XCTestCase {

    // MARK: – Grundzustand und Obergrenze

    func testDefaultIsYearPulseOnly() {
        XCTAssertEqual(StatsCardPrefs().active, [.yearPulse])
    }

    func testSetActivatesAndDeactivatesInOrder() {
        var prefs = StatsCardPrefs(active: [])
        prefs.set(.streakFlame, active: true)
        prefs.set(.todayRing, active: true)
        XCTAssertEqual(prefs.active, [.streakFlame, .todayRing])
        prefs.set(.streakFlame, active: false)
        XCTAssertEqual(prefs.active, [.todayRing])
    }

    func testMaxTwoIsEnforcedBySet() {
        var prefs = StatsCardPrefs(active: [.yearPulse, .streakFlame])
        XCTAssertTrue(prefs.isFull)
        prefs.set(.todayRing, active: true)   // No-op: voll
        XCTAssertEqual(prefs.active, [.yearPulse, .streakFlame])
    }

    func testCanToggleLocksOnlyInactiveCardsWhenFull() {
        let full = StatsCardPrefs(active: [.yearPulse, .streakFlame])
        XCTAssertTrue(full.canToggle(.yearPulse))      // aktive dürfen immer aus
        XCTAssertFalse(full.canToggle(.todayRing))     // neue sind gesperrt
        let free = StatsCardPrefs(active: [.yearPulse])
        XCTAssertTrue(free.canToggle(.todayRing))
    }

    func testInitSanitizesDuplicatesAndOverflow() {
        let prefs = StatsCardPrefs(active: [.todayRing, .todayRing, .yearPulse, .weekMomentum])
        XCTAssertEqual(prefs.active, [.todayRing, .yearPulse])
    }

    func testSetSameCardTwiceDoesNotDuplicate() {
        var prefs = StatsCardPrefs(active: [.yearPulse])
        prefs.set(.yearPulse, active: true)
        XCTAssertEqual(prefs.active, [.yearPulse])
    }

    // MARK: – Codable

    func testCodableRoundTripPreservesEmptySelection() throws {
        let empty = StatsCardPrefs(active: [])
        let raw = try JSONEncoder().encode(empty)
        let back = try JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        // „Alle aus" ist eine Entscheidung — sie darf beim Lesen nicht zum
        // Standard (Jahres-Puls) zurückspringen.
        XCTAssertEqual(back.active, [])
    }

    func testDecodeDropsUnknownCardNames() throws {
        let raw = Data(#"{"active":["yearPulse","hologram","streakFlame","todayRing"]}"#.utf8)
        let prefs = try JSONDecoder().decode(StatsCardPrefs.self, from: raw)
        XCTAssertEqual(prefs.active, [.yearPulse, .streakFlame])   // max 2, Unbekanntes weg
    }

    // MARK: – Ablage

    private func scratchDefaults() -> (UserDefaults, () -> Void) {
        let suite = "stats-prefs-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    func testLoadWithoutStoredValueIsDefault() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.yearPulse])
    }

    func testSaveThenLoadRoundTrips() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        var prefs = StatsCardPrefs(active: [])
        prefs.set(.weekMomentum, active: true)
        prefs.save(to: defaults)
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.weekMomentum])
    }

    func testLoadWithCorruptDataFallsBackToDefault() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        defaults.set(Data("kaputt".utf8), forKey: StatsCardPrefs.storageKey)
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.yearPulse])
    }

    func testStoreWritesEveryChange() {
        let (defaults, cleanup) = scratchDefaults()
        defer { cleanup() }
        let store = StatsCardStore(defaults: defaults)
        store.prefs.set(.streakFlame, active: true)
        XCTAssertEqual(StatsCardPrefs.load(from: defaults).active, [.yearPulse, .streakFlame])
        let reloaded = StatsCardStore(defaults: defaults)
        XCTAssertEqual(reloaded.prefs.active, [.yearPulse, .streakFlame])
    }
}

/// Der Such-Zug: „runterziehen öffnet die Suche" — entschieden aus dem
/// Fingerweg der Geste und der echten Zeilenbewegung.
final class SearchPullTests: XCTestCase {

    private func pull(first: CGFloat?) -> SearchPull {
        var p = SearchPull()
        p.latestFirst = first
        return p
    }

    func testRubberBandPullAtTopFiresOnce() {
        var p = pull(first: 0)
        // Finger 40 pt, Zeilen 20 pt (Gummiband ~0,5): noch unter der Schwelle.
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 40), first: 20))
        // Finger 100 pt, Zeilen 48 pt: Schwelle überschritten, Verhältnis < 0,6.
        XCTAssertTrue(p.update(translation: CGSize(width: 2, height: 100), first: 48))
        // Verriegelt bis zum Loslassen.
        XCTAssertFalse(p.update(translation: CGSize(width: 2, height: 140), first: 60))
    }

    func testOneToOneScrollingNeverFires() {
        var p = pull(first: 0)
        // Zeilen folgen dem Finger 1:1 — das ist Scrollen, kein Zug.
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 100), first: 100))
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 200), first: 198))
    }

    func testMidListGestureWithoutVisibleAnchorNeverFires() {
        // Mitten in der Liste ist die Titelzeile abgeräumt: kein Anker.
        var p = pull(first: nil)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 300)))
    }

    func testHorizontalDragDoesNotFire() {
        var p = pull(first: 0)
        XCTAssertFalse(p.update(translation: CGSize(width: 90, height: 100), first: 50))
    }

    func testEndedRearmsForTheNextGesture() {
        var p = pull(first: 0)
        XCTAssertTrue(p.update(translation: CGSize(width: 0, height: 100), first: 48))
        p.ended()
        p.latestFirst = 0
        XCTAssertTrue(p.update(translation: CGSize(width: 0, height: 100), first: 48))
    }

    func testPinnedContentDoesNotFire() {
        // Die Zeilen bewegen sich gar nicht (eine andere Geste gewann):
        // kein Gummiband, kein Zug.
        var p = pull(first: 0)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: 120), first: 0))
    }

    func testUpwardDragDoesNotFire() {
        var p = pull(first: 0)
        XCTAssertFalse(p.update(translation: CGSize(width: 0, height: -120), first: -60))
    }
}
