import Foundation
import SwiftUI
import UIKit

/// One Canvas renderer for every contribution graph in the app. The source
/// data may be a Habit or GitHub, but the expensive view tree and tile styling
/// should not diverge between them.
struct ContributionGridRenderer: View, Equatable {
    let snapshot: GridCalendar.Snapshot
    let cell: CGFloat
    let gap: CGFloat
    let width: CGFloat
    let showsMonthLabels: Bool
    let labelScale: CGFloat
    let palette: PaletteStyle
    let highlightsToday: Bool
    let checkPulse: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences

    static func == (a: ContributionGridRenderer, b: ContributionGridRenderer) -> Bool {
        a.snapshot == b.snapshot
            && a.cell == b.cell
            && a.gap == b.gap
            && a.width == b.width
            && a.showsMonthLabels == b.showsMonthLabels
            && a.labelScale == b.labelScale
            && a.palette == b.palette
            && a.highlightsToday == b.highlightsToday
            && a.checkPulse == b.checkPulse
    }

    var body: some View {
        let pitch = cell + gap
        let marks = GridCalendar.placeMarks(snapshot.marks,
                                             pitch: pitch,
                                             contentWidth: width) { mark in
            Self.labelWidth(GridCalendar.label(for: mark), scale: labelScale)
        }
        let todayRect = todayRect(pitch: pitch)

        VStack(alignment: .leading, spacing: 3) {
            if showsMonthLabels {
                monthRow(marks)
            }
            Canvas { context, _ in
                var shading: [Int: GraphicsContext.Shading] = [:]
                var dimmedShading: [Int: GraphicsContext.Shading] = [:]
                let cellPath = Path(roundedRect: CGRect(x: 0, y: 0,
                                                        width: cell,
                                                        height: cell),
                                    cornerRadius: GridCell.radius)
                let dark = scheme == .dark
                let emptyCell = Color.primary.opacity(dark ? 0.16 : 0.07)
                let usesAdaptiveOutline = Theme.effectiveMaterial(appearancePreferences) == .adaptive
                let outline = Theme.adaptiveTileOutline(
                    preferences: appearancePreferences,
                    dark: dark)

                for (columnIndex, column) in snapshot.keys.enumerated() {
                    guard columnIndex < snapshot.levels.count else { continue }
                    for row in 0..<GridCalendar.rows {
                        guard row < column.count,
                              row < snapshot.levels[columnIndex].count else { continue }
                        let level = snapshot.levels[columnIndex][row]
                        let future = column[row] == nil
                        let fill: GraphicsContext.Shading
                        if level == 0 && !future {
                            // Keep empty history cells visible so every row
                            // shares one optical baseline with no false gaps.
                            fill = .color(emptyCell)
                        } else if future {
                            if dimmedShading[level] == nil {
                                dimmedShading[level] = .color(
                                    Theme.level(level, dark: dark, palette: palette).opacity(0.35))
                            }
                            fill = dimmedShading[level]!
                        } else {
                            if shading[level] == nil {
                                shading[level] = .color(
                                    Theme.level(level, dark: dark, palette: palette))
                            }
                            fill = shading[level]!
                        }
                        var cellContext = context
                        cellContext.translateBy(x: CGFloat(columnIndex) * pitch,
                                                y: CGFloat(row) * pitch)
                        cellContext.fill(cellPath, with: fill)
                        if usesAdaptiveOutline {
                            cellContext.stroke(cellPath,
                                               with: .color(outline),
                                               lineWidth: 0.5)
                        }
                    }
                }

                if highlightsToday, let todayRect {
                    context.stroke(Path(roundedRect: todayRect.insetBy(dx: 0.6, dy: 0.6),
                                        cornerRadius: GridCell.radius),
                                   with: .color(.primary),
                                   lineWidth: 1.2)
                }
            }
            .frame(width: max(width, 0), height: gridHeight(pitch: pitch))
            .overlay(alignment: .topLeading) {
                if highlightsToday, let todayRect {
                    RoundedRectangle(cornerRadius: GridCell.radius, style: .continuous)
                        .strokeBorder(Theme.accentText(palette), lineWidth: 1.4)
                        .frame(width: todayRect.width, height: todayRect.height)
                        .offset(x: todayRect.minX, y: todayRect.minY)
                        .scaleEffect(checkPulse ? 1.9 : 1)
                        .opacity(checkPulse ? 0.9 : 0)
                        .allowsHitTesting(false)
                }
            }
            .id("grid-canvas")
        }
        .padding(.vertical, 2)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func gridHeight(pitch: CGFloat) -> CGFloat {
        CGFloat(GridCalendar.rows) * pitch - gap
    }

    private func todayRect(pitch: CGFloat) -> CGRect? {
        for (columnIndex, column) in snapshot.keys.enumerated() {
            if let row = column.firstIndex(of: snapshot.today) {
                return CGRect(x: CGFloat(columnIndex) * pitch,
                              y: CGFloat(row) * pitch,
                              width: cell,
                              height: cell)
            }
        }
        return nil
    }

    private func monthRow(_ marks: [GridCalendar.PlacedMark]) -> some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "Mmm").font(.caption2).hidden()
            ForEach(marks, id: \.mark) { placed in
                Text(verbatim: GridCalendar.label(for: placed.mark))
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .fixedSize()
                    .offset(x: placed.x)
            }
        }
        .frame(width: max(width, 0), alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private static func labelWidth(_ text: String, scale: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let size = max(1, 11 * scale)
        return (text as NSString)
            .size(withAttributes: [.font: UIFont.systemFont(ofSize: size)]).width
    }
}

/// Shared key for contribution intensity, used by habit and GitHub surfaces.
struct ContributionChartLegend: View {
    let palette: PaletteStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            Text(String(localized: "Weniger")).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { level in
                    GridCell(color: Theme.level(level, dark: scheme == .dark, palette: palette), size: 9)
                }
            }
            Text(String(localized: "Mehr")).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Beitragsintensität: weniger bis mehr"))
    }
}

/// 7-Zeilen-Raster der GitHub-Tage. Chronologie bleibt links->rechts, auch
/// in RTL, und benutzt die GitHub-Grunrampe - kein nachgebautes Habit.
struct GitHubContributionGraph: View, Equatable {
    static func == (a: GitHubContributionGraph, b: GitHubContributionGraph) -> Bool {
        a.days == b.days
            && a.weeks == b.weeks
            && a.cellSize == b.cellSize
            && a.gap == b.gap
            && a.showsMonthLabels == b.showsMonthLabels
            && a.interactive == b.interactive
            && a.palette == b.palette
    }

    let days: [GitHubContributionDay]
    var weeks: Int?
    var cellSize: CGFloat?
    var gap: CGFloat?
    var showsMonthLabels: Bool = true
    var interactive: Bool = true
    var palette: PaletteStyle? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.palettes) private var palettes
    @State private var available: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    private static let referenceColumns: CGFloat = 24
    private static let referencePitch: CGFloat = GridCell.size + GridCell.gap

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize {
            return (cellSize, gap ?? GridCell.gap)
        }
        let pitch = available > 0
            ? available / Self.referenceColumns
            : Self.referencePitch
        return (min(GridCell.size,
                    max(8, pitch * 11 / Self.referencePitch)),
                min(GridCell.gap,
                    max(2, pitch * 3 / Self.referencePitch)))
    }

    private var renderedPalette: PaletteStyle {
        Theme.adaptivePalette(palette ?? palettes.style,
                              preferences: appearancePreferences,
                              dark: scheme == .dark)
    }

    private static let contributionCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    var body: some View {
        // Habit and GitHub graphs share the same notion of today. The latest
        // fetched contribution can be older than today and must not freeze
        // the graph's future-cell behavior in that case.
        let today = DayKey.today(calendar: Self.contributionCalendar)
        let displayWeeks = weeks ?? GridCalendar.weeksForDisplay(
            dates: days.map(\.date),
            today: today,
            calendar: Self.contributionCalendar)
        let levelsByDay = days.reduce(into: [String: Int]()) { result, day in
            result[day.date] = day.level
        }
        let snapshot = GridCalendar.snapshot(levelsByDay: levelsByDay,
                                             weeks: displayWeeks,
                                             today: today,
                                             calendar: Self.contributionCalendar)
        let m = metrics
        let pitch = m.cell + m.gap
        let contentWidth = CGFloat(max(snapshot.keys.count, 1)) * pitch - m.gap

        Group {
            if interactive {
                ScrollView(.horizontal, showsIndicators: false) {
                    ContributionGridRenderer(snapshot: snapshot,
                                             cell: m.cell,
                                             gap: m.gap,
                                             width: contentWidth,
                                             showsMonthLabels: showsMonthLabels,
                                             labelScale: labelScale / 100,
                                             palette: renderedPalette,
                                             highlightsToday: false,
                                             checkPulse: false)
                }
                .softScrollEdges()
                .defaultScrollAnchor(.trailing)
                .scrollDisabled(available > 0
                                && !GridCalendar.needsHorizontalScroll(
                                    contentWidth: contentWidth,
                                    viewportWidth: available))
            } else {
                // A disabled ScrollView can retain a trailing offset inside a
                // UIKit context preview. Render the fixed-width canvas
                // directly so every contribution column remains visible.
                ContributionGridRenderer(snapshot: snapshot,
                                         cell: m.cell,
                                         gap: m.gap,
                                         width: contentWidth,
                                         showsMonthLabels: showsMonthLabels,
                                         labelScale: labelScale / 100,
                                         palette: renderedPalette,
                                         highlightsToday: false,
                                         checkPulse: false)
            }
        }
        .background(widthReader)
        .accessibilityLabel(String(localized: "GitHub-Beitragskalender"))
    }

    private var widthReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: GitHubGridWidthKey.self, value: geo.size.width)
        }
        .onPreferenceChange(GitHubGridWidthKey.self) { width in
            if abs(width - available) > 0.5 { available = width }
        }
    }

    struct Layout {
        let columns: [[GitHubContributionDay?]]
        let marks: [MonthMark]
    }

    /// Layout is pure but comparatively expensive: parsing dates and building
    /// every week happens for the app graph and the widget graph alike. Cache
    /// the derived geometry by contribution content, not by view identity.
    private struct LayoutCacheKey: Hashable {
        let fingerprint: Int
        let count: Int
        let weekLimit: Int?
    }

    private struct WindowCacheKey: Hashable {
        let fingerprint: Int
        let count: Int
        let weeks: Int
    }

    private static let layoutLock = NSLock()
    private static var layoutCache: [LayoutCacheKey: Layout] = [:]
    private static var windowCache: [WindowCacheKey: [GitHubContributionDay]] = [:]
    private static let cacheLimit = 24
    private(set) static var layoutComputeCount = 0

    static func resetLayoutCache() {
        layoutLock.lock()
        layoutCache.removeAll(keepingCapacity: true)
        windowCache.removeAll(keepingCapacity: true)
        layoutComputeCount = 0
        layoutLock.unlock()
    }

    /// Widgets need a stable number of columns even when a cached response is
    /// sparse. Fill the window with empty days while preserving every real
    /// contribution returned by GitHub.
    static func widgetWindow(days: [GitHubContributionDay], weeks: Int) -> [GitHubContributionDay] {
        guard weeks > 0 else { return [] }

        let key = WindowCacheKey(fingerprint: fingerprint(days),
                                 count: days.count,
                                 weeks: weeks)
        layoutLock.lock()
        if let cached = windowCache[key] {
            layoutLock.unlock()
            return cached
        }
        layoutLock.unlock()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let validDates = days.compactMap { formatter.date(from: $0.date) }
        guard let latest = validDates.max() else { return days }

        let weekday = calendar.component(.weekday, from: latest)
        guard let endOfWeek = calendar.date(byAdding: .day,
                                            value: 7 - weekday,
                                            to: latest),
              let start = calendar.date(byAdding: .day,
                                        value: -(weeks * GridCalendar.rows - 1),
                                        to: endOfWeek) else {
            return days
        }

        var byDate: [String: GitHubContributionDay] = [:]
        for day in days { byDate[day.date] = day }

        let result = (0..<(weeks * GridCalendar.rows)).compactMap { (offset: Int) -> GitHubContributionDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            let key = formatter.string(from: date)
            return byDate[key] ?? GitHubContributionDay(date: key, count: 0, level: 0)
        }

        layoutLock.lock()
        if windowCache.count >= cacheLimit { windowCache.removeAll(keepingCapacity: true) }
        windowCache[key] = result
        layoutLock.unlock()
        return result
    }

    static func layout(days: [GitHubContributionDay], weekLimit: Int?) -> Layout {
        let key = LayoutCacheKey(fingerprint: fingerprint(days),
                                 count: days.count,
                                 weekLimit: weekLimit)
        layoutLock.lock()
        if let cached = layoutCache[key] {
            layoutLock.unlock()
            return cached
        }
        layoutLock.unlock()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first, let firstDate = formatter.date(from: first.date) else {
            let empty = Layout(columns: [Array(repeating: nil, count: GridCalendar.rows)], marks: [])
            storeLayout(empty, for: key)
            return empty
        }

        let pad = calendar.component(.weekday, from: firstDate) - 1
        var byDate: [String: GitHubContributionDay] = [:]
        for day in sorted { byDate[day.date] = day }

        let lastDate = formatter.date(from: sorted.last?.date ?? first.date) ?? firstDate
        let totalDays = (calendar.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0) + 1 + pad
        let columnCount = max(1, Int(ceil(Double(totalDays) / Double(GridCalendar.rows))))
        let limited = weekLimit.map { min(columnCount, max(1, $0)) } ?? columnCount
        let startColumn = max(0, columnCount - limited)

        var columns: [[GitHubContributionDay?]] = []
        var marks: [MonthMark] = []
        var previousMonth: Int?
        for column in startColumn..<columnCount {
            var week: [GitHubContributionDay?] = []
            for row in 0..<GridCalendar.rows {
                let offset = column * GridCalendar.rows + row - pad
                guard offset >= 0,
                      let date = calendar.date(byAdding: .day, value: offset, to: firstDate) else {
                    week.append(nil)
                    continue
                }
                week.append(byDate[formatter.string(from: date)])
            }
            columns.append(week)
            if let lead = week.first, let day = lead, let date = formatter.date(from: day.date) {
                let month = calendar.component(.month, from: date)
                let year = calendar.component(.year, from: date)
                let dayNumber = calendar.component(.day, from: date)
                if month != previousMonth, column == startColumn ? dayNumber <= 7 : true {
                    marks.append(MonthMark(column: column - startColumn, year: year, month: month))
                }
                previousMonth = month
            }
        }
        let result = Layout(columns: columns, marks: marks)
        storeLayout(result, for: key)
        return result
    }

    private static func storeLayout(_ layout: Layout, for key: LayoutCacheKey) {
        layoutLock.lock()
        if layoutCache.count >= cacheLimit { layoutCache.removeAll(keepingCapacity: true) }
        layoutCache[key] = layout
        layoutComputeCount += 1
        layoutLock.unlock()
    }

    private static func fingerprint(_ days: [GitHubContributionDay]) -> Int {
        var hasher = Hasher()
        hasher.combine(days.count)
        for day in days {
            hasher.combine(day.date)
            hasher.combine(day.count)
            hasher.combine(day.level)
        }
        return hasher.finalize()
    }
}

private struct GitHubGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
