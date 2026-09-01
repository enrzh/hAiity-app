import Foundation
import SwiftUI

/// 7-Zeilen-Raster der GitHub-Tage. Chronologie bleibt links->rechts, auch
/// in RTL, und benutzt die GitHub-Grunrampe - kein nachgebautes Habit.
struct GitHubContributionGraph: View {
    let days: [GitHubContributionDay]
    var weeks: Int?
    var cellSize: CGFloat?
    var gap: CGFloat?
    var showsMonthLabels: Bool = true
    var interactive: Bool = true
    var palette: PaletteStyle = .default

    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences
    @State private var available: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    private static let referenceColumns: CGFloat = 24
    private static let referencePitch: CGFloat = 14

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize {
            return (cellSize, gap ?? GitHubGraphMetrics.gap)
        }
        let pitch = available > 0
            ? available / Self.referenceColumns
            : Self.referencePitch
        return (min(GitHubGraphMetrics.cell,
                    max(8, pitch * 11 / Self.referencePitch)),
                min(GitHubGraphMetrics.gap,
                    max(2, pitch * 3 / Self.referencePitch)))
    }

    private var renderedPalette: PaletteStyle {
        Theme.adaptivePalette(palette,
                              preferences: appearancePreferences,
                              dark: scheme == .dark)
    }

    var body: some View {
        let layout = Self.layout(days: days, weekLimit: weeks)
        let m = metrics
        let pitch = m.cell + m.gap
        let contentWidth = CGFloat(max(layout.columns.count, 1)) * pitch - m.gap
        let height = CGFloat(GridCalendar.rows) * pitch - m.gap

        Group {
            if interactive {
                ScrollView(.horizontal, showsIndicators: false) {
                    graphContent(layout: layout,
                                 metrics: m,
                                 pitch: pitch,
                                 contentWidth: contentWidth,
                                 height: height)
                }
                .softScrollEdges()
                .defaultScrollAnchor(.trailing)
            } else {
                // A disabled ScrollView can retain a trailing offset inside a
                // UIKit context preview. Render the fixed-width canvas
                // directly so every contribution column remains visible.
                graphContent(layout: layout,
                             metrics: m,
                             pitch: pitch,
                             contentWidth: contentWidth,
                             height: height)
            }
        }
        .background(widthReader)
        .accessibilityLabel(String(localized: "GitHub-Beitragskalender"))
    }

    @ViewBuilder
    private func graphContent(layout: Layout,
                              metrics: (cell: CGFloat, gap: CGFloat),
                              pitch: CGFloat,
                              contentWidth: CGFloat,
                              height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if showsMonthLabels {
                monthRow(layout.marks, width: contentWidth, pitch: pitch)
            }
            Canvas { context, _ in
                var shading: [Int: GraphicsContext.Shading] = [:]
                let cellPath = Path(roundedRect: CGRect(x: 0, y: 0,
                                                        width: metrics.cell,
                                                        height: metrics.cell),
                                    cornerRadius: GitHubGraphMetrics.cornerRadius)
                let dark = scheme == .dark
                for (column, week) in layout.columns.enumerated() {
                    for row in 0..<GridCalendar.rows {
                        let level = week[row]?.level ?? 0
                        if shading[level] == nil {
                            shading[level] = .color(
                                Theme.level(level, dark: dark, palette: renderedPalette))
                        }
                        var cellContext = context
                        cellContext.translateBy(x: CGFloat(column) * pitch,
                                                y: CGFloat(row) * pitch)
                        cellContext.fill(cellPath, with: shading[level]!)
                        if appearancePreferences.material == .adaptive {
                            cellContext.stroke(
                                cellPath,
                                with: .color(Theme.adaptiveTileOutline(
                                    preferences: appearancePreferences,
                                    dark: dark)),
                                lineWidth: 0.5)
                        }
                    }
                }
            }
            .frame(width: max(contentWidth, 0), height: height)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, 2)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func monthRow(_ marks: [MonthMark], width: CGFloat, pitch: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: max(width, 0), height: 14 * max(1, labelScale / 100))
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                Text(verbatim: GridCalendar.label(for: mark))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(mark.column) * pitch)
            }
        }
        .frame(height: 14 * max(1, labelScale / 100), alignment: .topLeading)
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

private enum GitHubGraphMetrics {
    static let cell: CGFloat = 12
    static let gap: CGFloat = 3
    static let cornerRadius: CGFloat = 2
}

private struct GitHubGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
