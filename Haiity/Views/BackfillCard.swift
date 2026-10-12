import SwiftUI
import UIKit

/// A month of editable entries. Writes still pass through ContentView's
/// validation and persistence path; selection itself never changes a log.
struct BackfillCard: View {
    let habit: Habit
    @Binding var day: String
    let onWrite: ([String], Int?) -> [CheckInUndo.Entry]?
    let onRestore: ([CheckInUndo.Entry]) -> Bool
    let onClose: () -> Void
    var sourceAnchor: UnitPoint = .center

    @State private var selected: Set<String> = []
    @State private var selecting = false
    @State private var visibleMonth = Date()
    @State private var amount = 1
    @State private var missingOnly = false
    @State private var undoStack: [[CheckInUndo.Entry]] = []
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    monthNavigation
                    monthPreview
                    selectionTools
                    monthGrid
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selecting { editorActions }
            }
            .background(AppearanceBackground(preferences: appearancePreferences))
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
                    HistoryButton(title: String(localized: "Fertig"), symbol: nil,
                                  foreground: .white, fill: Theme.accentFill(palettes.style),
                                  titleFont: .systemFont(ofSize: 17, weight: .semibold),
                                  action: onClose)
                        .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityIdentifier("backfill-close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .pageHeaderChrome()
        .accessibilityIdentifier("backfill-card")
        .onAppear {
            let initial = DayKey.date(from: day, calendar: calendar) ?? range.upperBound
            visibleMonth = min(max(initial, range.lowerBound), range.upperBound)
            amount = max(1, habit.recurrence.effectiveTarget)
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
                .frame(minHeight: Theme.Metrics.hit)
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
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<GridCalendar.rows, id: \.self) { weekday in
                    HistoryCaption(text: calendar.veryShortWeekdaySymbols[weekday],
                                   fill: .clear)
                        .fixedSize(horizontal: false, vertical: true)
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
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            guard horizontal > 40, horizontal > vertical * 1.25 else { return }
            moveVisibleMonth(by: value.translation.width < 0 ? 1 : -1)
            Theme.Haptics.select()
        })
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
            moveVisibleMonth(by: offset)
        } label: {
            Image(systemName: symbol).frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
        }
        .disabled(adjacentMonth(offset) == nil)
        .accessibilityLabel(offset < 0 ? String(localized: "Vorheriger Monat") : String(localized: "Nächster Monat"))
        .accessibilityIdentifier(offset < 0 ? "history-previous-month" : "history-next-month")
    }

    private func moveVisibleMonth(by offset: Int) {
        guard let date = adjacentMonth(offset) else { return }
        visibleMonth = date
        selected.removeAll()
    }

    private var selectionTools: some View {
        ViewThatFits(in: .horizontal) {
            HStack { selectionControls }
            VStack(alignment: .leading, spacing: 8) { selectionControls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Theme.accentText(palettes.style(for: habit)))
        .padding(.horizontal, 20)
        .background(Theme.surfaceFill(preferences: appearancePreferences))
    }

    @ViewBuilder
    private var selectionControls: some View {
        Button {
            selecting.toggle()
            selected.removeAll()
        } label: {
            Text(selecting ? String(localized: "Abbrechen") : String(localized: "Auswählen"))
                .font(.headline)
                .frame(minHeight: Theme.Metrics.hit)
                .contentTransition(.identity)
        }
        .accessibilityIdentifier("history-selection-mode")
        if selecting {
            HistoryButton(title: selected == Set(visibleDays) && !selected.isEmpty
                          ? String(localized: "Auswahl aufheben") : String(localized: "Alle auswählen"),
                          symbol: nil, foreground: Theme.accentText(palettes.style), fill: nil) {
                selected = selected == Set(visibleDays) ? [] : Set(visibleDays)
            }
            .frame(minHeight: Theme.Metrics.hit)
            .fixedSize(horizontal: true, vertical: true)
            .disabled(visibleDays.isEmpty)
            .accessibilityIdentifier("history-select-all")
            Button {
                selected = Set(missingDays)
                Theme.Haptics.select()
            } label: {
                Image(systemName: selected == Set(missingDays) && !missingDays.isEmpty
                      ? "checkmark.circle.fill" : "circle.dashed")
                    .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
            }
            .disabled(missingDays.isEmpty)
            .help(String(localized: "Fehlende Tage auswählen"))
            .accessibilityLabel(String(localized: "Fehlende Tage auswählen"))
            .accessibilityIdentifier("history-select-missing")
        }
        Spacer(minLength: 8)
        Toggle(isOn: $missingOnly) {
            Text(String(localized: "Ohne Eintrag")).frame(minHeight: Theme.Metrics.hit)
        }
        .toggleStyle(.button)
        .font(.subheadline)
        .accessibilityIdentifier("history-missing-filter")
        .onChange(of: missingOnly) { _, _ in selected.removeAll() }
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
            let selectionAccent = Theme.accentText(
                Theme.adaptivePalette(palettes.style(for: habit),
                                       preferences: appearancePreferences,
                                       dark: scheme == .dark))

            Button {
                if selecting {
                    if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
                } else {
                    write([key], value: directValue(for: key))
                }
                day = key
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
                        .fill(fill)
                    if isSelected {
                        RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
                            .strokeBorder(selectionAccent, lineWidth: 2.5)
                            .padding(1)
                    }
                    VStack(spacing: 1) {
                        Text(date, format: .dateTime.day())
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if habit.kind == .quantity, let value = habit.log[key], value > 0 {
                            Text("\(value)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        } else if habit.kind == .yesNo, habit.log[key] != nil {
                            Image(systemName: habit.log[key] == Habit.Answer.no ? "xmark" : "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(level == 0
                                     ? AnyShapeStyle(Color.primary)
                                     : AnyShapeStyle(Theme.levelText(level, dark: scheme == .dark,
                                                                    palette: palettes.style(for: habit))))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: CornerRadius.chip, style: .continuous)
                            .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.85 : 0.7), lineWidth: 0.8)
                            .padding(4)
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
            HistoryCaption(text: Backfill.selectionLine(habit: habit, days: selected, calendar: calendar),
                           fill: Theme.surfaceFill(preferences: appearancePreferences))
                .fixedSize(horizontal: false, vertical: true)
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
        .background(Theme.surfaceFill(preferences: appearancePreferences))
    }

    private var actionButtons: some View {
        ForEach(actions) { action in
            HistoryButton(title: action.kind == .clear ? String(localized: "Einträge löschen") : action.title,
                          symbol: action.kind == .clear ? "eraser" : action.systemImage,
                          foreground: action.kind == .clear ? Color.primary
                              : action.kind == .declined
                              ? Theme.levelText(Habit.Answer.declinedLevel, dark: scheme == .dark,
                                                palette: palettes.style(for: habit)) : Color.white,
                          fill: action.kind == .clear ? Color(.tertiarySystemFill) : actionColor(for: action)) {
                write(selected.sorted(), value: action.value)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .fixedSize(horizontal: false, vertical: true)
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
        guard let entries = onWrite(keys, value) else { undoStack.removeAll(); return }
        undoStack.append(entries)
    }

    private func undo() {
        guard let entries = undoStack.last else { return }
        guard onRestore(entries) else { undoStack.removeAll(); return }
        undoStack.removeLast()
    }
}

// UIKit supplies reliable contrast metadata for these history controls.
private struct HistoryCaption: UIViewRepresentable {
    let text: String
    let fill: Color

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.overrideUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        label.font = .preferredFont(forTextStyle: .caption1)
        label.text = text
        label.textColor = .label
        label.backgroundColor = UIColor(fill)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        uiView.sizeThatFits(CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
                                  height: .greatestFiniteMagnitude))
    }
}

private struct HistoryButton: UIViewRepresentable {
    let title: String
    let symbol: String?
    let foreground: Color
    let fill: Color?
    var titleFont: UIFont? = nil
    let action: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.titleLabel?.numberOfLines = 0
        button.addInteraction(UILargeContentViewerInteraction())
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.overrideUserInterfaceStyle = context.environment.colorScheme == .dark ? .dark : .light
        var configuration = fill == nil ? UIButton.Configuration.plain() : .filled()
        configuration.title = title
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = UIColor(foreground)
        configuration.baseBackgroundColor = fill.map { UIColor($0) }
        configuration.contentInsets = fill == nil ? .zero
            : NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            attributes.font = titleFont ?? UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }
        button.configuration = configuration
        button.showsLargeContentViewer = titleFont != nil
        button.largeContentTitle = title
        button.isEnabled = context.environment.isEnabled
        let identifier = UIAction.Identifier("history-action")
        button.removeAction(identifiedBy: identifier, for: .touchUpInside)
        button.addAction(UIAction(identifier: identifier) { _ in action() }, for: .touchUpInside)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.intrinsicContentSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
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
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(filledCount) von \(totalDays) Tagen eingetragen"))
    }
}
