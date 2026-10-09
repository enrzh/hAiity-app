import SwiftUI
import UIKit

/// Fixed GitHub activity above personal entries, with a direct profile action.
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
    @Environment(\.appearancePreferences) private var appearancePreferences
    @State private var isContextMenuVisible = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    private var headerHeight: CGFloat { collapsed ? 32 : Theme.Metrics.hit }
    private var outerGap: CGFloat { collapsed ? designStyle.cardOuterGap : designStyle.cardOuterGap + 4 }

    var body: some View {
        cardSurface
            .padding(.top, 4)
            .padding(.bottom, outerGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("github-contribution-card")
    }

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            header
            graph
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var graph: some View {
        GitHubContributionGraph(days: snapshot.days,
                                showsMonthLabels: showsMonthLabels,
                                palette: palettes.style)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isContextMenuVisible ? 0 : 1)
        .contentShape(RoundedRectangle(cornerRadius: designStyle.cardRadius,
                                       style: .continuous))
        .overlay {
            GraphContextMenu(cardRadius: designStyle.cardRadius,
                             previewWidth: previewWidth,
                             previewHeight: previewHeight,
                             previewAccessibilityIdentifier: "github-preview",
                             preview: { AnyView(cardPreview) },
                             actions: [GraphMenuAction(title: String(localized: "GitHub-Profil öffnen"),
                                                       symbol: "arrow.up.right.square",
                                                       handler: openProfile)],
                             commit: openProfile,
                             onMenuVisibilityChanged: { visible in
                                 isContextMenuVisible = visible
                             })
                .frame(maxWidth: previewWidth)
        }
        .accessibilityIdentifier("github-grid")
    }

    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap))
            : AnyLayout(HStackLayout(spacing: designStyle.rowGap * 2))
        return layout {
            Text(showsUsername ? snapshot.username : "GitHub")
                .font(collapsed ? designStyle.rowTitleFont : designStyle.sectionTitleFont)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("github-username")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button(action: openProfile) {
                Label(String(localized: "GitHub-Profil öffnen"), systemImage: "arrow.up.right.square")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentText(palettes.style))
            .accessibilityIdentifier("github-open-profile")
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .leading)
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
            header
            GitHubContributionGraph(days: snapshot.days,
                                    // A recent window keeps the seven GitHub
                                    // rows legible without forcing tiny tiles.
                                    weeks: Self.previewGraphWeeks,
                                    cellSize: previewGraphCellSize,
                                    gap: Self.previewGraphGap,
                                    showsMonthLabels: false,
                                    interactive: false,
                                    palette: palettes.style)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, designStyle.cardPadding)
        .frame(width: previewWidth)
        .accessibilityIdentifier("github-preview")
    }
}
