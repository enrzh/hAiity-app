import SwiftUI

struct DesignStylePicker: View {
    let selection: Binding<AppDesignStyle>

    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.palettes) private var palettes

    var body: some View {
        VStack(alignment: .leading, spacing: preferences.designStyle.cardPadding) {
            Text(String(localized: "Designstil"))
                .font(preferences.designStyle.sectionTitleFont)
            Text(String(localized: "Wähle das Layout für die ganze App."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                         spacing: preferences.designStyle.cardPadding,
                                                         alignment: .top),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                      alignment: .leading, spacing: preferences.designStyle.cardPadding) {
                ForEach(AppDesignStyle.allCases, id: \.self) { style in
                    Button {
                        guard selection.wrappedValue != style else { return }
                        Theme.Haptics.select()
                        selection.wrappedValue = style
                    } label: {
                        VStack(alignment: .leading, spacing: preferences.designStyle.rowGap) {
                            DesignStylePagePreview(preferences: preferences, style: style)
                                .dynamicTypeSize(.xSmall)
                                .accessibilityHidden(true)
                            HStack(alignment: .firstTextBaseline, spacing: preferences.designStyle.rowGap) {
                                Text(style.displayName)
                                    .font(preferences.designStyle.rowTitleFont)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if selection.wrappedValue == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(preferences.designStyle.rowTitleFont)
                                        .foregroundStyle(Theme.accentText(palettes.style))
                                }
                            }
                            Text(style.hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(preferences.designStyle.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appSurface(cornerRadius: preferences.designStyle.cardRadius)
                        .overlay {
                            if selection.wrappedValue == style {
                                RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius,
                                                 style: .continuous)
                                    .strokeBorder(Theme.accentText(palettes.style), lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(style.displayName)
                    .accessibilityHint(style.hint)
                    .accessibilityAddTraits(selection.wrappedValue == style ? .isSelected : [])
                    .accessibilityIdentifier("appearance-design-\(style.rawValue)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appearance-design-picker")
    }
}

/// A small live page: the same content and colors make the layout differences visible.
private struct DesignStylePagePreview: View {
    let preferences: AppearancePreferences
    let style: AppDesignStyle

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palettes) private var palettes

    private var previewPreferences: AppearancePreferences {
        var copy = preferences
        copy.designStyle = style
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.sectionGap / 3) {
            Text(String(localized: "Habits"))
                .font(style.compactTitleFont)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: style.rowGap + 4) {
                Text(String(localized: "Heute"))
                    .font(style.sectionTitleFont)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: 0.6)
                    .tint(Theme.accentText(palettes.style))
                Text(String(localized: "Lesen"))
                    .font(style.rowTitleFont)
                    .fixedSize(horizontal: false, vertical: true)
                contributionGrid
                    .padding(.vertical, style.graphPadding / 2)
            }
            .padding(style.cardPadding / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(cornerRadius: style.cardRadius)
            .padding(.vertical, style.cardOuterGap / 2)

            VStack(alignment: .leading, spacing: style.rowGap) {
                previewRow(String(localized: "Darstellung"), symbol: "paintpalette")
            }
            .padding(style.cardPadding / 2)
            .morePanel()
        }
        .padding(style.cardPadding / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AppearanceBackground(preferences: previewPreferences)
                .clipShape(RoundedRectangle(cornerRadius: style.cardRadius, style: .continuous))
        }
        .environment(\.appearancePreferences, previewPreferences)
        .allowsHitTesting(false)
    }

    private var contributionGrid: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { column in
                        RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                            .fill(Theme.level((row * 7 + column) % 5,
                                              dark: colorScheme == .dark, palette: palettes.style))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func previewRow(_ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.gap) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(style.rowTitleFont)
        .frame(minHeight: style.settingsRowHeight / 3, alignment: .leading)
    }
}
