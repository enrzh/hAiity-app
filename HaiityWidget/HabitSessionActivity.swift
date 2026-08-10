import ActivityKit
import WidgetKit
import SwiftUI

/// Die Live-Aktivität einer laufenden Habit-Session: Sperrbildschirm-Banner
/// und Dynamic Island (kompakt/minimal/erweitert).
///
/// **Keine tickenden Updates.** Die verstrichene Zeit rendert das System aus
/// `Text(timerInterval:)` bzw. `ProgressView(timerInterval:)` selbst — die
/// Anzeige läuft also auch, wenn App UND Extension längst suspendiert sind.
/// Mit geplanter Dauer zählt die Uhr HERUNTER und der Balken füllt sich;
/// ohne („limitless") zählt sie schlicht hoch.
///
/// Die Knöpfe feuern `LiveActivityIntent`s, deren `perform()` im App-Prozess
/// läuft: „Fertig" hakt den Tag über den normalen Trichter ab und schreibt
/// die tatsächlichen Minuten, „✕" verwirft die Session.
struct HabitSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitActivityAttributes.self) { context in
            LockScreenSessionView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.emoji.isEmpty ? "⏱" : context.attributes.emoji)
                        Text(context.attributes.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionTimerText(context: context)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(SessionAccent.text(context, dark: true))
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        SessionProgressBar(context: context)
                        SessionButtons(context: context)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text(context.attributes.emoji.isEmpty ? "⏱" : context.attributes.emoji)
            } compactTrailing: {
                SessionTimerText(context: context)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(SessionAccent.text(context, dark: true))
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(SessionAccent.text(context, dark: true))
            }
        }
    }

}

/// Akzentfarbe nach dem Schema des SPERRBILDSCHIRMS (nicht der App).
private struct SessionAccent {
    static func text(_ context: ActivityViewContext<HabitActivityAttributes>, dark: Bool) -> Color {
        Theme.color(context.attributes.accentText(dark: dark))
    }
    static func fill(_ context: ActivityViewContext<HabitActivityAttributes>, dark: Bool) -> Color {
        Theme.color(context.attributes.accentFill(dark: dark))
    }
}

// MARK: – Bausteine

/// Die laufende Uhr. Countdown gegen den Plan, sonst Zähler ab Start.
private struct SessionTimerText: View {
    let context: ActivityViewContext<HabitActivityAttributes>

    var body: some View {
        if let end = HabitSessionMath.plannedEnd(startedAt: context.state.startedAt,
                                                 plannedMinutes: context.attributes.plannedMinutes) {
            Text(timerInterval: context.state.startedAt...end, countsDown: true)
                .multilineTextAlignment(.trailing)
        } else {
            Text(context.state.startedAt, style: .timer)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Der Fortschritt gegen den Plan — nur, wenn es einen gibt. Auch er läuft
/// ohne Updates: das Intervall füllt sich systemseitig.
private struct SessionProgressBar: View {
    let context: ActivityViewContext<HabitActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let planned = context.attributes.plannedMinutes,
           let end = HabitSessionMath.plannedEnd(startedAt: context.state.startedAt,
                                                 plannedMinutes: planned) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(timerInterval: context.state.startedAt...end,
                             countsDown: false, label: { EmptyView() },
                             currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear)
                        .tint(SessionAccent.fill(context, dark: scheme == .dark))
                Text(String(localized: "Geplant: \(HabitSessionMath.durationText(minutes: planned))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Fertig + Abbrechen. „Fertig" trägt die Akzentfarbe des Habits — derselbe
/// Grünton (oder die eigene Palette), in dem seine Zellen leuchten.
private struct SessionButtons: View {
    let context: ActivityViewContext<HabitActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: FinishHabitSessionIntent()) {
                Label(String(localized: "Fertig"), systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SessionAccent.fill(context, dark: scheme == .dark))
            Button(intent: CancelHabitSessionIntent()) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Das Banner auf dem Sperrbildschirm: Kopfzeile wie die Habit-Karte
/// (Emoji, Name, Uhr rechts), darunter Fortschritt und die beiden Knöpfe.
private struct LockScreenSessionView: View {
    let context: ActivityViewContext<HabitActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !context.attributes.emoji.isEmpty {
                    Text(context.attributes.emoji).font(.title3)
                }
                Text(context.attributes.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                SessionTimerText(context: context)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SessionAccent.text(context, dark: scheme == .dark))
                    .frame(maxWidth: 80)
            }
            SessionProgressBar(context: context)
            SessionButtons(context: context)
        }
        .padding(14)
        .activityBackgroundTint(nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-activity")
    }
}
