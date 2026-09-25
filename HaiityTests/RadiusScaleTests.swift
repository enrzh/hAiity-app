import XCTest
@testable import Haiity

/// Keeps the corner radii a scale instead of a habit.
///
/// The view layer had 44 call sites carrying **thirteen** different numbers as
/// literals. Two surfaces the same size with 9 and 10 next to each other read as
/// an accident, and with thirteen values the radius is the first thing you notice
/// when screens sit side by side. This test is what makes the scale stick: a new
/// number cannot be typed in without either using a named step or adding one here
/// on purpose, which is a decision rather than an accident.
final class RadiusScaleTests: XCTestCase {

    /// Every radius in a view has to name its step or be computed from one. No
    /// free-floating numbers.
    func testNoViewInventsACornerRadius() throws {
        let files = try Self.viewSources()
        var offenders: [String] = []
        for path in files {
            let source = try String(contentsOf: path, encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("RoundedRectangle(cornerRadius:") {
                // The rule is "no literal", not "must be a named step". A radius
                // computed from something — a cell size, a corner variable — is
                // exactly what should be allowed, and an allowlist of prefixes
                // would have had to be maintained forever to say so.
                let after = line.components(separatedBy: "RoundedRectangle(cornerRadius:").last ?? ""
                let value = after.trimmingCharacters(in: .whitespaces)
                if value.first?.isNumber == true || value.hasPrefix(".") {
                    offenders.append("\(path.lastPathComponent):\(index + 1)  \(value.prefix(40))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "corner radii must come from CornerRadius:\n" + offenders.joined(separator: "\n"))
    }

    /// The scale has to stay small. A "scale" with a step per screen is the same
    /// as no scale, so the count is part of the contract.
    func testTheScaleStaysSmall() {
        XCTAssertEqual(CornerRadius.scale.count, 7,
                       "a radius scale is a handful of named steps, not one per screen")
        XCTAssertEqual(Set(CornerRadius.scale).count, CornerRadius.scale.count,
                       "two steps with the same value is one step with two names")
        // Ascending, so the list can be reasoned about rather than just read.
        XCTAssertEqual(CornerRadius.scale, CornerRadius.scale.sorted())
    }

    /// The standard card is one definition. `Theme.Metrics.cardRadius` used to be
    /// its own literal, which is how a second "standard" appears next to the first.
    func testTheCardRadiusHasOneDefinition() {
        XCTAssertEqual(Theme.Metrics.cardRadius, CornerRadius.card)
    }

    /// Rounding strays onto a named step moves corners by a fraction of a point.
    /// That is the point, but it is a real change, so it is pinned: if someone
    /// widens a step, this says how much moved.
    func testTheScaleIsWhereTheOldValuesLanded() {
        // 6 and 7 were grid cells and a small chip; they now share the chip step.
        XCTAssertEqual(CornerRadius.chip, 8)
        // 9 was used seven times, almost always for an icon chip.
        XCTAssertLessThanOrEqual(abs(CornerRadius.chip - 9), 1)
        // 11 was a control-sized control.
        XCTAssertLessThanOrEqual(abs(CornerRadius.control - 11), 1)
        // 18 and 20 were the two largest surfaces and now agree.
        XCTAssertEqual(CornerRadius.hero, 20)
    }

    private static func viewSources() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let views = root.appendingPathComponent("Haiity/Views")
        let models = root.appendingPathComponent("Haiity/Models")
        return (try FileManager.default.contentsOfDirectory(at: views,
                                                            includingPropertiesForKeys: nil)
                + FileManager.default.contentsOfDirectory(at: models,
                                                         includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}
