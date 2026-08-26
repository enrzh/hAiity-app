import SwiftUI
import UIKit

/// Feste GitHub-Karte auf der Habits-Seite. Nur Anzeige: kein Habit, kein
/// Wischen, kein Tipp. Halten auf dem Raster öffnet das eine Profil-Menü.
struct GitHubContributionCard: View, Equatable {
    static func == (a: GitHubContributionCard, b: GitHubContributionCard) -> Bool {
        a.snapshot == b.snapshot
            && a.collapsed == b.collapsed
            && a.showsUsername == b.showsUsername
    }

    let snapshot: GitHubContributionSnapshot
    var collapsed: Bool = false
    let showsUsername: Bool
    let openProfile: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isContextMenuVisible = false

    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }
    private var innerGap: CGFloat { collapsed ? 4 : Theme.Metrics.gap }
    private var outerGap: CGFloat { collapsed ? 12 : Theme.Metrics.gutter }

    var body: some View {
        VStack(alignment: .leading, spacing: innerGap) {
            if showsUsername {
                header
            }
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
            .appSurface()
            .opacity(isContextMenuVisible ? 0 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
            .overlay {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 previewHeight: previewHeight,
                                 preview: { AnyView(cardPreview) },
                                 actions: [GraphMenuAction(title: String(localized: "GitHub-Profil öffnen"),
                                                           symbol: "arrow.up.right.square",
                                                           handler: openProfile)],
                                 commit: openProfile,
                                 onMenuVisibilityChanged: { visible in
                                     isContextMenuVisible = visible
                                 })
            }
            .accessibilityIdentifier("github-grid")
    }

    private var previewWidth: CGFloat {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).width
    }

    private var previewHeight: CGFloat {
        showsUsername ? 216 : 184
    }

    private var previewGraphCellSize: CGFloat {
        // The popup cannot be horizontally scrolled reliably. Show a recent
        // window with a readable, card-sized tile scale instead.
        let gap = Self.previewGraphGap
        let graphWidth = max(1, previewWidth - 2 * Theme.Metrics.gutter)
        return max(8, (graphWidth + gap) / CGFloat(Self.previewGraphWeeks) - gap)
    }

    private static let previewGraphWeeks = 16
    private static let previewGraphGap: CGFloat = 2

    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsUsername {
                Text(snapshot.username)
                    .font(.headline)
                    .lineLimit(1)
            }
            GitHubContributionGraph(days: snapshot.days,
                                    // A recent window keeps the seven GitHub
                                    // rows legible without forcing tiny tiles.
                                    weeks: Self.previewGraphWeeks,
                                    cellSize: previewGraphCellSize,
                                    gap: Self.previewGraphGap,
                                    showsMonthLabels: false,
                                    interactive: false)
        }
        .padding(Theme.Metrics.gutter)
        .frame(width: previewWidth)
        .background(Color(scheme == .dark
                          ? .tertiarySystemBackground
                          : .secondarySystemGroupedBackground))
        .accessibilityIdentifier("github-preview")
    }
}
