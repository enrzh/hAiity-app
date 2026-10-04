import SwiftUI
import WidgetKit
import UIKit
import XCTest
@testable import Haiity

@MainActor
final class WidgetRenderingTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func entry(count: Int = 4, longNames: Bool = false, reset: Bool = true) -> HaiityEntry {
        let today = DayKey.key(for: now, calendar: calendar)
        let names = longNames
            ? ["Read and reflect on a chapter before breakfast", "Drink enough water during a busy working day",
               "Avoid drinking coffee after the afternoon", "Call the dentist about the next appointment"]
            : ["Read", "Water", "No late coffee", "Dentist"]
        var items = names.enumerated().map { index, name in
            Habit(name: name, itemType: index == 3 ? .reminder : .habit,
                  recurrence: Recurrence(target: index == 1 ? 3 : nil),
                  kind: index == 1 ? .quantity : index == 2 ? .yesNo : .checkbox)
        }
        for index in items.indices {
            items[index].createdAt = "2026-05-01"
            items[index].timeZoneIdentifier = "UTC"
            items[index].notificationMode = .off
            for offset in 0..<150 where (offset + index) % 4 != 0 {
                let day = DayKey.shifted(today, by: -offset, calendar: calendar)!
                items[index].log[day] = index == 1 ? offset % 4 + 1 : 1
            }
        }
        items[0].log[today] = 1
        items[1].log[today] = 1
        items[2].log[today] = Habit.Answer.no
        items[3].log[today] = nil
        items = Array(items.prefix(count))
        return HaiityEntry(date: now, habits: items, defaultTimeZoneIdentifier: "UTC",
                           selected: items.first?.id, widgetResetEnabled: reset, largeItems: items)
    }

    private func compositions(_ entry: HaiityEntry) -> [(String, AnyView)] {
        [("dual", AnyView(LargeDualWidgetView(entry: entry))),
         ("list", AnyView(LargeListWidgetView(entry: entry))),
         ("grid", AnyView(LargeGridWidgetView(entry: entry))),
         ("focus", AnyView(LargeFocusWidgetView(entry: entry)))]
    }

    func testAllConfiguredLayoutsStayInsideRealCanvasSizes() throws {
        for size in [CGSize(width: 292, height: 311), CGSize(width: 332, height: 350),
                     CGSize(width: 364, height: 382)] {
            for (name, view) in compositions(entry(longNames: true)) {
                for textSize in [DynamicTypeSize.large, .accessibility5] {
                    let content = view.environment(\.dynamicTypeSize, textSize)
                    try assertFits(content, size: size,
                                   name: "bounds-\(name)-\(Int(size.width))-\(textSize)")
                }
            }
        }
    }

    func testSparseAndEmptyLayoutsRenderWithoutInventingItems() throws {
        for count in 0...4 {
            for (name, view) in compositions(entry(count: count)) {
                let image = try render(view.background(Color.white).frame(width: 332, height: 350),
                                       name: "sparse-\(name)-\(count)")
                XCTAssertGreaterThan(ink(image), 20, "\(name) / \(count)")
            }
        }
    }

    func testSmallAndMediumWidgetsFitAllItemKindsAndResetStates() throws {
        for reset in [false, true] {
            let fixture = entry(longNames: true, reset: reset)
            for habit in fixture.habits {
                let selected = HaiityEntry(date: fixture.date, habits: [habit],
                                           defaultTimeZoneIdentifier: "UTC", palettes: fixture.palettes,
                                           selected: habit.id, widgetResetEnabled: reset)
                for (family, size) in [(WidgetFamily.systemSmall, CGSize(width: 138, height: 138)),
                                       (.systemMedium, CGSize(width: 332, height: 138))] {
                    for textSize in [DynamicTypeSize.large, .accessibility5] {
                        try assertFits(HaiityWidgetView(entry: selected).content(family: family, dark: false)
                            .environment(\.dynamicTypeSize, textSize),
                            size: size, name: "main-\(habit.kind)-\(habit.itemType)-\(family)-\(reset)-\(textSize)")
                    }
                }
            }
        }
    }

    func testEveryStyleAndRenderingModeProducesReadableCompositions() throws {
        for style in AppDesignStyle.allCases {
            var fixture = entry()
            fixture.designStyle = style
            for dark in [false, true] {
                for (name, view) in compositions(fixture) {
                    let image = try render(view.environment(\.colorScheme, dark ? .dark : .light)
                        .background(dark ? Color.black : .white).frame(width: 332, height: 350),
                        name: "\(style.rawValue)-\(name)-\(dark ? "dark" : "light")")
                    XCTAssertGreaterThan(ink(image, dark: dark), 100)
                }
            }
        }
        for (modeName, mode) in [("accented", WidgetRenderingMode.accented), ("vibrant", .vibrant)] {
            for (name, view) in compositions(entry()) {
                let image = try render(view.environment(\.widgetRenderingMode, mode)
                    .background(Color.black).frame(width: 332, height: 350),
                    name: "\(modeName)-\(name)")
                XCTAssertGreaterThan(ink(image, dark: true), 100)
            }
        }
    }

    func testEachListRowAndGridTileHasVisibleContent() throws {
        for (name, view) in compositions(entry()) where name == "list" || name == "grid" {
            let image = try render(view.background(Color.white).frame(width: 332, height: 350),
                                   name: "regions-\(name)")
            let regions: [CGRect] = name == "grid"
                ? [CGRect(x: 0, y: 0, width: 166, height: 175),
                   CGRect(x: 166, y: 0, width: 166, height: 175),
                   CGRect(x: 0, y: 175, width: 166, height: 175),
                   CGRect(x: 166, y: 175, width: 166, height: 175)]
                : (0..<4).map { CGRect(x: 0, y: 28 + $0 * 80, width: 332, height: 80) }
            for (index, region) in regions.enumerated() {
                XCTAssertGreaterThan(ink(image, region: region), 40, "\(name) region \(index)")
            }
        }
    }

    func testGraphsStayChronologicalInRTLAndFillAllFamilies() throws {
        let fixture = entry()
        for (family, size) in [(WidgetFamily.systemSmall, CGSize(width: 138, height: 138)),
                               (.systemMedium, CGSize(width: 332, height: 138)),
                               (.systemLarge, CGSize(width: 332, height: 350))] {
            let view = GraphWidgetView(entry: fixture).content(family: family, dark: false)
                .background(Color.white).frame(width: size.width, height: size.height)
            let ltr = try render(view.environment(\.layoutDirection, .leftToRight),
                                 name: "graph-\(family)-ltr")
            let rtl = try render(view.environment(\.layoutDirection, .rightToLeft),
                                 name: "graph-\(family)-rtl")
            XCTAssertEqual(ltr.pngData(), rtl.pngData(), "Only text direction changes, never date chronology")
            XCTAssertGreaterThan(ink(ltr), 100)
        }
    }

    func testGitHubGraphsRenderAllLevelsAndValidEmptyCaches() throws {
        let today = DayKey.key(for: now, calendar: calendar)
        let days = (0..<180).map { offset in
            GitHubContributionDay(date: DayKey.shifted(today, by: -offset, calendar: calendar)!,
                                  count: offset % 5, level: offset % 5)
        }
        for values in [days, []] {
            let fixture = HaiityEntry(date: now, habits: [], graphSource: .github,
                githubSnapshot: GitHubContributionSnapshot(username: "sample", days: values, fetchedAt: now))
            let image = try render(GraphWidgetView(entry: fixture)
                .content(family: .systemMedium, dark: false)
                .background(Color.white).frame(width: 332, height: 138),
                name: values.isEmpty ? "github-empty-cache" : "github")
            XCTAssertGreaterThan(ink(image, cutoff: 250), 100)
            XCTAssertEqual(WidgetLogic.gitHubWidgetContent(snapshot: fixture.githubSnapshot,
                                                           anchor: now),
                           .graph(days: WidgetLogic.gitHubWidgetDays(snapshot: fixture.githubSnapshot, anchor: now)))
        }
    }

    func testAllSixDataLevelsRemainDistinctInEveryAppearance() {
        for mode in [WidgetRenderingMode.fullColor, .accented, .vibrant] {
            for dark in [false, true] {
                var signatures = Set<String>()
                for level in -1...4 {
                    let color = UIColor(HomeWidgetInk.level(level, mode: mode, dark: dark,
                                                            palette: PaletteStyle.default))
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
                    signatures.insert("\(r)-\(g)-\(b)-\(a)")
                }
                XCTAssertEqual(signatures.count, 6)
            }
        }
    }

    func testCustomPalettesAndResetPreferenceSurviveRendering() throws {
        let custom = CustomPalette(name: "Amber", base: 0xD97706)
        var fixture = entry()
        fixture.palettes = PaletteBook(global: .custom(custom.id), customs: [custom])
        let before = fixture.habits
        let image = try render(LargeDualWidgetView(entry: fixture)
            .background(Color.white).frame(width: 332, height: 350), name: "custom-palette")
        XCTAssertGreaterThan(ink(image), 100)
        XCTAssertEqual(fixture.habits, before, "Rendering must never mutate habit data")
        let today = fixture.today(for: fixture.habits[0])
        XCTAssertNotNil(fixture.habits[0].log[today])
        XCTAssertTrue(fixture.showsReset(for: fixture.habits[0]))
        fixture.widgetResetEnabled = false
        XCTAssertFalse(fixture.showsReset(for: fixture.habits[0]))
    }

    func testLockScreenZeroProgressHasNoFakeCompletedArc() throws {
        var habit = Habit(name: "Read")
        habit.createdAt = "2026-05-01"
        habit.timeZoneIdentifier = "UTC"
        let zero = HaiityEntry(date: now, habits: [habit], defaultTimeZoneIdentifier: "UTC")
        habit.log[DayKey.key(for: now, calendar: calendar)] = 1
        let complete = HaiityEntry(date: now, habits: [habit], defaultTimeZoneIdentifier: "UTC")
        let images = try [zero, complete].enumerated().map { index, value in
            try render(RingAccessoryView(entry: value).content(mode: .vibrant)
                .background(Color.black).frame(width: 62, height: 62), name: "ring-\(index)")
        }
        XCTAssertGreaterThan(brightRingPixels(images[1]), brightRingPixels(images[0]) + 100)
    }

    func testAccessoriesRenderReminderAndHabitStatesInAllModes() throws {
        for habit in entry().habits {
            let fixture = HaiityEntry(date: now, habits: [habit], defaultTimeZoneIdentifier: "UTC",
                                      selected: habit.id)
            for (name, mode) in [("full", WidgetRenderingMode.fullColor),
                                  ("accented", .accented), ("vibrant", .vibrant)] {
                let image = try render(StreakAccessoryView(entry: fixture).content(mode: mode, dark: true)
                    .environment(\.colorScheme, .dark)
                    .background(Color.black).frame(width: 160, height: 72),
                    name: "accessory-\(habit.itemType)-\(habit.kind)-\(name)")
                XCTAssertGreaterThan(ink(image, dark: true), 20)
                let inline = try render(InlineAccessoryView(entry: fixture).content(mode: mode)
                    .environment(\.colorScheme, .dark)
                    .background(Color.black).frame(width: 220, height: 28),
                    name: "inline-\(habit.itemType)-\(habit.kind)-\(name)")
                XCTAssertGreaterThan(ink(inline, dark: true), 5)
            }
        }
    }

    func testControlsAndLinksKeepIndependentNativeContracts() throws {
        let shared = try source("HaiityWidget/WidgetComponents.swift")
        for intent in ["CheckOffHabitIntent", "AnswerYesHabitIntent", "AnswerNoHabitIntent", "ResetHabitIntent"] {
            XCTAssertTrue(shared.contains("Button(intent:") && shared.contains(intent))
        }
        XCTAssertTrue(shared.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(shared.contains(".accessibilityLabel("))
        XCTAssertTrue(shared.contains(".accessibilityValue(summary.metricText)"))
        XCTAssertTrue(shared.contains("entry.showsReset(for: habit)"))
        for file in ["HaiityWidgetView", "RosterWidgetView"] {
            let view = try source("HaiityWidget/\(file).swift")
            XCTAssertTrue(view.contains("Link(destination: HaiityWidgetLink.habits)"))
            XCTAssertTrue(view.contains("WidgetItemActions("))
            XCTAssertFalse(view.contains(".widgetURL("), "A parent URL must not intercept intent buttons")
            XCTAssertFalse(view.contains("Link(destination: HaiityWidgetLink.habit("))
        }
    }

    func testReminderAccessoriesUseOccurrenceStateAndAvoidHabitHistory() throws {
        let accessory = try source("HaiityWidget/AccessoryWidgetViews.swift")
        XCTAssertTrue(accessory.contains("now: entry.date"))
        XCTAssertTrue(accessory.contains("if habit.isReminder"))
        XCTAssertTrue(accessory.contains("calendar: entry.calendar(for: habit)"))
        XCTAssertFalse(accessory.contains("WidgetItemActions"))
        let shared = try source("HaiityWidget/WidgetGridViews.swift")
        XCTAssertFalse(shared.contains("strokeBorder"), "No decorative tile outlines")
        XCTAssertTrue(shared.contains("ContributionTiles("))
    }

    func testLiveActivitiesRetainSystemTimersAndOriginalIntents() throws {
        let session = try source("HaiityWidget/HabitSessionActivity.swift")
        for contract in ["ActivityConfiguration(for: HabitActivityAttributes.self)",
                         "Text(context.state.startedAt, style: .timer)",
                         "ProgressView(timerInterval:", "FinishHabitSessionIntent(",
                         "CancelHabitSessionIntent(", ".privacySensitive()", "HaiityWidgetLink.habits"] {
            XCTAssertTrue(session.contains(contract), contract)
        }
        let motivation = try source("HaiityWidget/MotivationLiveActivity.swift")
        XCTAssertTrue(motivation.contains("ActivityConfiguration(for: MotivationActivityAttributes.self)"))
        XCTAssertTrue(motivation.contains("DismissMotivationActivityIntent()"))
        XCTAssertTrue(motivation.contains(".privacySensitive()"))
    }

    func testCriticalWidgetActionAndReminderLabelsHaveAllLanguages() throws {
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(source("Haiity/Localizable.xcstrings").utf8))
                                   as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        for key in ["Überfällig", "Morgen", "Mit Nein beantworten", "Erinnerung erledigen", "Ausblenden"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let translations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(translations.count, 17, key)
            for (locale, value) in translations {
                let localized = try XCTUnwrap(value as? [String: Any], locale)
                let unit = try XCTUnwrap(localized["stringUnit"] as? [String: Any], locale)
                XCTAssertEqual(unit["state"] as? String, "translated", locale)
                XCTAssertFalse((unit["value"] as? String ?? "").isEmpty, locale)
            }
        }
    }

    func testProductionWidgetPreviewBoardsInBothAppearances() throws {
        let fixture = entry()
        for dark in [false, true] {
            let canvas = dark ? Color.black : Color.white
            let board = VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "hAiity Widgets").font(.title2.bold())
                HStack(alignment: .top, spacing: 16) {
                    HaiityWidgetView(entry: fixture).content(family: .systemSmall, dark: dark)
                        .frame(width: 138, height: 138)
                    HaiityWidgetView(entry: fixture).content(family: .systemMedium, dark: dark)
                        .frame(width: 332, height: 138)
                }
                HStack(alignment: .top, spacing: 16) {
                    HaiityWidgetView(entry: fixture).content(family: .systemLarge, dark: dark)
                        .frame(width: 332, height: 350)
                    VStack(spacing: 16) {
                        GraphWidgetView(entry: fixture).content(family: .systemMedium, dark: dark)
                            .frame(width: 332, height: 138)
                        RingAccessoryView(entry: fixture).content(mode: .vibrant)
                            .frame(width: 62, height: 62)
                        StreakAccessoryView(entry: fixture).content(mode: .vibrant, dark: true)
                            .frame(width: 160, height: 72)
                    }
                }
            }
            .padding(20)
            .foregroundStyle(dark ? Color.white : .black)
            .background(canvas)
            .environment(\.colorScheme, dark ? .dark : .light)
            _ = try render(board, name: dark ? "widget-board-dark" : "widget-board-light")
        }
    }

    private func render<V: View>(_ view: V, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        let directory = URL(fileURLWithPath: "/tmp/haiity-widget-rebuild", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        return image
    }

    private func assertFits<V: View>(_ view: V, size: CGSize, name: String) throws {
        let margin: CGFloat = 12
        let image = try render(view.frame(width: size.width, height: size.height)
            .background(Color.white).padding(margin).background(Color(uiColor: .magenta)), name: name)
        let pixels = rgba(image)
        let width = image.cgImage!.width, height = image.cgImage!.height
        var overflow = 0
        for y in 0..<height {
            for x in 0..<width where x < 22 || y < 22 || x >= width - 22 || y >= height - 22 {
                let i = (y * width + x) * 4
                if pixels[i] < 240 || pixels[i + 1] > 10 || pixels[i + 2] < 240 { overflow += 1 }
            }
        }
        XCTAssertEqual(overflow, 0, "\(name) paints outside its allocated widget bounds")
        XCTAssertEqual(width, Int((size.width + 2 * margin) * 2))
        XCTAssertEqual(height, Int((size.height + 2 * margin) * 2))
    }

    private func rgba(_ image: UIImage) -> [UInt8] {
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

    private func ink(_ image: UIImage, region: CGRect? = nil, dark: Bool = false, cutoff: UInt8 = 220) -> Int {
        let pixels = rgba(image)
        let width = image.cgImage!.width, height = image.cgImage!.height
        let area = region.map { CGRect(x: $0.minX * 2, y: $0.minY * 2, width: $0.width * 2, height: $0.height * 2) }
            ?? CGRect(x: 0, y: 0, width: width, height: height)
        var count = 0
        for y in max(0, Int(area.minY))..<min(height, Int(area.maxY)) {
            for x in max(0, Int(area.minX))..<min(width, Int(area.maxX)) {
                let i = (y * width + x) * 4
                if dark ? max(pixels[i], pixels[i + 1], pixels[i + 2]) > 40
                        : min(pixels[i], pixels[i + 1], pixels[i + 2]) < cutoff { count += 1 }
            }
        }
        return count
    }

    private func brightRingPixels(_ image: UIImage) -> Int {
        let pixels = rgba(image)
        let width = image.cgImage!.width, height = image.cgImage!.height
        var count = 0
        for y in 0..<height {
            for x in 0..<width where x < 24 || y < 24 || x >= width - 24 || y >= height - 24 {
                let i = (y * width + x) * 4
                if min(pixels[i], pixels[i + 1], pixels[i + 2]) > 200 { count += 1 }
            }
        }
        return count
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
