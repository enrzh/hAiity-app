import WidgetKit
import SwiftUI
import AppIntents

/// Widget liest dieselbe data.json aus dem App-Group-Container.
/// Klein: heutiger Status + Serie + Abhak-Button. Mittel: Mini-Grid der
/// letzten Wochen + Abhak-Button. Der Button feuert CheckOffHabitIntent
/// im Extension-Prozess; der schreibt über den geteilten Store.
struct HaiityEntry: TimelineEntry {
    let date: Date
    let habits: [Habit]
}

struct HaiityProvider: TimelineProvider {
    func placeholder(in context: Context) -> HaiityEntry {
        HaiityEntry(date: .now, habits: [demoHabit()])
    }

    func getSnapshot(in context: Context, completion: @escaping (HaiityEntry) -> Void) {
        completion(HaiityEntry(date: .now, habits: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HaiityEntry>) -> Void) {
        let entry = HaiityEntry(date: .now, habits: load())
        // Nächster Refresh: Mitternacht (der "heute"-Rahmen wandert).
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }

    /// Nur AKTIVE Habits — archivierte verschwinden auch aus dem Widget.
    private func load() -> [Habit] {
        HabitStore.read(SharedStorage.dataURL())?.habits.filter { $0.archivedAt == nil } ?? []
    }

    private func demoHabit() -> Habit {
        var h = Habit(name: "Lesen", emoji: "📖")
        for i in 0..<40 where i % 3 != 0 {
            if let k = DayKey.shifted(DayKey.today(), by: -i) { h.log[k] = 1 }
        }
        return h
    }
}

struct HaiityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: HaiityEntry

    var body: some View {
        Group {
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
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "haiity://open"))
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

    private func miniGrid(_ habit: Habit, weeks: Int, cell: CGFloat) -> some View {
        let cal = Calendar.current
        let now = Date()
        let dow = cal.component(.weekday, from: now) - 1
        let lastSat = cal.date(byAdding: .day, value: 6 - dow, to: now)!
        return HStack(alignment: .top, spacing: 2) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { r in
                        let offset = -(weeks * 7 - 1) + w * 7 + r
                        let d = cal.date(byAdding: .day, value: offset, to: lastSat)!
                        let key = DayKey.key(for: d)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(d > now
                                  ? Theme.level(0, dark: scheme == .dark).opacity(0.35)
                                  : Theme.level(habit.intensity(key), dark: scheme == .dark))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}

@main
struct HaiityWidgetBundle: WidgetBundle {
    var body: some Widget {
        HaiityWidget()
    }
}

struct HaiityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HaiityWidget", provider: HaiityProvider()) { entry in
            HaiityWidgetView(entry: entry)
        }
        .configurationDisplayName("hAiity")
        .description(String(localized: "Dein Habit-Graph auf dem Home-Bildschirm."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
