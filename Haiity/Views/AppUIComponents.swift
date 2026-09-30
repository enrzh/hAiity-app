import SwiftUI

/// Shared icon treatment for settings and utility rows. The caller keeps
/// ownership of the meaning and action; this view only aligns the visual slot.
struct AppIconBadge: View {
    let symbol: String
    var tint: Color?

    @Environment(\.palettes) private var palettes

    init(symbol: String, tint: Color? = nil) {
        self.symbol = symbol
        self.tint = tint
    }

    private var resolvedTint: Color {
        tint ?? Theme.accentText(palettes.style)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(resolvedTint)
            .frame(width: Theme.Metrics.glyph, height: Theme.Metrics.glyph)
            .background(resolvedTint.opacity(0.11), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Layout-only settings row. Native controls stay in the trailing slot and
/// remain independently hit-testable; routing and persistence stay outside.
struct AppSettingsRow<Trailing: View>: View {
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
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
               minHeight: Theme.Metrics.settingsRowMinHeight,
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
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
                .padding(.horizontal, 14)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .morePanel()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Appearance-aware surface used by compact feedback above the tab bar.
struct AppToastSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .appSurface(cornerRadius: 999)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }
}

extension View {
    func appToastSurface() -> some View {
        modifier(AppToastSurface())
    }
}
