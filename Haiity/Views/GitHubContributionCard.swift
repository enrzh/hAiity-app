import SwiftUI
import UIKit

/// Feste GitHub-Karte auf der Habits-Seite. Nur Anzeige: kein Habit, kein
/// Wischen, kein Tipp. Halten auf dem Raster öffnet das eine Profil-Menü.
struct GitHubContributionCard: View, Equatable {
    static func == (a: GitHubContributionCard, b: GitHubContributionCard) -> Bool {
        a.snapshot == b.snapshot && a.collapsed == b.collapsed
    }

    let snapshot: GitHubContributionSnapshot
    var collapsed: Bool = false
    let openProfile: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }
    private var innerGap: CGFloat { collapsed ? 4 : Theme.Metrics.gap }
    private var outerGap: CGFloat { collapsed ? 12 : Theme.Metrics.gutter }

    var body: some View {
        VStack(alignment: .leading, spacing: innerGap) {
            header
            graph
        }
        .padding(.top, 4)
        .padding(.bottom, outerGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("github-contribution-card")
    }

    private var header: some View {
        Text(snapshot.username)
            .font(collapsed ? .subheadline.weight(.semibold) : .headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("github-username")
    }

    private var graph: some View {
        GitHubContributionGraph(days: snapshot.days)
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
            .background {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 preview: { AnyView(cardPreview) },
                                 actions: [GraphMenuAction(title: String(localized: "GitHub-Profil öffnen"),
                                                           symbol: "arrow.up.right.square",
                                                           handler: openProfile)],
                                 commit: openProfile)
            }
            .accessibilityIdentifier("github-grid")
    }

    private var previewWidth: CGFloat {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).width
    }

    private var previewWeeks: Int {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).weeks
    }

    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.username)
                .font(.headline)
                .lineLimit(1)
            GitHubContributionGraph(days: snapshot.days,
                                    weeks: previewWeeks,
                                    cellSize: HabitCard.previewCell,
                                    gap: HabitCard.previewGap)
        }
        .padding(Theme.Metrics.gutter)
        .frame(width: previewWidth)
        .background(Color(scheme == .dark
                          ? .tertiarySystemBackground
                          : .secondarySystemGroupedBackground))
        .accessibilityIdentifier("github-preview")
    }
}

/// 7-Zeilen-Raster der GitHub-Tage. Chronologie bleibt links→rechts, auch
/// in RTL, und benutzt die GitHub-Grünrampe — kein nachgebautes Habit.
struct GitHubContributionGraph: View {
    let days: [GitHubContributionDay]
    var weeks: Int?
    var cellSize: CGFloat?
    var gap: CGFloat?

    @Environment(\.colorScheme) private var scheme
    @State private var available: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    private static let referenceColumns: CGFloat = 24
    private static let referencePitch: CGFloat = 14

    private var metrics: (cell: CGFloat, gap: CGFloat) {
        if let cellSize { return (cellSize, gap ?? GridCell.gap) }
        let pitch = available > 0
            ? available / Self.referenceColumns
            : Self.referencePitch
        return (min(GridCell.size, max(8, pitch * 11 / Self.referencePitch)),
                min(GridCell.gap, max(2, pitch * 3 / Self.referencePitch)))
    }

    var body: some View {
        let layout = Self.layout(days: days, weekLimit: weeks)
        let m = metrics
        let pitch = m.cell + m.gap
        let contentWidth = CGFloat(max(layout.columns.count, 1)) * pitch - m.gap
        let height = CGFloat(GridCalendar.rows) * pitch - m.gap

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                monthRow(layout.marks, width: contentWidth, pitch: pitch)
                Canvas { context, _ in
                    var shading: [Int: GraphicsContext.Shading] = [:]
                    let cellPath = Path(roundedRect: CGRect(x: 0, y: 0,
                                                            width: m.cell, height: m.cell),
                                        cornerRadius: GridCell.radius)
                    let dark = scheme == .dark
                    for (column, week) in layout.columns.enumerated() {
                        for row in 0..<GridCalendar.rows {
                            let level = week[row]?.level ?? 0
                            if shading[level] == nil {
                                shading[level] = .color(
                                    Theme.level(level, dark: dark, palette: PaletteStyle.default))
                            }
                            var cellContext = context
                            cellContext.translateBy(x: CGFloat(column) * pitch,
                                                    y: CGFloat(row) * pitch)
                            cellContext.fill(cellPath, with: shading[level]!)
                        }
                    }
                }
                .frame(width: max(contentWidth, 0), height: height)
                .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.vertical, 2)
        }
        .environment(\.layoutDirection, .leftToRight)
        .defaultScrollAnchor(.trailing)
        .background(widthReader)
        .accessibilityLabel(String(localized: "GitHub-Beitragskalender"))
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

    static func layout(days: [GitHubContributionDay], weekLimit: Int?) -> Layout {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first, let firstDate = formatter.date(from: first.date) else {
            return Layout(columns: [Array(repeating: nil, count: GridCalendar.rows)], marks: [])
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
        return Layout(columns: columns, marks: marks)
    }
}

private struct GitHubGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
