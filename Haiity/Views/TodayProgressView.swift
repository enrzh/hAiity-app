import SwiftUI

struct TodayProgressView: View {
    let progress: ScheduledProgress.Today
    @Binding var todayOnly: Bool
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    var body: some View {
        VStack(alignment: .leading, spacing: designStyle.cardPadding) {
            VStack(alignment: .leading, spacing: designStyle.rowGap) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(String(localized: "Heute"))
                        .font(designStyle == .native ? .title2.bold() : designStyle.sectionTitleFont)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text("\(progress.completed)/\(progress.scheduled)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(progress.scheduled == 0
                            ? String(localized: "Heute keine festen Termine")
                            : String(localized: "\(progress.completed) von \(progress.scheduled) geplanten Habits erledigt"))
                }
                if progress.flexible > 0 {
                    Text(String(localized: "Flexible Ziele: \(progress.flexibleCompleted) von \(progress.flexible) in ihrer Periode erfüllt"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-progress")

            if progress.scheduled > 0 {
                ProgressView(value: Double(progress.completed),
                             total: Double(progress.scheduled))
                .tint(Theme.accentText(palettes.style))
                .frame(height: 5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Fortschritt heute"))
                .accessibilityValue(String(localized: "\(progress.completed) von \(progress.scheduled) erledigt"))
                .accessibilityIdentifier("today-progress-bar")
            }

            Picker(String(localized: "Einträge anzeigen"), selection: $todayOnly) {
                Text(String(localized: "Heute")).tag(true)
                Text(String(localized: "Alle")).tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today-all-filter")
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, designStyle.rowGap * 2)
    }
}
