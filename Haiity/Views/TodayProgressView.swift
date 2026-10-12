import SwiftUI

struct TodayProgressView: View {
    let progress: ScheduledProgress.Today
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var appearancePreferences

    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    var body: some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            Text(progress.scheduled == 0
                ? String(localized: "Heute keine festen Termine")
                : String(localized: "\(progress.completed) von \(progress.scheduled) geplanten Habits erledigt"))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today-progress")

            if progress.flexible > 0 {
                Text(String(localized: "Flexible Ziele: \(progress.flexibleCompleted) von \(progress.flexible) in ihrer Periode erfüllt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if progress.scheduled > 0 {
                ProgressView(value: Double(progress.completed),
                             total: Double(progress.scheduled))
                .tint(Theme.accentText(palettes.style))
                .frame(height: 5)
                .accessibilityIdentifier("today-progress-bar")
                .accessibilityHidden(true)
            }

        }
        .padding(.bottom, designStyle.rowGap * 2)
    }
}
