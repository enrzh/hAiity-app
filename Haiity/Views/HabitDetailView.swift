import SwiftUI

struct HabitDetailView: View {
    let store: HabitStore
    let habitID: UUID
    let now: Date
    let onEdit: (UUID) -> Void
    let onHistory: (UUID) -> Void
    let onToggleDay: (UUID, String) -> Void
    let onIncrement: (UUID) -> Void
    let onAnswer: (UUID, Bool) -> Void
    let onToggleReminder: (UUID) -> Void
    let onArchive: (UUID) -> Void
    let onDelete: (UUID) -> Void
    var allowsArchived = false
    var onRestore: ((UUID) -> Void)? = nil
    var onOpenCalendar: (() -> Void)? = nil
    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.palettes) private var palettes
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var graphWidth: CGFloat = 0
    @State private var proStatus = ProStatus.shared
    @State private var rendered: (key: GridCalendar.HabitSnapshotKey, habit: Habit, snapshot: GridCalendar.Snapshot)?
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 100

    var currentHabit: Habit? {
        if allowsArchived { return store.habits.first { $0.id == habitID } }
        _ = proStatus.unlocked
        return ProGate.visibleActiveHabits(store.activeHabits, unlocked: Pro.isUnlocked)
            .first { $0.id == habitID }
    }

    private func calendarDestination(_ habit: Habit) -> String {
        guard habit.calendarSyncEnabled else { return String(localized: "Aus") }
        let calendarEnabled = habit.isReminder ? CalendarSync.syncReminders : CalendarSync.syncHabits
        if calendarEnabled {
            return CalendarSync.activeCalendarTitle(isReminder: habit.isReminder)
                ?? CalendarSync.destinationTitle(isReminder: habit.isReminder)
        }
        if habit.isReminder && ReminderSync.isEnabled { return "hAiity Reminders" }
        return String(localized: "Aus")
    }

    var body: some View {
        Group {
            if let habit = currentHabit {
                content(habit)
                    .toolbar {
                        if !allowsArchived { ToolbarItem(placement: .topBarTrailing) {
                            Button { if currentHabit != nil { onEdit(habitID) } } label: {
                                Text(String(localized: "Bearbeiten")).font(.body)
                                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                            }
                                .accessibilityIdentifier("edit-habit")
                        }
                        }
                    }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "Eintrag nicht verfügbar"), systemImage: "questionmark.folder")
                } actions: {
                    Button(String(localized: "Zurück")) { dismiss() }.frame(minHeight: Theme.Metrics.hit)
                }
                .accessibilityIdentifier("item-unavailable")
            }
        }
        .navigationTitle(String(localized: "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("habit-detail")
        .onChange(of: currentHabit?.archivedAt) { old, new in
            if allowsArchived, old != nil, new == nil, currentHabit != nil { dismiss() }
        }
    }

    private func content(_ habit: Habit) -> some View {
        let calendar = HabitTimeZone.calendar(for: habit, defaultIdentifier: store.defaultTimeZoneIdentifier)
        let day = DayKey.key(for: now, calendar: calendar)
        let metrics = ContributionChart.bandMetrics(width: graphWidth)
        let request = GridCalendar.HabitSnapshotKey(habit: habit, weeks: metrics.weeks, today: day, calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: preferences.designStyle.sectionGap) {
                VStack(alignment: .leading, spacing: preferences.designStyle.rowGap) {
                    Text(habit.name).font(preferences.designStyle.sectionTitleFont)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text(RecurrenceText.summary(habit.recurrence, timeMinutes: habit.timeMinutes, calendar: calendar))
                        .font(.subheadline).foregroundStyle(Theme.secondaryText(preferences: preferences))
                    if allowsArchived {
                        Text(String(localized: "Archiv")).font(.subheadline)
                        Button(String(localized: "Wiederherstellen")) { onRestore?(habitID) }
                            .frame(minHeight: Theme.Metrics.hit).accessibilityIdentifier("unarchive-habit")
                    } else if habit.isReminder {
                        reminderActions(habit, calendar: calendar)
                    } else {
                        HabitActionControls(habit: habit, calendar: calendar, now: now,
                            onToggleDay: { onToggleDay(habitID, $0) },
                            onIncrement: { onIncrement(habitID) }, onAnswer: { onAnswer(habitID, $0) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(preferences.designStyle.cardPadding).appSurface()

                if habit.isTrackedHabit {
                    AppSettingsGroup(title: String(localized: "Historie")) {
                        recentGraph(habit, request: request, calendar: calendar)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { graphWidth = $0 }
                        if !allowsArchived { Button { onHistory(habitID) } label: {
                            AppSettingsRow(title: String(localized: "Historie"), symbol: "calendar", showsChevron: true) {}
                        }.buttonStyle(.plain).accessibilityIdentifier("open-habit-history")
                        }
                        if let rendered, rendered.key.canDisplaySnapshot(for: request), rendered.snapshot.streak > 0 {
                            AppSettingsRow(title: String(localized: "Serie"), symbol: "flame") {
                                Text("\(rendered.snapshot.streak)").monospacedDigit()
                            }
                        }
                    }
                }
                AppSettingsGroup(title: String(localized: "Wiederholung")) {
                    AppSettingsRow(title: RecurrenceText.summary(habit.recurrence, timeMinutes: habit.timeMinutes, calendar: calendar), symbol: "calendar") {}
                    AppSettingsRow(title: String(localized: "Zeitzone"), detail: calendar.timeZone.localizedName(for: .generic, locale: .current) ?? calendar.timeZone.identifier, symbol: "globe") {}
                }
                AppSettingsGroup(title: String(localized: "Mitteilungen")) {
                    AppSettingsRow(title: EditHabitSheet.notificationPreview(mode: habit.notificationMode,
                        times: habit.effectiveNotificationTimes, calendar: calendar),
                        detail: habit.notificationTimes == nil ? String(localized: "Zeiten folgen dem Termin") : nil,
                        symbol: "bell") {}
                }
                if !allowsArchived, let onOpenCalendar {
                    Button(action: onOpenCalendar) {
                        AppSettingsRow(title: String(localized: "Kalender & Erinnerungen"),
                            detail: calendarDestination(habit), symbol: "calendar", showsChevron: true) {}
                    }.buttonStyle(.plain).accessibilityIdentifier("detail-calendar")
                }
                AppSettingsGroup(title: String(localized: "Mehr")) {
                    if habit.isTrackedHabit && !allowsArchived {
                        Button { if let current = currentHabit { HabitSessionManager.shared.start(habit: current) } } label: {
                            AppSettingsRow(title: String(localized: "Session starten"), symbol: "timer") {}
                        }.buttonStyle(.plain)
                        ShareLink(item: HabitShareImage(habit: habit, dark: scheme == .dark, palette: palettes.style(for: habit)), preview: SharePreview(habit.name)) {
                            AppSettingsRow(title: String(localized: "Als Bild teilen"), symbol: "square.and.arrow.up") {}
                        }.buttonStyle(.plain)
                    }
                    if !allowsArchived { Button { if currentHabit != nil { onArchive(habitID) } } label: {
                        AppSettingsRow(title: String(localized: "Archivieren"), symbol: "archivebox") {}
                    }.buttonStyle(.plain)
                    }
                    Button(role: .destructive) { if currentHabit != nil { onDelete(habitID) } } label: {
                        AppSettingsRow(title: String(localized: "Löschen"), symbol: "trash") {}
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.floatingControlsClearance)
            .frame(maxWidth: Theme.Metrics.readableContentWidth).frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        .task(id: request) {
            guard habit.isTrackedHabit, graphWidth > 0 else { return }
            if let cached = GridCalendar.cachedSnapshot(habit: habit, weeks: request.weeks, today: request.today, calendar: request.calendar) {
                rendered = (request, habit, cached)
            } else if let snapshot = await ContributionSnapshotScheduler.perform({
                GridCalendar.snapshot(habit: habit, weeks: request.weeks, today: request.today, calendar: request.calendar)
            }), !Task.isCancelled {
                rendered = (request, habit, snapshot)
            }
        }
    }

    @ViewBuilder private func recentGraph(_ habit: Habit, request: GridCalendar.HabitSnapshotKey, calendar: Calendar) -> some View {
        let metrics = ContributionChart.bandMetrics(width: graphWidth)
        if let rendered, rendered.key.canDisplaySnapshot(for: request) {
            let snapshot = HabitCard.currentDaySnapshot(rendered.snapshot, previous: rendered.habit, habit: habit, calendar: calendar)
            ContributionChart(snapshot: snapshot,
                cell: metrics.cell, gap: GridCell.gap, width: graphWidth,
                showsMonthLabels: true, labelScale: labelScale / 100, palette: palettes.style(for: habit),
                highlightsToday: true, checkPulse: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: String(localized: "%@: %lld Tage in den letzten %lld Wochen."),
                    habit.name, snapshot.filledCount, request.weeks))
        } else {
            Color.clear.frame(height: 7 * metrics.cell + 6 * GridCell.gap + 24)
                .accessibilityLabel(String(localized: "Wird geladen"))
        }
    }

    private func reminderActions(_ habit: Habit, calendar: Calendar) -> some View {
        let state = ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: preferences.designStyle.rowGap) {
            if let occurrence = state.actionable {
                Text(ReminderOccurrenceText.label(for: occurrence,
                    includesTime: Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) != nil,
                    now: now, calendar: calendar)).font(.subheadline)
                if state.overdueCount > 1 { Text(String(localized: "Noch \(state.overdueCount) offen")).font(.subheadline) }
            }
            Button { onToggleReminder(habitID) } label: {
                Label(String(localized: "Erledigt"), systemImage: state.isChecked(now: now, calendar: calendar) ? "checkmark.circle.fill" : "circle")
                    .frame(minHeight: Theme.Metrics.hit).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("reminder-check-\(habitID.uuidString)")
        }
    }
}
