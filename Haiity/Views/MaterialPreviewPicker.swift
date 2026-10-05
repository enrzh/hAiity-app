import SwiftUI

/// A visual style board instead of a text-only material picker. The preview
/// uses the same surface modifier as the app, so the selection is explained by
/// appearance rather than by a paragraph of settings text.
struct MaterialPreviewPicker: View {
    let selection: Binding<AppearanceMaterial>

    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: preferences.designStyle.cardPadding) {
            AppearanceStylePreview(preferences: preferences,
                                   material: selection.wrappedValue)

            Text(String(localized: "Oberfläche"))
                .font(preferences.designStyle.sectionTitleFont)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(),
                                                         spacing: preferences.designStyle.cardPadding),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                      spacing: preferences.designStyle.cardPadding) {
                ForEach(AppearanceMaterial.allCases, id: \.self) { material in
                    MaterialOptionCard(preferences: preferences,
                                       material: material,
                                       isSelected: selection.wrappedValue == material) {
                        Theme.Haptics.select()
                        selection.wrappedValue = material
                    }
                    .accessibilityIdentifier("appearance-material-\(material.rawValue)")
                }
            }

            Text(selection.wrappedValue.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AppearanceStylePreview: View {
    let preferences: AppearancePreferences
    let material: AppearanceMaterial

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.palettes) private var palettes

    private var previewPreferences: AppearancePreferences {
        var copy = preferences
        copy.material = material
        return copy
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: preferences.designStyle.cardPadding) {
                    previewText
                    previewRamp
                }
            } else {
                HStack(spacing: preferences.designStyle.cardPadding) {
                    previewText
                    Spacer(minLength: preferences.designStyle.rowGap)
                    previewRamp
                }
            }
        }
        .padding(preferences.designStyle.cardPadding)
        .frame(maxWidth: .infinity,
               minHeight: preferences.designStyle.settingsRowHeight * 2, alignment: .leading)
        .appSurface(cornerRadius: preferences.designStyle.cardRadius)
        .background {
            AppearanceBackground(preferences: previewPreferences)
                .clipShape(RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius,
                                            style: .continuous))
        }
        .environment(\.appearancePreferences, previewPreferences)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Vorschau des ausgewählten Erscheinungsbilds"))
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: preferences.designStyle.rowGap) {
            Text(String(localized: "Heute"))
                .font(.caption.weight(.semibold))
            Text(String(localized: "Dein Fortschritt"))
                .font(preferences.designStyle.sectionTitleFont)
            Text(String(localized: "12 Tage Serie"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var previewRamp: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                    .fill(Theme.level(level, dark: colorScheme == .dark, palette: palettes.style))
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityHidden(true)
    }

}

private struct MaterialOptionCard: View {
    let preferences: AppearancePreferences
    let material: AppearanceMaterial
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palettes) private var palettes

    private static let rampPattern: [[Int]] = [
        [0, 1, 2],
        [1, 3, 4],
        [0, 2, 4]
    ]

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: preferences.designStyle.rowGap) {
                sampleSurface
                    .frame(maxWidth: .infinity)
                    .frame(height: preferences.designStyle.settingsRowHeight)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: preferences.designStyle.rowGap) {
                    Text(material.displayName)
                        .font(preferences.designStyle.rowTitleFont)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(preferences.designStyle.rowTitleFont)
                            .foregroundStyle(Theme.accentText(palettes.style))
                    }
                }
            }
            .padding(preferences.designStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(cornerRadius: preferences.designStyle.cardRadius)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius, style: .continuous)
                        .strokeBorder(Theme.accentText(palettes.style), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(material.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sampleSurface: some View {
        VStack(spacing: 3) {
            ForEach(Array(Self.rampPattern.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { level in
                        RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                            .fill(Theme.level(level, dark: colorScheme == .dark, palette: palettes.style))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(preferences.designStyle.cardPadding / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appSurface(cornerRadius: preferences.designStyle.cardRadius / 2)
        .environment(\.appearancePreferences, preferences.withMaterial(material))
    }
}

private extension AppearancePreferences {
    func withMaterial(_ material: AppearanceMaterial) -> Self {
        var copy = self
        copy.material = material
        copy.performanceMode = false
        return copy
    }
}
