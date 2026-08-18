import XCTest
@testable import Haiity

final class GitHubPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GitHubPreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUsernameVisibilityDefaultsToEnabled() {
        XCTAssertTrue(GitHubPreferences.showsUsername(in: defaults))
    }

    func testUsernameVisibilityRoundTripsThroughTheSuppliedDefaults() {
        GitHubPreferences.setShowsUsername(false, in: defaults)
        XCTAssertFalse(GitHubPreferences.showsUsername(in: defaults))

        GitHubPreferences.setShowsUsername(true, in: defaults)
        XCTAssertTrue(GitHubPreferences.showsUsername(in: defaults))
    }
}
