import Foundation
import SwiftUI
import UIKit
import OSLog

private enum GraphMetrics {
    private static let log = OSLog(subsystem: "com.aiity.haiity", category: "graphs")

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

/// Shared tile renderer for app cards and widgets. Colors stay caller-owned
/// so WidgetKit's vibrant and accented appearances retain their contrast.
struct ContributionTiles: View {
    let snapshot: GridCalendar.Snapshot
    let cell: CGFloat
    let gap: CGFloat
    var radius: CGFloat = 2
    var rows: Int = GridCalendar.rows
    var todayOutline: Color? = nil
    var highlightedCells: Set<ContributionHighlightCell>? = nil
    var highlightBackground: Color? = nil
    var highlightOutline: Color? = nil
    var highlightLineWidth: CGFloat = 0
    let level: (Int) -> Color

    static func highlightPadding(for gap: CGFloat) -> CGFloat {
        min(2, max(0.75, gap * 0.6))
    }

    static func highlightBackgroundOpacity(dark: Bool) -> CGFloat {
        dark ? 0.30 : 0.16
    }

    var body: some View {
        let padding = highlightedCells?.isEmpty == false
            ? Self.highlightPadding(for: gap) : 0
        Canvas { context, _ in
            let colors = (-1...4).map(level)
            let shape = Path(roundedRect: CGRect(x: 0, y: 0, width: cell, height: cell),
                             cornerRadius: radius)
            for (column, keys) in snapshot.keys.enumerated() {
                guard column < snapshot.levels.count else { continue }
                for row in 0..<min(rows, keys.count, snapshot.levels[column].count) {
                    let intensity = min(4, max(Habit.Answer.declinedLevel, snapshot.levels[column][row]))
                    let position = ContributionHighlightCell(column: column, row: row)
                    var tile = context
                    tile.translateBy(x: padding + CGFloat(column) * (cell + gap),
                                     y: padding + CGFloat(row) * (cell + gap))
                    tile.fill(shape, with: .color(colors[intensity + 1].opacity(keys[row] == nil ? 0.35 : 1)))
                    if highlightedCells?.contains(position) == true {
                        if let highlightBackground {
                            tile.fill(shape, with: .color(highlightBackground))
                        }
                        if let highlightOutline, highlightLineWidth > 0 {
                            let inset = highlightLineWidth / 2
                            let selectedRect = CGRect(x: inset, y: inset,
                                                      width: max(0, cell - highlightLineWidth),
                                                      height: max(0, cell - highlightLineWidth))
                            tile.stroke(Path(roundedRect: selectedRect,
                                             cornerRadius: max(0, radius - inset)),
                                        with: .color(highlightOutline),
                                        lineWidth: highlightLineWidth)
                        }
                    }
                    if keys[row] == snapshot.today, let todayOutline {
                        let rect = CGRect(x: 0.6, y: 0.6, width: cell - 1.2, height: cell - 1.2)
                        tile.stroke(Path(roundedRect: rect, cornerRadius: radius),
                                    with: .color(todayOutline), lineWidth: 1.2)
                    }
                }
            }
        }
        .frame(width: max(0, CGFloat(snapshot.keys.count) * (cell + gap) - gap) + padding * 2,
               height: max(0, CGFloat(rows) * (cell + gap) - gap) + padding * 2)
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct ContributionHighlightCell: Hashable {
    let column: Int
    let row: Int
}

/// Labels and tile surface are siblings, so labels never occupy the card.
struct ContributionChart: View, Equatable {
    /// A square-cell band fills its measured inner width; only column changes request history.
    static func bandMetrics(width: CGFloat, gap: CGFloat = GridCell.gap) -> (weeks: Int, cell: CGFloat) {
        let width = width.isFinite && width > 0 ? width : 12
        let weeks = Int(min(53, max(1, floor((width + gap) / (12 + gap)))))
        return (weeks, (width - CGFloat(weeks - 1) * gap) / CGFloat(weeks))
    }
    /// Fit whole columns in the viewport so neither edge starts on a cut tile.
    static func fittedCell(viewport: CGFloat, cell: CGFloat, gap: CGFloat) -> CGFloat {
        guard viewport > cell + 8 else { return cell }
        let width = viewport - 8
        let columns = max(1, floor((width + gap) / (cell + gap)))
        return (width + gap) / columns - gap
    }
    let snapshot: GridCalendar.Snapshot
    let cell: CGFloat
    let gap: CGFloat
    let width: CGFloat
    let showsMonthLabels: Bool
    let labelScale: CGFloat
    let palette: PaletteStyle
    let highlightsToday: Bool
    let checkPulse: Bool
    var showsSurface: Bool = false
    var highlightedCells: Set<ContributionHighlightCell>? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences

    static func == (a: Self, b: Self) -> Bool {
        a.snapshot == b.snapshot && a.cell == b.cell && a.gap == b.gap
            && a.width == b.width && a.showsMonthLabels == b.showsMonthLabels
            && a.labelScale == b.labelScale && a.palette == b.palette
            && a.highlightsToday == b.highlightsToday && a.checkPulse == b.checkPulse
            && a.showsSurface == b.showsSurface
            && a.highlightedCells == b.highlightedCells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMonthLabels {
                monthRow
            }
            if showsSurface {
                tiles.padding(.vertical, appearancePreferences.designStyle.graphPadding)
            } else {
                tiles
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var tiles: some View {
        let dark = scheme == .dark
        let radius = max(GridCell.radius, cell * 0.26)
        return ContributionTiles(snapshot: snapshot, cell: cell, gap: gap, radius: radius,
                                 todayOutline: highlightsToday ? .primary : nil,
                                 highlightedCells: highlightedCells,
                                 highlightBackground: Theme.accentText(palette).opacity(
                                    ContributionTiles.highlightBackgroundOpacity(dark: dark)),
                                 highlightOutline: Color.primary.opacity(dark ? 0.82 : 0.44),
                                 highlightLineWidth: dark ? 1.1 : 0.8) { value in
            value == 0 ? Color.primary.opacity(dark ? 0.12 : 0.065)
                : Theme.level(value, dark: dark, palette: palette)
        }
        .overlay(alignment: .topLeading) {
            if highlightsToday, let column = snapshot.keys.firstIndex(where: { $0.contains(snapshot.today) }),
               let row = snapshot.keys[column].firstIndex(of: snapshot.today) {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.accentText(palette), lineWidth: 1.4)
                    .frame(width: cell, height: cell)
                    .scaleEffect(checkPulse ? 1.9 : 1)
                    .opacity(checkPulse ? 0.9 : 0)
                    .offset(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap))
                    .allowsHitTesting(false)
            }
        }
    }

    private var monthRow: some View {
        let quietMarks = snapshot.marks.count > 4
            ? snapshot.marks.filter { $0.month % 2 == 1 } : snapshot.marks
        let marks = GridCalendar.placeMarks(quietMarks, pitch: cell + gap,
                                            contentWidth: width) { mark in
            (GridCalendar.label(for: mark) as NSString)
                .size(withAttributes: [.font: UIFont.systemFont(ofSize: max(1, 11 * labelScale))]).width
        }
        return ZStack(alignment: .topLeading) {
            Text(verbatim: "Mmm").font(.caption2).hidden()
            ForEach(marks, id: \.mark) { placed in
                Text(verbatim: GridCalendar.label(for: placed.mark))
                    .font(.caption2).foregroundStyle(Theme.secondaryText(preferences: appearancePreferences))
                    .fixedSize().offset(x: placed.x)
            }
        }
        .frame(width: max(width, 0), alignment: .topLeading)
        .accessibilityRepresentation { EmptyView() }
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
            && DayKey.key(for: a.now, calendar: contributionCalendar)
                == DayKey.key(for: b.now, calendar: contributionCalendar)
    }

    let days: [GitHubContributionDay]
    var weeks: Int?
    var cellSize: CGFloat?
    var gap: CGFloat?
    var showsMonthLabels: Bool = true
    var interactive: Bool = true
    var palette: PaletteStyle? = nil
    var now: Date = .now

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.palettes) private var palettes
    /// GitHub's date window is converted to the shared grid off the main
    /// actor so cached contributions never stall the first page frame.
    @State private var renderedSnapshot: (key: SnapshotRequest, value: GridCalendar.Snapshot)?
    @State private var viewportWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    private var fitsViewport: Bool { interactive && weeks == nil && cellSize == nil }

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize {
            return (cellSize, gap ?? GridCell.gap)
        }
        if fitsViewport {
            return (ContributionChart.bandMetrics(width: viewportWidth).cell, GridCell.gap)
        }
        // Measure the viewport, never the scrolling content: fit whole
        // columns at the same scale as the habit graph without a layout loop.
        return (ContributionChart.fittedCell(viewport: viewportWidth,
                                            cell: GridCell.size, gap: GridCell.gap), GridCell.gap)
    }

    private var renderedPalette: PaletteStyle {
        Theme.adaptivePalette(palette ?? palettes.style,
                              preferences: appearancePreferences,
                              dark: scheme == .dark)
    }

    struct SnapshotRequest: Hashable {
        let days: [GitHubContributionDay]
        let weeks: Int?
        let today: String

        // No account identity is available here. Only identical source data
        // can safely reuse a visible snapshot across view updates.
        func canDisplaySnapshot(for request: Self) -> Bool { self == request }
    }

    private func loadSnapshot(for request: SnapshotRequest) async {
        guard !fitsViewport || viewportWidth > 0 else { return }
        let graphSignpost = GraphMetrics.begin("githubGraphCalculation")
        defer { GraphMetrics.end("githubGraphCalculation", id: graphSignpost) }
        let displayWeeks = request.weeks ?? GridCalendar.weeksForDisplay(
            dates: request.days.map(\.date), today: request.today,
            calendar: Self.contributionCalendar)
        let levelsByDay = request.days.reduce(into: [String: Int]()) { result, day in
            result[day.date] = day.level
        }
        if let cached = GridCalendar.cachedSnapshot(levelsByDay: levelsByDay,
                                                    weeks: displayWeeks,
                                                    today: request.today,
                                                    calendar: Self.contributionCalendar) {
            renderedSnapshot = (request, cached)
            return
        }
        guard let snapshot = await ContributionSnapshotScheduler.perform({
            return GridCalendar.snapshot(levelsByDay: levelsByDay,
                                  weeks: displayWeeks,
                                  today: request.today,
                                  calendar: Self.contributionCalendar)
        }), !Task.isCancelled else { return }
        renderedSnapshot = (request, snapshot)
    }

    nonisolated static let contributionCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    var body: some View {
        // Habit and GitHub graphs share the same notion of today. The latest
        // fetched contribution can be older than today and must not freeze
        // the graph's future-cell behavior in that case.
        let today = DayKey.key(for: now, calendar: Self.contributionCalendar)
        let request = SnapshotRequest(days: days,
                                      weeks: fitsViewport ? ContributionChart.bandMetrics(width: viewportWidth).weeks : weeks,
                                      today: today)
        let snapshot = renderedSnapshot.flatMap {
            $0.key.canDisplaySnapshot(for: request) ? $0.value : nil
        }
        let displayWeeks = snapshot?.weeks ?? request.weeks ?? 1
        let m = metrics
        let pitch = m.cell + m.gap
        let contentWidth = CGFloat(max(displayWeeks, 1)) * pitch - m.gap

        Group {
            if let snapshot {
                if fitsViewport {
                    chartContent(snapshot: snapshot, cell: m.cell, gap: m.gap, width: contentWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if interactive {
                    if GridCalendar.needsHorizontalScroll(
                        contentWidth: contentWidth + 8,
                        viewportWidth: viewportWidth) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            chartContent(snapshot: snapshot,
                                         cell: m.cell,
                                         gap: m.gap,
                                         width: contentWidth)
                        }
                        .defaultScrollAnchor(.trailing)
                        .padding(.horizontal, 4)
                    } else {
                        chartContent(snapshot: snapshot,
                                     cell: m.cell,
                                     gap: m.gap,
                                     width: contentWidth)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    chartContent(snapshot: snapshot,
                                 cell: m.cell,
                                 gap: m.gap,
                                 width: contentWidth)
                }
            } else if fitsViewport {
                loadingGraph(cell: m.cell, gap: m.gap, width: contentWidth)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if interactive {
                ScrollView(.horizontal, showsIndicators: false) {
                    loadingGraph(cell: m.cell, gap: m.gap, width: contentWidth)
                }
                .defaultScrollAnchor(.trailing)
                .padding(.horizontal, 4)
            } else {
                loadingGraph(cell: m.cell, gap: m.gap, width: contentWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0, abs(width - viewportWidth) > 0.5 else { return }
            viewportWidth = width
        }
        .task(id: request) {
            await loadSnapshot(for: request)
        }
        .accessibilityLabel(String(localized: "GitHub-Beitragskalender"))
    }

    private func chartContent(snapshot: GridCalendar.Snapshot,
                              cell: CGFloat,
                              gap: CGFloat,
                              width: CGFloat) -> some View {
        ContributionChart(snapshot: snapshot,
                          cell: cell,
                          gap: gap,
                          width: width,
                          showsMonthLabels: showsMonthLabels,
                          labelScale: labelScale / 100,
                          palette: renderedPalette,
                          highlightsToday: false,
                          checkPulse: false,
                          showsSurface: interactive)
    }

    private func loadingGraph(cell: CGFloat, gap: CGFloat, width: CGFloat) -> some View {
        let weeks = min(53, max(1, Int(round((width + gap) / (cell + gap)))))
        return chartContent(snapshot: GridCalendar.Snapshot(
            weeks: weeks, today: "",
            keys: Array(repeating: Array(repeating: nil, count: GridCalendar.rows), count: weeks),
            levels: Array(repeating: Array(repeating: 0, count: GridCalendar.rows), count: weeks),
            marks: [], filledCount: 0), cell: cell, gap: gap, width: width)
            .accessibilityLabel(String(localized: "Beitragskalender wird geladen"))
    }

    struct Layout {
        let columns: [[GitHubContributionDay?]]
        let marks: [MonthMark]
    }

    /// Layout is pure but comparatively expensive: parsing dates and building
    /// every week happens for the app graph and the widget graph alike. Cache
    /// the derived geometry by contribution content, not by view identity.
    private struct LayoutCacheKey: Hashable {
        let days: [GitHubContributionDay]
        let weekLimit: Int?
    }

    private struct WindowCacheKey: Hashable {
        let days: [GitHubContributionDay]
        let weeks: Int
    }

    private static let layoutLock = NSLock()
    private static var layoutCache = BoundedGraphCache<LayoutCacheKey, Layout>(limit: 24)
    private static var windowCache = BoundedGraphCache<WindowCacheKey, [GitHubContributionDay]>(limit: 24)
    private(set) static var layoutComputeCount = 0

    static func resetLayoutCache() {
        layoutLock.lock()
        layoutCache.removeAll()
        windowCache.removeAll()
        layoutComputeCount = 0
        layoutLock.unlock()
    }

    /// Widgets need a stable number of columns even when a cached response is
    /// sparse. Fill the window with empty days while preserving every real
    /// contribution returned by GitHub.
    static func widgetWindow(days: [GitHubContributionDay], weeks: Int) -> [GitHubContributionDay] {
        guard weeks > 0 else { return [] }

        let key = WindowCacheKey(days: days,
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
        windowCache[key] = result
        layoutLock.unlock()
        return result
    }

    static func layout(days: [GitHubContributionDay], weekLimit: Int?) -> Layout {
        let key = LayoutCacheKey(days: days,
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
        layoutCache[key] = layout
        layoutComputeCount += 1
        layoutLock.unlock()
    }

}
