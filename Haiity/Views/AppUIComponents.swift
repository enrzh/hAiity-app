import SwiftUI

/// The shell every settings page sits in: one scroll view, the shared gutter,
/// the tab-bar clearance, and the chrome that makes a page read as settings.
///
/// It was written out eight times. All eight copies agreed on every value — which
/// is precisely the argument for moving them, because agreement between copies is
/// enforced by nobody: a page that quietly lost `.settingsChrome()` or the gutter
/// would look perfectly fine on its own and only be wrong when held next to a
/// sibling. One definition makes that class of drift impossible rather than
/// unlikely.
///
/// Deliberately narrow. The pages that do NOT use it — the More hub, the
/// appearance page with its per-section panels, the about page with its extra top
/// inset — differ on purpose, and a component wide enough to absorb them would
/// carry a knob per caller and stop being a rule.
struct SettingsPage<Content: View>: View {
    @Environment(\.appearancePreferences) private var preferences
    /// Root pages name themselves in the header; pushed subpages already carry a
    /// title in the navigation bar.
    var title: String?

    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        headed
    }

    /// The two modifiers are independent, so the order between them is not a
    /// rendering question — but the copies disagreed about it anyway (five put
    /// chrome first, one put the header first), which is exactly the sort of
    /// thing an agreed shell should stop recording differently in each file.
    @ViewBuilder private var headed: some View {
        if let title {
            scroll.appPageHeader(title)
        } else {
            scroll
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(spacing: preferences.designStyle.sectionGap) {
                content
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .softScrollEdges()
        .settingsChrome()
    }
}

/// Shared icon treatment for settings and utility rows. The caller keeps
/// ownership of the meaning and action; this view only aligns the visual slot.
struct AppIconBadge: View {
    let symbol: String
    var tint: Color?

    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var preferences
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 17

    init(symbol: String, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    private var resolvedTint: Color {
        tint ?? Theme.accentText(palettes.style)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: min(glyphSize, Theme.Metrics.glyph - Theme.Metrics.gap), weight: .semibold))
            .foregroundStyle(preferences.designStyle.usesQuietSurfaces ? Color.primary : resolvedTint)
            .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
            .background(resolvedTint.opacity(preferences.designStyle.usesQuietSurfaces ? 0 : 0.11), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Layout-only settings row. Native controls stay in the trailing slot and
/// remain independently hit-testable; routing and persistence stay outside.
struct AppSettingsRow<Trailing: View>: View {
    @Environment(\.appearancePreferences) private var preferences
    let title: String
    let detail: String?
    let symbol: String?
    let showsChevron: Bool
    let trailing: Trailing

    init(title: String,
         detail: String? = nil,
         symbol: String? = nil,
         showsChevron: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.showsChevron = showsChevron
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Metrics.gap + 4) {
            if let symbol {
                AppIconBadge(symbol: symbol)
            }

            VStack(alignment: .leading, spacing: detail == nil ? 0 : 2) {
                Text(title)
                    .font(preferences.designStyle.rowTitleFont)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText(preferences: preferences))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: Theme.Metrics.gap)
            trailing

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity,
               minHeight: preferences.designStyle.settingsRowHeight,
               alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Grouped settings surface: one label, one panel, caller-owned rows and
/// dividers. Shared by the More hub and the non-List settings pages so a
/// sub-page looks like the hub instead of a stock iOS list.
///
/// This is the former `MoreView.moreHubGroup`, moved here unchanged. It now has
/// callers in more than one file, which is the bar the design system sets for a
/// shared component; before that it was private to MoreView.
struct AppSettingsGroup<Content: View>: View {
    @Environment(\.appearancePreferences) private var preferences
    let title: String
    /// Optional leading symbol. The hub's groups are text-only; the diagnostics
    /// page labels its groups with an SF Symbol. One component serves both
    /// rather than the page composing its own.
    var symbol: String?
    /// A line under the group that says what the group is for, or what a control
    /// inside it actually does. Lives here so a page does not hand-roll a
    /// caption in a different size and indent from every other one.
    var footer: String?
    /// Optional accessibility identifier for the group itself, so a test can
    /// address the panel a row sits in rather than only the row. That
    /// distinction is the whole point: a row renders identically with and without
    /// a panel around it, and only the frame says which one it got.
    var identifier: String?
    private let content: Content

    init(title: String,
         symbol: String? = nil,
         footer: String? = nil,
         identifier: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.footer = footer
        self.identifier = identifier
        self.content = content()
    }

    private var label: some View {
        Group {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .font(preferences.designStyle == .native ? .subheadline.weight(.semibold)
              : preferences.designStyle.sectionTitleFont)
        .foregroundStyle(Theme.secondaryText(preferences: preferences))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
                .padding(.horizontal, preferences.designStyle == .native ? 14 : preferences.designStyle.cardPadding)
            VStack(spacing: 0) { content }
                .padding(.horizontal, preferences.designStyle == .native ? 14 : preferences.designStyle.cardPadding)
                .padding(.vertical, preferences.designStyle.rowGap)
                .morePanel()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText(preferences: preferences))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, preferences.designStyle == .native ? 14 : preferences.designStyle.cardPadding)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Appearance-aware surface used by compact feedback above the tab bar.
struct AppToastSurface: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .appSurface(cornerRadius: dynamicTypeSize.isAccessibilitySize ? Theme.Metrics.cardRadius : 999)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

extension View {
    func appToastSurface() -> some View {
        modifier(AppToastSurface())
    }
}
