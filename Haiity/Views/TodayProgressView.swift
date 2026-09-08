import SwiftUI

struct TodayProgressView: View {
    let progress: ScheduledProgress.Today
    @Binding var todayOnly: Bool
    @Environment(\.palettes) private var palettes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Heute"))
                        .font(.title2.bold())
                    Spacer()
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
                ZStack {
                    ProgressView(value: Double(progress.completed),
                                 total: Double(progress.scheduled))
                        .tint(Theme.accentText(palettes.style))
                        .frame(height: 5)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Metrics.hit)
                .contentShape(Rectangle())
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
        .padding(.bottom, 8)
    }
}
