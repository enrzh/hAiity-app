import SwiftUI

struct TodayProgressView: View {
    let progress: ScheduledProgress.Today
    @Binding var todayOnly: Bool
    @Environment(\.palettes) private var palettes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.scheduled == 0
                     ? String(localized: "Heute keine festen Termine")
                     : String(localized: "\(progress.completed) von \(progress.scheduled) geplanten Habits erledigt"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if progress.scheduled > 0 {
                    ProgressView(value: progress.fraction)
                        .tint(Theme.accentFill(palettes.style))
                        .accessibilityHidden(true)
                }
                if progress.flexible > 0 {
                    Text(String(localized: "Flexible Ziele: \(progress.flexibleCompleted) von \(progress.flexible) in ihrer Periode erfüllt"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today-progress")

            Picker(String(localized: "Einträge anzeigen"), selection: $todayOnly) {
                Text(String(localized: "Heute")).tag(true)
                Text(String(localized: "Alle")).tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today-all-filter")
            .frame(minHeight: 44)
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.bottom, 16)
    }
}
