import SwiftUI

struct TodayView<Row: View>: View {
    enum SectionKind: Equatable { case scheduled, reminders, flexible, resolved }

    struct VisitOrder {
        var ids: [UUID] = []
        var sections: [UUID: SectionKind] = [:]

        mutating func regroup(_ items: [(UUID, SectionKind)]) {
            ids = items.map { $0.0 }
            sections = Dictionary(uniqueKeysWithValues: items)
        }

        mutating func reconcile(_ items: [(UUID, SectionKind)]) {
            let current = Set(items.map { $0.0 })
            ids.removeAll { !current.contains($0) }
            sections = sections.filter { current.contains($0.key) }
            for (id, section) in items where sections[id] == nil {
                ids.append(id)
                sections[id] = section
            }
        }
    }

    let habits: [Habit]
    let defaultTimeZoneIdentifier: String?
    let now: Date
    let isActive: Bool
    let onCreate: () -> Void
    let onOpenHabits: () -> Void
    @ViewBuilder let row: (Habit) -> Row
    @Environment(\.appearancePreferences) private var preferences
    @State private var visit = VisitOrder()
    @State private var showResolved = false
    @State private var scrolling = false
    @State private var pendingRegroup = false
    @State private var pendingReconcile = false
    @GestureState private var touching = false
    private var style: AppDesignStyle { preferences.designStyle }

    static func section(for habit: Habit, now: Date, calendar: Calendar) -> SectionKind? {
        guard habit.archivedAt == nil else { return nil }
        let day = DayKey.key(for: now, calendar: calendar)
        if habit.isReminder {
            let state = ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
            if state.isChecked(now: now, calendar: calendar), state.mostRecentCompleted?.day == day {
                return .resolved
            }
            guard let occurrence = state.actionable, occurrence.day <= day else { return nil }
            return .reminders
        }
        guard GoalEngine.isScheduled(habit: habit, day: day, calendar: calendar) else { return nil }
        if habit.recurrence.isFlexible {
            return GoalEngine.periodSatisfied(habit: habit, day: day, today: day, calendar: calendar) ? .resolved : .flexible
        }
        return GoalEngine.dayCounts(habit: habit, day: day, calendar: calendar) || habit.isDeclined(day) ? .resolved : .scheduled
    }

    private var classified: [(UUID, SectionKind)] {
        habits.compactMap { habit in
            let calendar = HabitTimeZone.calendar(for: habit, defaultIdentifier: defaultTimeZoneIdentifier)
            return Self.section(for: habit, now: now, calendar: calendar).map { (habit.id, $0) }
        }
    }
    private var boundary: [String] {
        habits.map { DayKey.key(for: now, calendar: HabitTimeZone.calendar(for: $0, defaultIdentifier: defaultTimeZoneIdentifier)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: style.sectionGap) {
                VStack(alignment: .leading, spacing: style.rowGap) {
                    Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline).foregroundStyle(.primary)
                    TodayProgressView(progress: ScheduledProgress.today(habits: habits,
                        defaultTimeZoneIdentifier: defaultTimeZoneIdentifier, now: now))
                }
                if habits.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "Noch keine Habits"), systemImage: "square.grid.3x3")
                    } description: {
                        Text(String(localized: "Lege deinen ersten Eintrag an und hake ihn ab, damit dein Raster sichtbar wächst."))
                    } actions: {
                        Button(String(localized: "Ersten Habit anlegen"), action: onCreate)
                            .frame(minHeight: Theme.Metrics.hit).accessibilityIdentifier("add-first-habit")
                    }
                } else if visit.ids.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "Heute nichts fällig"), systemImage: "sun.max")
                    } actions: {
                        Button(String(localized: "Habits"), action: onOpenHabits).frame(minHeight: Theme.Metrics.hit)
                    }
                }
                section(.scheduled, title: String(localized: "Fällig heute"))
                section(.reminders, title: String(localized: "Erinnerungen"))
                section(.flexible, title: String(localized: "Flexible Ziele"))
                if !items(in: .resolved).isEmpty {
                    DisclosureGroup(isExpanded: $showResolved) {
                        rows(items(in: .resolved))
                    } label: {
                        Text(String(localized: "Abgeschlossen und beantwortet (\(items(in: .resolved).count))"))
                            .font(style.sectionTitleFont).fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: Theme.Metrics.hit)
                            .accessibilityIdentifier("today-resolved")
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.floatingControlsClearance)
            .frame(maxWidth: Theme.Metrics.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("today-list")
        .softScrollEdges()
        .simultaneousGesture(DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true })
        .onScrollPhaseChange { _, phase in
            scrolling = phase != .idle
            if !scrolling { regroupIfIdle() }
        }
        .refreshable { visit.regroup(classified) }
        .onAppear { visit.regroup(classified) }
        .onChange(of: isActive) { _, active in if active { visit.regroup(classified) } }
        .onChange(of: classified.map { $0.0 }) { _, _ in
            if touching || scrolling { pendingReconcile = true }
            else { visit.reconcile(classified) }
        }
        .onChange(of: boundary) { _, _ in pendingRegroup = true; regroupIfIdle() }
        .onChange(of: touching) { _, active in if !active { regroupIfIdle() } }
    }

    private func regroupIfIdle() {
        guard !touching, !scrolling else { return }
        if pendingRegroup { visit.regroup(classified) }
        else if pendingReconcile { visit.reconcile(classified) }
        pendingRegroup = false
        pendingReconcile = false
    }
    private func items(in section: SectionKind) -> [Habit] {
        let live = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        return visit.ids.filter { visit.sections[$0] == section }.compactMap { live[$0] }
    }
    @ViewBuilder private func section(_ kind: SectionKind, title: String) -> some View {
        let items = items(in: kind)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: style.rowGap) {
                Text(title).font(style.sectionTitleFont).accessibilityAddTraits(.isHeader)
                rows(items)
            }
        }
    }
    private func rows(_ items: [Habit]) -> some View {
        ForEach(items) { habit in row(habit).id(habit.id) }
    }
}
