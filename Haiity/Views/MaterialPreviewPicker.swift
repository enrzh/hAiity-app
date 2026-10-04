import SwiftUI

/// A visual style board instead of a text-only material picker. The preview
/// uses the same surface modifier as the app, so the selection is explained by
/// appearance rather than by a paragraph of settings text.
struct MaterialPreviewPicker: View {
    let selection: Binding<AppearanceMaterial>

    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.gap + 2) {
            AppearanceStylePreview(preferences: preferences,
                                   material: selection.wrappedValue)

            Text(String(localized: "Oberfläche"))
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                      spacing: Theme.Metrics.gap) {
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

    private var previewPreferences: AppearancePreferences {
        var copy = preferences
        copy.material = material
        return copy
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Metrics.gap) {
                    previewText
                    previewRamp
                }
            } else {
                HStack(spacing: Theme.Metrics.gap) {
                    previewText
                    Spacer(minLength: Theme.Metrics.gap)
                    previewRamp
                }
            }
        }
        .padding(preferences.designStyle.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            AppearanceBackground(preferences: previewPreferences)
        }
        .environment(\.appearancePreferences, previewPreferences)
        .clipShape(RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: preferences.designStyle.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Vorschau des ausgewählten Erscheinungsbilds"))
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                    .fill(Theme.level(level, dark: colorScheme == .dark))
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

    private static let rampPattern: [[Int]] = [
        [0, 1, 2],
        [1, 3, 4],
        [0, 2, 4]
    ]

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                sampleSurface
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
                            .strokeBorder(isSelected
                                          ? Color.accentColor.opacity(0.9)
                                          : Color.primary.opacity(0.10),
                                          lineWidth: isSelected ? 1.5 : 0.5)
                    }

                HStack(spacing: 5) {
                    Text(material.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.45))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(isSelected ? 0.075 : 0.025),
                        in: RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous)
                    .strokeBorder(isSelected
                                  ? Color.accentColor.opacity(0.35)
                                  : Color.primary.opacity(0.06),
                                  lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .settingsRowSurface()
        .accessibilityLabel(material.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sampleSurface: some View {
        VStack(spacing: 3) {
            ForEach(Array(Self.rampPattern.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { level in
                        RoundedRectangle(cornerRadius: CornerRadius.pixel, style: .continuous)
                            .fill(Theme.level(level, dark: colorScheme == .dark))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.appearancePreferences, preferences.withMaterial(material))
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.control, style: .continuous)
                .fill(Color.accentColor.opacity(material == .solid ? 0.035 : 0.06))
                .allowsHitTesting(false)
        }
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
