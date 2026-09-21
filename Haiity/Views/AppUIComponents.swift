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
