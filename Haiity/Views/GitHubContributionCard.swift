import SwiftUI
import UIKit

/// Feste GitHub-Karte auf der Habits-Seite. Nur Anzeige: kein Habit, kein
/// Wischen, kein Tipp. Halten auf dem Raster öffnet das eine Profil-Menü.
struct GitHubContributionCard: View, Equatable {
    static func == (a: GitHubContributionCard, b: GitHubContributionCard) -> Bool {
        a.snapshot == b.snapshot
            && a.collapsed == b.collapsed
            && a.showsUsername == b.showsUsername
            && a.showsMonthLabels == b.showsMonthLabels
    }

    let snapshot: GitHubContributionSnapshot
    var collapsed: Bool = false
    let showsUsername: Bool
    let showsMonthLabels: Bool
    let openProfile: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.palettes) private var palettes
    @State private var isContextMenuVisible = false

    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }
    private var outerGap: CGFloat { collapsed ? 12 : Theme.Metrics.gutter }

    var body: some View {
        cardSurface
            .padding(.top, 4)
            .padding(.bottom, outerGap)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("github-contribution-card")
    }

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsUsername {
                header
                Divider()
                    .opacity(0.45)
                    .padding(.leading, Theme.Metrics.glyph + Theme.Metrics.gap)
                    .padding(.vertical, 4)
            }
            graph
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, Theme.Metrics.cardPadding)
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText(palettes.style))
                .frame(width: 28, height: 28)
                .background(Theme.accentFill(palettes.style).opacity(0.14),
                            in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            Text(snapshot.username)
                .font(collapsed ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("github-username")
    }

    private var graph: some View {
        GitHubContributionGraph(days: snapshot.days,
                                showsMonthLabels: showsMonthLabels)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 0) {
            if showsUsername {
                header
                Divider()
                    .opacity(0.45)
                    .padding(.leading, Theme.Metrics.glyph + Theme.Metrics.gap)
                    .padding(.vertical, 4)
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
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, Theme.Metrics.cardPadding)
        .frame(width: previewWidth)
        .accessibilityIdentifier("github-preview")
    }
}
