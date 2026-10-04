import ActivityKit
import WidgetKit
import SwiftUI

/// Die Live-Aktivität einer laufenden Habit-Session: Sperrbildschirm-Banner
/// und Dynamic Island (kompakt/minimal/erweitert).
///
/// **Keine tickenden Updates.** Die verstrichene Zeit rendert das System aus
/// `Text(timerInterval:)` bzw. `ProgressView(timerInterval:)` selbst — die
/// Anzeige läuft also auch, wenn App UND Extension längst suspendiert sind.
/// Die Uhr zählt immer hoch; mit geplanter Dauer ist nur der Balken begrenzt.
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
                    SessionIdentity(context: context)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionTimerText(context: context)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(SessionAccent.text(context, dark: true))
                        .frame(width: 88, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        SessionProgressBar(context: context)
                        SessionButtons(context: context)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(SessionAccent.text(context, dark: true))
            } compactTrailing: {
                SessionTimerText(context: context)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(SessionAccent.text(context, dark: true))
                    .frame(width: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(SessionAccent.text(context, dark: true))
            }
            .widgetURL(HaiityWidgetLink.habits)
            .keylineTint(SessionAccent.fill(context, dark: true))
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

private struct SessionIdentity: View {
    let context: ActivityViewContext<HabitActivityAttributes>

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !context.attributes.emoji.isEmpty {
                Text(verbatim: context.attributes.emoji)
                    .accessibilityHidden(true)
            }
            Text(verbatim: context.attributes.name)
                .font(.headline)
                .lineLimit(2)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.attributes.name)
    }
}

/// The system keeps counting elapsed time, including beyond the planned end.
private struct SessionTimerText: View {
    let context: ActivityViewContext<HabitActivityAttributes>

    var body: some View {
        Text(context.state.startedAt, style: .timer)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .privacySensitive()
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
                    .lineLimit(1)
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
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(SessionAccent.fill(context, dark: scheme == .dark))
            .accessibilityIdentifier("session-finish")
            Button(intent: CancelHabitSessionIntent()) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Abbrechen"))
            .accessibilityIdentifier("session-cancel")
        }
        .controlSize(.mini)
        .accessibilityElement(children: .contain)
    }
}

/// Identity and elapsed time have separate space; progress and actions follow.
private struct LockScreenSessionView: View {
    let context: ActivityViewContext<HabitActivityAttributes>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                SessionIdentity(context: context)
                SessionTimerText(context: context)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SessionAccent.text(context, dark: scheme == .dark))
                    .frame(width: 88, alignment: .trailing)
            }
            SessionProgressBar(context: context)
            SessionButtons(context: context)
        }
        .padding(14)
        .activityBackgroundTint(nil)
        .widgetURL(HaiityWidgetLink.habits)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-activity")
    }
}
