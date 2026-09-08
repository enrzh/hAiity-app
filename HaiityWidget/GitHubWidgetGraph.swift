import WidgetKit
import SwiftUI

/// WidgetKit-safe GitHub graph. It uses the same height-driven band geometry as
/// the habit graph, but keeps only the recent columns that fit this widget.
struct GitHubWidgetGraph: View {
    let content: GitHubWidgetContent
    let palette: PaletteStyle
    let mode: WidgetRenderingMode

    init(content: GitHubWidgetContent,
         palette: PaletteStyle,
         mode: WidgetRenderingMode = .fullColor) {
        self.content = content
        self.palette = palette
        self.mode = mode
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            graphBody(in: geometry.size)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func graphBody(in size: CGSize) -> some View {
        switch content {
        case .connectPrompt:
            Link(destination: HaiityWidgetLink.habits) {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "GitHub verbinden"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(String(localized: "GitHub verbinden"))
        case .graph(let days):
            let graph = GraphLayout.trailing(width: size.width,
                                             height: size.height)
            let visibleDays = GitHubContributionGraph.widgetWindow(days: days,
                                                                    weeks: graph.weeks)
            let columns = GitHubContributionGraph.layout(days: visibleDays,
                                                          weekLimit: graph.weeks).columns

            let snapshot = GridCalendar.Snapshot(
                weeks: columns.count, today: "",
                keys: columns.map { $0.map { $0?.date } },
                levels: columns.map { $0.map { $0?.level ?? 0 } },
                marks: [], filledCount: 0)
            ContributionTiles(snapshot: snapshot, cell: graph.cell, gap: graph.gap,
                              radius: graph.radius) { level in
                HomeWidgetInk.level(level, mode: mode, dark: scheme == .dark, palette: palette)
            }
            .frame(width: graph.contentWidth, height: graph.contentHeight,
                   alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

}
