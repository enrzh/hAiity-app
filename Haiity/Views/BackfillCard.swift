import SwiftUI

/// A month of editable entries. Writes still pass through ContentView's
/// validation and persistence path; selection itself never changes a log.
struct BackfillCard: View {
    let habit: Habit
    @Binding var day: String
    let onWrite: ([String], Int?) -> Void
    let onRestore: ([(day: String, value: Int?)]) -> Void
    let onClose: () -> Void
    var sourceAnchor: UnitPoint = .center

    @State private var selected: Set<String> = []
    @State private var selecting = false
    @State private var visibleMonth = Date()
    @State private var amount = 1
    @State private var missingOnly = false
    @State private var undoStack: [[(day: String, value: Int?)]] = []
    @Environment(\.calendar) private var calendar
    @Environment(\.palettes) private var palettes
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearancePreferences) private var appearancePreferences

    // Retained for existing layout clients; the editor now uses a native sheet.
    static let maxWidth: CGFloat = 360
    static func contentWidth(window: CGFloat) -> CGFloat {
        max(0, min(maxWidth, window - 2 * Theme.Metrics.gutter) - 2 * Theme.Metrics.gutter)
    }

    private var today: String { DayKey.today(calendar: calendar) }
    private var range: ClosedRange<Date> {
        Backfill.dateRange(habit: habit, today: today, calendar: calendar)
    }
    private var monthDays: [String] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let count = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let allowedRange = range
        return count.compactMap { number in
            guard let date = calendar.date(byAdding: .day, value: number - 1, to: interval.start),
                  allowedRange.contains(date) else { return nil }
            return DayKey.key(for: date, calendar: calendar)
        }.reversed()
    }
    private var visibleDays: [String] {
        missingOnly ? monthDays.filter { habit.log[$0] == nil } : monthDays
    }
    private var missingDays: [String] {
        Backfill.selectableMissingDays(habit: habit,
                                       days: monthDays,
                                       today: today,
                                       calendar: calendar)
    }
    private var actions: [Backfill.Action] {
        Backfill.selectActions(habit: habit, amount: amount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthNavigation
                monthPreview
                selectionTools
                monthGrid
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { editorActions }
            }
            .background(Color(.systemBackground))
            .navigationTitle(habit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: undo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)
                    .accessibilityLabel(String(localized: "Rückgängig"))
                    .accessibilityIdentifier("history-undo")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig"), action: onClose)
                        .accessibilityIdentifier("backfill-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("backfill-card")
        .onAppear {
            let initial = DayKey.date(from: day, calendar: calendar) ?? range.upperBound
            visibleMonth = min(max(initial, range.lowerBound), range.upperBound)
            amount = max(1, habit.recurrence.target ?? 1)
        }
    }

    private var monthNavigation: some View {
        HStack(spacing: 12) {
            monthButton(-1, symbol: "chevron.left")
            Spacer(minLength: 0)
            Menu {
                ForEach(years.reversed(), id: \.self) { year in
                    Menu(String(year)) {
                        ForEach(months(in: year), id: \.self) { month in
                            Button(month.formatted(.dateTime.month(.wide))) {
                                visibleMonth = month
                                selected.removeAll()
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(visibleMonth, format: .dateTime.month(.wide).year())
                        .font(.headline)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("history-jump-date")
            Spacer(minLength: 0)
            monthButton(1, symbol: "chevron.right")
        }
        .padding(.horizontal, 20)
        .padding(.top, 0)
    }

    private var monthPreview: some View {
        HistoryMonthPreview(snapshot: monthPreviewSnapshot,
                            filledCount: monthFilledCount,
                            totalDays: monthTotalDays,
                            highlightedCells: monthPreviewHighlightCells,
                            palette: Theme.adaptivePalette(palettes.style(for: habit),
                                                           preferences: appearancePreferences,
                                                           dark: scheme == .dark))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .accessibilityIdentifier("history-month-preview")
    }

    private static let previewWeeks = 24

    private var monthFilledCount: Int {
        monthDays.filter { GoalEngine.dayCounts(habit: habit, day: $0, calendar: calendar) }.count
    }

    /// Keep the selected month centered in a compact, habit-style window.
    /// The editor below remains the precise month view; this graph provides
    /// context without changing the shared contribution geometry.
    private var monthPreviewLayout: Date? {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return nil }
        let monthStart = calendar.startOfDay(for: interval.start)
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? monthStart
        let firstWeek = previewWeekStart(for: monthStart)
        let lastWeek = previewWeekStart(for: monthEnd)
        let daySpan = calendar.dateComponents([.day], from: firstWeek, to: lastWeek).day ?? 0
        let monthWeeks = max(1, daySpan / GridCalendar.rows + 1)
        let leadingWeeks = max(0, (Self.previewWeeks - monthWeeks) / 2)
        guard let start = calendar.date(byAdding: .day,
                                        value: -leadingWeeks * GridCalendar.rows,
                                        to: firstWeek) else { return nil }
        return start
    }

    private var monthPreviewHighlightCells: Set<ContributionHighlightCell> {
        guard let layout = monthPreviewLayout,
              let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let days = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let monthStart = calendar.startOfDay(for: interval.start)
        return Set(days.compactMap { number in
            guard let date = calendar.date(byAdding: .day, value: number - 1, to: monthStart),
                  let offset = calendar.dateComponents([.day], from: layout, to: date).day,
                  offset >= 0,
                  offset < Self.previewWeeks * GridCalendar.rows else { return nil }
            return ContributionHighlightCell(column: offset / GridCalendar.rows,
                                             row: offset % GridCalendar.rows)
        })
    }

    private func previewWeekStart(for date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) - 1
        return calendar.date(byAdding: .day, value: -weekday, to: day) ?? day
    }

    private var monthPreviewSnapshot: GridCalendar.Snapshot {
        guard let layout = monthPreviewLayout else {
            return GridCalendar.Snapshot(weeks: 0, today: today, keys: [], levels: [],
                                         marks: [], filledCount: 0)
        }
        let keys = (0..<Self.previewWeeks).map { week in
            (0..<GridCalendar.rows).map { weekday -> String? in
                let offset = week * GridCalendar.rows + weekday
                guard let date = calendar.date(byAdding: .day, value: offset, to: layout) else {
                    return nil
                }
                let key = DayKey.key(for: date, calendar: calendar)
                guard key <= today,
                      Backfill.canWrite(habit: habit, day: key,
                                        today: today, calendar: calendar) else { return nil }
                return key
            }
        }
        let levels = keys.map { column in
            column.map { key in
                key.map { GoalEngine.intensity(habit: habit, key: $0, calendar: calendar) } ?? 0
            }
        }
        let filled = keys.flatMap { $0 }.compactMap { $0 }
            .filter { GoalEngine.dayCounts(habit: habit, day: $0, calendar: calendar) }
            .count
        return GridCalendar.Snapshot(weeks: Self.previewWeeks, today: today, keys: keys,
                                     levels: levels, marks: [], filledCount: filled)
    }

    private var monthTotalDays: Int {
        calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
    }

    private var monthGridDays: [String?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let days = calendar.range(of: .day, in: .month, for: visibleMonth) else {
            return []
        }
        let start = calendar.startOfDay(for: interval.start)
        let leading = calendar.component(.weekday, from: start) - 1
        let weekCount = (leading + days.count + GridCalendar.rows - 1) / GridCalendar.rows
        return (0..<(weekCount * GridCalendar.rows)).map { slot in
            let offset = slot - leading
            guard days.contains(offset + 1),
                  let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return DayKey.key(for: date, calendar: calendar)
        }
    }

    private var monthGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(0..<GridCalendar.rows, id: \.self) { weekday in
                        Text(calendar.veryShortWeekdaySymbols[weekday])
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                         count: GridCalendar.rows), spacing: 6) {
                    ForEach(Array(monthGridDays.enumerated()), id: \.offset) { _, key in
                        monthDayCell(key)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, selecting ? 12 : 24)
        }
        .accessibilityIdentifier("history-entries")
    }

    private func adjacentMonth(_ offset: Int) -> Date? {
        guard let start = calendar.dateInterval(of: .month, for: visibleMonth)?.start,
              let date = calendar.date(byAdding: .month, value: offset, to: start),
              let interval = calendar.dateInterval(of: .month, for: date),
              interval.end > range.lowerBound, interval.start <= range.upperBound else { return nil }
        return max(date, range.lowerBound)
    }

    private var years: [Int] {
        Array(calendar.component(.year, from: range.lowerBound)...calendar.component(.year, from: range.upperBound))
    }

    private func months(in year: Int) -> [Date] {
        (1...12).compactMap { month in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let interval = calendar.dateInterval(of: .month, for: date),
                  interval.end > range.lowerBound, date <= range.upperBound else { return nil }
            return max(date, range.lowerBound)
        }
    }

    private func monthButton(_ offset: Int, symbol: String) -> some View {
        Button {
            guard let date = adjacentMonth(offset) else { return }
            visibleMonth = date
            selected.removeAll()
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
        }
        .disabled(adjacentMonth(offset) == nil)
        .accessibilityLabel(offset < 0 ? String(localized: "Vorheriger Monat") : String(localized: "Nächster Monat"))
        .accessibilityIdentifier(offset < 0 ? "history-previous-month" : "history-next-month")
    }

    private var selectionTools: some View {
        HStack {
            Button {
                selecting.toggle()
                selected.removeAll()
            } label: {
                Text(selecting ? String(localized: "Abbrechen") : String(localized: "Auswählen"))
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("history-selection-mode")
            if selecting {
                Button {
                    selected = selected == Set(visibleDays) ? [] : Set(visibleDays)
                } label: {
                    Text(selected == Set(visibleDays) && !selected.isEmpty
                         ? String(localized: "Auswahl aufheben") : String(localized: "Alle auswählen"))
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                .disabled(visibleDays.isEmpty)
                .accessibilityIdentifier("history-select-all")
                Button {
                    selected = Set(missingDays)
                    Theme.Haptics.select()
                } label: {
                    Image(systemName: selected == Set(missingDays) && !missingDays.isEmpty
                          ? "checkmark.circle.fill" : "circle.dashed")
                        .frame(width: 44, height: 44)
                }
                .disabled(missingDays.isEmpty)
                .help(String(localized: "Fehlende Tage auswählen"))
                .accessibilityLabel(String(localized: "Fehlende Tage auswählen"))
                .accessibilityIdentifier("history-select-missing")
            }
            Spacer()
            Toggle(isOn: $missingOnly) {
                Text(String(localized: "Ohne Eintrag")).frame(minHeight: 44)
            }
                .toggleStyle(.button)
                .font(.subheadline)
                .accessibilityIdentifier("history-missing-filter")
                .onChange(of: missingOnly) { _, _ in selected.removeAll() }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func monthDayCell(_ key: String?) -> some View {
        if let key, let date = DayKey.date(from: key, calendar: calendar) {
            let writable = Backfill.canWrite(habit: habit, day: key,
                                              today: today, calendar: calendar)
            let selectable = !missingOnly || visibleDays.contains(key)
            let level = writable ? GoalEngine.intensity(habit: habit, key: key,
                                                        calendar: calendar) : 0
            let isSelected = selected.contains(key)
            let fill = level == 0
                ? Color.primary.opacity(scheme == .dark ? 0.12 : 0.07)
                : Theme.level(level, dark: scheme == .dark, palette: palettes.style(for: habit))

            Button {
                if selecting {
                    if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
                } else {
                    write([key], value: directValue(for: key))
                }
                day = key
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill)
                    VStack(spacing: 1) {
                        Text(date, format: .dateTime.day())
                            .font(.subheadline.weight(.medium))
                        if habit.kind == .quantity, let value = habit.log[key], value > 0 {
                            Text("\(value)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        } else if habit.kind == .yesNo, habit.log[key] != nil {
                            Image(systemName: habit.log[key] == Habit.Answer.no ? "xmark" : "checkmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .foregroundStyle(level == 0
                                     ? AnyShapeStyle(Color.primary)
                                     : AnyShapeStyle(Color.white))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 2)
                            .padding(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!writable || !selectable)
            .opacity(writable && selectable ? 1 : 0.35)
            .accessibilityLabel(String(localized: "\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(Backfill.statusText(for: Backfill.state(habit: habit, day: key), kind: habit.kind))"))
            .accessibilityIdentifier("history-day-\(key)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    private func directValue(for key: String) -> Int? {
        switch habit.kind {
        case .checkbox:
            return GoalEngine.dayCounts(habit: habit, day: key, calendar: calendar) ? nil : 1
        case .quantity:
            return min(Habit.Answer.maxCount, (habit.log[key] ?? 0) + 1)
        case .yesNo:
            switch habit.log[key] {
            case Habit.Answer.yes: return Habit.Answer.no
            case Habit.Answer.no: return nil
            default: return Habit.Answer.yes
            }
        }
    }

    private var editorActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Backfill.selectionLine(habit: habit, days: selected, calendar: calendar))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("backfill-status")
            if habit.kind == .quantity {
                Stepper(value: $amount, in: 1...Habit.Answer.maxCount) {
                    Text(String(localized: "Menge: \(amount)"))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("backfill-amount-value")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons }
                VStack(spacing: 8) { actionButtons }
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
    }

    private var actionButtons: some View {
        ForEach(actions) { action in
            Button {
                write(selected.sorted(), value: action.value)
            } label: {
                Label(action.kind == .clear ? String(localized: "Einträge löschen") : action.title,
                      systemImage: action.kind == .clear ? "eraser" : action.systemImage)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(action.kind == .clear ? Color.primary : Color.white)
                    .background {
                        if action.kind == .clear {
                            Capsule().fill(.regularMaterial)
                        } else {
                            Capsule().fill(actionColor(for: action))
                        }
                    }
                    .overlay {
                        Capsule().strokeBorder(.quaternary, lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
            .accessibilityIdentifier(action.accessibilityIdentifier)
        }
    }

    private func actionColor(for action: Backfill.Action) -> Color {
        action.kind == .declined
            ? Theme.color(palettes.style(for: habit).negative(dark: scheme == .dark))
            : Theme.accentFill(palettes.style(for: habit))
    }

    private func write(_ keys: [String], value: Int?) {
        guard !keys.isEmpty else { return }
        undoStack.append(keys.map { (day: $0, value: habit.log[$0]) })
        onWrite(keys, value)
    }

    private func undo() {
        guard let entries = undoStack.popLast() else { return }
        onRestore(entries)
    }
}

private struct HistoryMonthPreview: View {
    let snapshot: GridCalendar.Snapshot
    let filledCount: Int
    let totalDays: Int
    let highlightedCells: Set<ContributionHighlightCell>
    let palette: PaletteStyle
    @Environment(\.colorScheme) private var scheme

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    private var graphWidth: CGFloat {
        max(0, CGFloat(snapshot.keys.count) * (cell + gap) - gap) + graphPadding * 2
    }
    private var graphHeight: CGFloat {
        max(0, CGFloat(GridCalendar.rows) * (cell + gap) - gap) + graphPadding * 2
    }
    private var graphPadding: CGFloat {
        ContributionTiles.highlightPadding(for: gap)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ContributionChart(snapshot: snapshot,
                              cell: cell,
                              gap: gap,
                              width: graphWidth,
                              showsMonthLabels: false,
                              labelScale: 1,
                              palette: palette,
                              highlightsToday: true,
                              checkPulse: false,
                              showsSurface: false,
                              highlightedCells: highlightedCells)
            .frame(width: graphWidth, height: graphHeight, alignment: .leading)
            Text("\(filledCount)/\(totalDays)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .frame(minHeight: 24)
                .background(.quaternary, in: Capsule())
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: graphHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(filledCount) von \(totalDays) Tagen eingetragen"))
    }
}
