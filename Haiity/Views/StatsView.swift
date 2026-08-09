import SwiftUI

/// Statistik: Gesamtkopf (Check-ins über ALLE Habits inkl. Archiv, Anzahl
/// aktiver Habits) plus eine Zeile pro aktivem Habit — Quoten 30/90/365,
/// Serien, Summe und 12 Monats-Balken. Die Mathematik liegt komplett in
/// StatsMath/GoalEngine (unit-getestet), hier wird nur gezeichnet.
struct StatsView: View {
    let store: HabitStore

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    statTile(value: "\(StatsMath.totalCheckIns(store.habits))",
                             label: String(localized: "Check-ins gesamt"))
                    statTile(value: "\(store.activeHabits.count)",
                             label: String(localized: "Aktive Habits"))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                ForEach(store.activeHabits) { habit in
                    StatsRow(habit: habit)
                }
            }
        }
        .navigationTitle(String(localized: "Statistik"))
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatsRow: View {
    let habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !habit.emoji.isEmpty { Text(habit.emoji) }
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("🔥 \(GoalEngine.streak(habit: habit))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                completionCell(days: 30)
                completionCell(days: 90)
                completionCell(days: 365)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(localized: "Best: \(GoalEngine.bestStreak(habit: habit))"))
                    Text(String(localized: "Gesamt: \(habit.checkInCount())"))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            MonthBars(counts: StatsMath.monthlyCounts(habit: habit, months: 12))
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("stats-row")
    }

    private func completionCell(days: Int) -> some View {
        let pct = Int((GoalEngine.completion(habit: habit, lastNDays: days) * 100).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(pct) %")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(String(localized: "\(days) Tage"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 12 dünne Kapseln, eine pro Monat (älteste links), Höhe relativ zum
/// stärksten Monat — bewusst ohne Beschriftung, ein Mini-Sparkline.
private struct MonthBars: View {
    let counts: [Int]
    @Environment(\.palettes) private var palettes

    var body: some View {
        let peak = max(counts.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(count > 0 ? Theme.accent(palettes.style) : Color(.tertiarySystemFill))
                    .frame(width: 5, height: max(4, 34 * CGFloat(count) / CGFloat(peak)))
            }
        }
        .frame(height: 36, alignment: .bottom)
        // Chronologie nie spiegeln — wie beim Contribution-Grid.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Check-ins der letzten 12 Monate: \(counts.reduce(0, +))"))
    }
}
