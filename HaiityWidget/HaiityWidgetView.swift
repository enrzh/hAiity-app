import WidgetKit
import SwiftUI
import AppIntents

/// Ein Zeitpunkt im Widget-Verlauf: der Stand der aktiven Habits.
struct HaiityEntry: TimelineEntry {
    let date: Date
    let habits: [Habit]
}

/// Die Widget-Oberfläche. Klein: heutiger Status + Serie + Abhak-Button.
/// Mittel: Mini-Grid der letzten Wochen + Abhak-Button. Der Button feuert
/// CheckOffHabitIntent im Extension-Prozess; der schreibt über den
/// geteilten Store.
///
/// Bewusst zweigeteilt: `body` liest die Familie aus der Umgebung (so
/// arbeitet WidgetKit), `content(family:)` nimmt sie als Argument. Nur
/// dadurch lassen sich beide Größen außerhalb eines Widget-Prozesses
/// zeichnen und prüfen — `\.widgetFamily` ist von außen nicht setzbar.
struct HaiityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: HaiityEntry

    var body: some View {
        content(family: family)
            .containerBackground(for: .widget) { Color(.systemBackground) }
            .widgetURL(URL(string: "haiity://open"))
    }

    @ViewBuilder
    func content(family: WidgetFamily) -> some View {
        if let habit = entry.habits.first {
            switch family {
            case .systemMedium: medium(habit)
            default: small(habit)
            }
        } else {
            VStack(spacing: 4) {
                Text("hAiity").font(.headline)
                Text(String(localized: "Noch keine Habits")).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func small(_ habit: Habit) -> some View {
        let done = GoalEngine.dayCounts(habit: habit, day: DayKey.today())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if !habit.emoji.isEmpty { Text(habit.emoji) }
                Text(habit.name).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 4)
                checkButton(habit)
            }
            Spacer()
            Text(done
                 ? String(localized: "✓ Heute erledigt")
                 : String(localized: "Heute noch offen"))
                .font(.caption2)
                .foregroundStyle(done ? Theme.accentText : .secondary)
            Text("🔥 \(habit.streak())")
                .font(.title3.bold().monospacedDigit())
            miniGrid(habit, weeks: 8, cell: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !habit.emoji.isEmpty { Text(habit.emoji) }
                Text(habit.name).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text("🔥 \(habit.streak())").font(.subheadline.monospacedDigit())
                checkButton(habit)
            }
            miniGrid(habit, weeks: 16, cell: 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Abhak-Button: Checkbox-Habits zeigen ✓ (gefüllt, wenn der Tag
    /// zählt) und sind nur offen tippbar — der Intent ent-hakt nie.
    /// Mengen-Habits zeigen n/Ziel und zählen bei jedem Tipp weiter,
    /// auch über das Ziel hinaus.
    private func checkButton(_ habit: Habit) -> some View {
        let today = DayKey.today()
        let done = GoalEngine.dayCounts(habit: habit, day: today)
        return Button(intent: CheckOffHabitIntent(habit: habit)) {
            if let target = habit.goal.target {
                Text("\(habit.log[today] ?? 0)/\(target)")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(done ? Theme.accentFill : Color.secondary.opacity(0.25), in: Capsule())
                    .foregroundStyle(done ? .white : .primary)
            } else {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Theme.accentText : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(habit.goal.target == nil && done)
        .accessibilityLabel(String(localized: "Habit abhaken"))
    }

    /// Dasselbe Raster wie in der App, nur kleiner — inklusive gedimmter
    /// Zukunft, gecachter Berechnung und erzwungener Leserichtung. Keine
    /// Force-Unwraps: ein Widget, das beim Datumsrechnen abstürzt, zeigt
    /// dem Nutzer nur noch ein graues Rechteck.
    private func miniGrid(_ habit: Habit, weeks: Int, cell: CGFloat) -> some View {
        let snapshot = GridCalendar.snapshot(habit: habit, weeks: weeks, today: DayKey.today())
        return HStack(alignment: .top, spacing: 2) {
            ForEach(Array(snapshot.keys.enumerated()), id: \.offset) { wi, column in
                VStack(spacing: 2) {
                    ForEach(0..<GridCalendar.rows, id: \.self) { r in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Theme.level(snapshot.levels[wi][r], dark: scheme == .dark))
                            .opacity(column[r] == nil ? 0.35 : 1)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        // Chronologie nie spiegeln — wie im Contribution-Grid der App.
        .environment(\.layoutDirection, .leftToRight)
    }
}
