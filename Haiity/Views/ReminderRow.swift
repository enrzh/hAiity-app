import SwiftUI

enum ItemPresentation: Equatable {
    case habitCard
    case reminderRow

    static func forItem(_ item: Habit) -> ItemPresentation {
        item.isReminder ? .reminderRow : .habitCard
    }
}

struct ReminderRow: View, Equatable {
    static let rowHeight: CGFloat = 64

    let habit: Habit
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onRevert: () -> Void
    var onDelete: () -> Void = {}
    var onCreateOneTime: () -> Void = {}
    var onEnableSorting: () -> Void = {}
    var now: Date = .now
    var calendar: Calendar = .current
    var leadingSwipe: [RevealAction] = []
    var trailingSwipe: [RevealAction] = []
    var onDetails: (() -> Void)? = nil
    @State private var reveal = SwipeRevealSession()
    @State private var isContextMenuVisible = false
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appearancePreferences) private var appearancePreferences

    private var designStyle: AppDesignStyle { appearancePreferences.designStyle }

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar == rhs.calendar
            && (lhs.now == rhs.now || (lhs.state == rhs.state && lhs.subtitle == rhs.subtitle))
            && (lhs.onDetails == nil) == (rhs.onDetails == nil)
    }

    var body: some View {
        ReminderSlidingSurface(reveal: reveal,
                               leadingSwipe: leadingSwipe,
                               trailingSwipe: trailingSwipe,
                               layoutDirection: layoutDirection,
                               onAction: revealActionTapped,
                               rowContent: { rowContent })
        .background {
            SwipeRevealPan(shouldBegin: revealShouldBegin,
                           began: { reveal.begin() },
                           changed: revealChanged,
                           ended: revealEnded,
                           cancelled: { snapReveal(to: 0) },
                           isOpen: { reveal.offset != 0 },
                           ownerID: habit.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-row-\(habit.id.uuidString)")
        .allowsHitTesting(!revealActionLock)
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDismissAll)) { _ in
            guard reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDidBegin)) { note in
            guard let ownerID = note.object as? UUID, ownerID != habit.id,
                  reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
    }

    private var rowContent: some View {
        rowLayout
            .frame(maxWidth: .infinity, minHeight: max(Theme.Metrics.hit, designStyle.settingsRowHeight + 12))
            .appSurface()
            .opacity(isContextMenuVisible ? 0 : 1)
            .contentShape(RoundedRectangle(cornerRadius: designStyle.cardRadius,
                                           style: .continuous))
    }

    private var revealOffset: CGFloat {
        get { reveal.offset }
        nonmutating set { reveal.offset = newValue }
    }

    private var revealActionLock: Bool {
        get { reveal.actionLock }
        nonmutating set { reveal.actionLock = newValue }
    }

    private func revealShouldBegin(towardTrailing: Bool, horizontal: Bool,
                                   overGrid: Bool, gridAtTrailingEnd: Bool) -> Bool {
        SwipeReveal.canBegin(towardTrailing: towardTrailing,
                             horizontalIntent: horizontal,
                             open: revealOffset != 0,
                             hasLeading: !leadingSwipe.isEmpty,
                             hasTrailing: !trailingSwipe.isEmpty,
                             overGrid: overGrid,
                             gridAtTrailingEnd: gridAtTrailingEnd)
    }

    private func revealChanged(_ translation: CGFloat) {
        reveal.applyTranslation(translation,
                                leadingCount: leadingSwipe.count,
                                trailingCount: trailingSwipe.count)
    }

    private func revealActionTapped(_ action: RevealAction) {
        reveal.perform(action, reduceMotion: reduceMotion)
    }

    private func revealEnded(_ translation: CGFloat, velocity: CGFloat) {
        let resting = SwipeReveal.resting(
            pull: reveal.start + translation,
            velocity: velocity,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count),
            cardWidth: reveal.width)
        switch resting {
        case .closed:
            if reveal.start != 0 { Theme.Haptics.select() }
            snapReveal(to: 0, velocity: velocity)
        case .leading:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: SwipeReveal.revealWidth(count: leadingSwipe.count), velocity: velocity)
        case .trailing:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: -SwipeReveal.revealWidth(count: trailingSwipe.count), velocity: velocity)
        case .commitLeading:
            commitReveal(leadingSwipe.first)
        case .commitTrailing:
            commitReveal(trailingSwipe.first)
        }
    }

    private func commitReveal(_ action: RevealAction?) {
        Theme.Haptics.check()
        if let action { revealActionTapped(action) }
    }

    private func snapReveal(to target: CGFloat, velocity: CGFloat = 0) {
        reveal.snap(to: target, velocity: velocity, reduceMotion: reduceMotion)
    }

    // MARK: - Long-press preview

    /// The reminder preview uses the same full-width context-menu bridge as
    /// habit and GitHub graphs. Tapping the lifted surface commits directly
    /// to the editor instead of merely dismissing the native menu.
    static let contextPreviewHeight: CGFloat = 112

    private var previewWidth: CGFloat {
        HabitCard.previewMetrics(windowWidth: HabitCard.windowWidth()).width
    }

    private var reminderPreview: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap))
            : AnyLayout(HStackLayout(spacing: designStyle.cardPadding + 2))
        return layout {
            reminderIcon(size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(designStyle.sectionTitleFont)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }

            Image(systemName: state.isChecked(now: now, calendar: calendar)
                  ? "checkmark.circle.fill" : "circle")
                .font(.title.weight(.semibold))
                .foregroundStyle(state.isChecked(now: now, calendar: calendar)
                                 ? Color.green : Color.secondary)
                .accessibilityLabel(String(localized: "Erledigt"))
        }
        .padding(.horizontal, designStyle.cardPadding + 8)
        .padding(.vertical, designStyle.cardPadding + 6)
        .frame(width: previewWidth, alignment: .leading)
        .frame(minHeight: Self.contextPreviewHeight, alignment: .leading)
        .environment(\.palettes, palettes)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reminder-preview")
    }

    private func reminderIcon(size: CGFloat) -> some View {
        Group {
            if habit.emoji.isEmpty {
                Image(systemName: "bell.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(habit.emoji)
                    .font(.title)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.accentFill(palettes.style).opacity(0.14), in: Circle())
    }

    private var menuActions: [GraphMenuAction] {
        var secondary = [GraphMenuAction]()
        if habit.recurrence.frequency != .once {
            secondary.append(GraphMenuAction(title: String(localized: "Einmalig anlegen"),
                                             symbol: "plus.square",
                                             handler: onCreateOneTime))
        }
        secondary += [
            GraphMenuAction(title: String(localized: "Rückgängig"),
                            symbol: "arrow.uturn.backward",
                            handler: onRevert),
            GraphMenuAction(title: String(localized: "Archivieren"),
                            symbol: "archivebox",
                            handler: onArchive),
            GraphMenuAction(title: String(localized: "Löschen"),
                            symbol: "trash",
                            handler: onDelete,
                            destructive: true),
            GraphMenuAction(title: String(localized: "Sortieren"),
                            symbol: "arrow.up.arrow.down",
                            handler: onEnableSorting)
        ]
        return [
            GraphMenuAction(title: String(localized: "Bearbeiten"),
                            symbol: "pencil",
                            handler: onEdit),
            GraphMenuAction(title: String(localized: "Mehr"),
                            symbol: "ellipsis.circle",
                            handler: {},
                            submenu: secondary)
        ]
    }

    private var rowLayout: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: designStyle.rowGap * 2))
            : AnyLayout(HStackLayout(spacing: designStyle.rowGap * 2))
        return VStack(alignment: .leading, spacing: designStyle.rowGap) {
            layout {
                HStack(spacing: designStyle.rowGap * 2) {
                    Group {
                        if habit.emoji.isEmpty {
                            AppIconBadge(symbol: "bell.fill")
                        } else {
                            Text(habit.emoji)
                                .font(.title3)
                                .frame(width: Theme.Metrics.glyph)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                    // The preview host must not intercept the name or completion button.
                    .overlay {
                        GraphContextMenu(cardRadius: designStyle.cardRadius,
                                         previewWidth: previewWidth,
                                         previewHeight: Self.contextPreviewHeight,
                                         previewAccessibilityIdentifier: "reminder-preview",
                                         preview: { AnyView(reminderPreview) },
                                         actions: menuActions,
                                         commit: onEdit,
                                         onMenuVisibilityChanged: { visible in
                                             isContextMenuVisible = visible
                                         })
                    }

                    Button(action: onDetails ?? onEdit) {
                        VStack(alignment: .leading, spacing: designStyle.rowGap / 2) {
                            Text(habit.name)
                                .font(designStyle.rowTitleFont)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                            if onDetails != nil {
                                Label(String(localized: "Details"), systemImage: "chevron.forward")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(habit.name)
                    .accessibilityValue(subtitle)
                    .accessibilityHint(onDetails == nil
                        ? String(localized: "Bearbeiten")
                        : String(localized: "Öffnet die Details dieses Eintrags."))
                    .accessibilityIdentifier("reminder-name-\(habit.id.uuidString)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: toggleFromCheckmark) {
                    Image(systemName: state.isChecked(now: now, calendar: calendar)
                          ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                        .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.isChecked(now: now, calendar: calendar)
                                 ? Color.green : Color.secondary)
                .accessibilityLabel(String(localized: "Erledigt"))
                .accessibilityValue(state.isChecked(now: now, calendar: calendar)
                                    ? String(localized: "Erledigt")
                                    : String(localized: "Offen"))
                .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
                // Named actions supplement the pan for VoiceOver.
                .modifier(ReminderVoiceOverActions(actions: leadingSwipe + trailingSwipe))
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                       alignment: .trailing)
            }

            if onDetails == nil {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onEdit) {
                        Label(String(localized: "Bearbeiten"), systemImage: "pencil")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Bearbeiten"))
                    .accessibilityIdentifier("reminder-edit-\(habit.id.uuidString)")
                }
            }
        }
        .padding(.horizontal, min(designStyle.cardPadding + 2, Theme.Metrics.gutter))
        .padding(.vertical, designStyle.cardPadding + 2)
    }

    private var state: ReminderOccurrenceState {
        ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
    }

    private func toggleFromCheckmark() {
        onToggle()
    }

    private var subtitle: String {
        guard let occurrence = state.actionable else {
            return String(localized: "Kein weiterer Termin")
        }
        var text = ReminderOccurrenceText.label(
            for: occurrence,
            includesTime: Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) != nil,
            now: now,
            calendar: calendar
        )
        if state.overdueCount > 1 {
            text += " · +\(state.overdueCount - 1) \(String(localized: "offen"))"
        }
        return text
    }

}

private struct ReminderSlidingSurface<Content: View>: View {
    var reveal: SwipeRevealSession
    let leadingSwipe: [RevealAction]
    let trailingSwipe: [RevealAction]
    let layoutDirection: LayoutDirection
    let onAction: (RevealAction) -> Void
    @ViewBuilder var rowContent: () -> Content

    private var revealOffset: CGFloat { reveal.offset }
    private var revealActionLock: Bool { reveal.actionLock }
    private var mirror: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    var body: some View {
        ZStack {
            rowContent()
                .offset(x: revealOffset * mirror)
                .zIndex(1)
                .allowsHitTesting(revealOffset == 0 && !revealActionLock)
                .accessibilityHidden(revealOffset != 0 || revealActionLock)
            SwipeRevealActions(actions: leadingSwipe,
                               alignment: .leading,
                               exposedWidth: max(revealOffset, 0),
                               height: nil,
                               onAction: onAction)
                .allowsHitTesting(revealOffset > 0)
            SwipeRevealActions(actions: trailingSwipe,
                               alignment: .trailing,
                               exposedWidth: max(-revealOffset, 0),
                               height: nil,
                               onAction: onAction)
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            reveal.width = width
        }
    }
}

/// Compact identity and actions shared by Today and native Search, without graphs.
struct SearchResultRow: View, Equatable {
    @Environment(\.appearancePreferences) private var preferences
    let habit: Habit
    let onEdit: () -> Void
    var onToggleReminder: () -> Void = {}
    var now: Date = .now
    var calendar: Calendar = .current
    var leadingSwipe: [RevealAction] = []
    var trailingSwipe: [RevealAction] = []
    var onDetails: (() -> Void)? = nil
    var onToggleDay: (String) -> Void = { _ in }
    var onIncrement: () -> Void = {}
    var onAnswer: (Bool) -> Void = { _ in }
    @State private var reveal = SwipeRevealSession()
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    static func == (lhs: SearchResultRow, rhs: SearchResultRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar == rhs.calendar
            && (!lhs.habit.isReminder || lhs.now == rhs.now)
            && (lhs.onDetails == nil) == (rhs.onDetails == nil)
    }

    var body: some View {
        ReminderSlidingSurface(reveal: reveal,
                               leadingSwipe: leadingSwipe,
                               trailingSwipe: trailingSwipe,
                               layoutDirection: layoutDirection,
                               onAction: revealActionTapped,
                               rowContent: { rowContent })
        .background {
            SwipeRevealPan(shouldBegin: revealShouldBegin,
                           began: { reveal.begin() },
                           changed: revealChanged,
                           ended: revealEnded,
                           cancelled: { snapReveal(to: 0) },
                           isOpen: { reveal.offset != 0 },
                           ownerID: habit.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-result-\(habit.id.uuidString)")
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDismissAll)) { _ in
            guard reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDidBegin)) { note in
            guard let ownerID = note.object as? UUID, ownerID != habit.id,
                  reveal.offset != 0 else { return }
            snapReveal(to: 0)
        }
    }

    private var rowContent: some View {
        let style = preferences.designStyle
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: style.rowGap * 2))
            : AnyLayout(HStackLayout(spacing: Theme.Metrics.gap))
        return layout {
            Button(action: onDetails ?? onEdit) {
                HStack(spacing: Theme.Metrics.gap) {
                    if habit.emoji.isEmpty {
                        Image(systemName: habit.isReminder ? "bell.fill" : "square.grid.3x3.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                    } else {
                        Text(habit.emoji)
                            .font(.title3)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(preferences.designStyle.rowTitleFont)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText(preferences: preferences))
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let todayAnswer {
                            Text(todayAnswer)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let periodProgress {
                            Text(periodProgress)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText(preferences: preferences))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("item-details-\(habit.id.uuidString)")
            .accessibilityValue(todayAnswer ?? "")

            if habit.isReminder {
                Button(action: onToggleReminder) {
                    Image(systemName: reminderChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(reminderChecked ? Color.green : Color.primary)
                .accessibilityLabel(String(localized: "Erledigt"))
                .accessibilityValue(reminderChecked ? String(localized: "Erledigt") : String(localized: "Offen"))
                .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
                .modifier(ReminderVoiceOverActions(actions: leadingSwipe + trailingSwipe))
            } else {
                HabitActionControls(habit: habit, calendar: calendar, now: now,
                                    onToggleDay: onToggleDay, onIncrement: onIncrement, onAnswer: onAnswer)
            }
        }
        .padding(.horizontal, preferences.designStyle.cardPadding)
        .padding(.vertical, preferences.designStyle.cardPadding - 2)
        .frame(maxWidth: .infinity, minHeight: max(Theme.Metrics.hit, preferences.designStyle.settingsRowHeight + 12))
        .appSurface()
    }

    private var reminderState: ReminderOccurrenceState {
        ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
    }

    private var reminderChecked: Bool {
        reminderState.isChecked(now: now, calendar: calendar)
    }

    var periodProgress: String? {
        guard habit.isTrackedHabit, let target = habit.recurrence.timesPerPeriod else { return nil }
        let today = DayKey.key(for: now, calendar: calendar)
        let schedule = habit.recurrence.schedule(calendar: calendar)
        guard schedule.isScheduled(today), let period = schedule.periodStart(for: now) else { return nil }
        let completed = GoalEngine.periodCounts(habit: habit, schedule: schedule,
                                                 today: today, calendar: calendar)[period] ?? 0
        return String(localized: "In dieser Periode: \(completed) von \(target) erledigt")
    }

    var todayAnswer: String? {
        habit.isTrackedHabit && habit.kind == .yesNo
            && habit.isDeclined(DayKey.key(for: now, calendar: calendar))
            ? String(localized: "Heute: Nein") : nil
    }

    var subtitle: String {
        if habit.isReminder {
            let state = reminderState
            guard let occurrence = state.actionable else {
                return String(localized: "Kein weiterer Termin")
            }
            var text = ReminderOccurrenceText.label(
                for: occurrence,
                includesTime: Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) != nil,
                now: now,
                calendar: calendar)
            if state.overdueCount > 1 {
                text += " · +\(state.overdueCount - 1) \(String(localized: "offen"))"
            }
            return text
        }
        var text = RecurrenceText.pattern(habit.recurrence, calendar: calendar)
        if let clock = RecurrenceText.timeText(habit.timeMinutes) {
            text += String(localized: " um \(clock)")
        }
        return text
    }

    private func revealShouldBegin(towardTrailing: Bool, horizontal: Bool,
                                   overGrid: Bool, gridAtTrailingEnd: Bool) -> Bool {
        SwipeReveal.canBegin(towardTrailing: towardTrailing,
                             horizontalIntent: horizontal,
                             open: reveal.offset != 0,
                             hasLeading: !leadingSwipe.isEmpty,
                             hasTrailing: !trailingSwipe.isEmpty,
                             overGrid: overGrid,
                             gridAtTrailingEnd: gridAtTrailingEnd)
    }

    private func revealChanged(_ translation: CGFloat) {
        reveal.applyTranslation(translation,
                                leadingCount: leadingSwipe.count,
                                trailingCount: trailingSwipe.count)
    }

    private func revealActionTapped(_ action: RevealAction) {
        reveal.perform(action, reduceMotion: reduceMotion)
    }

    private func revealEnded(_ translation: CGFloat, velocity: CGFloat) {
        let resting = SwipeReveal.resting(
            pull: reveal.start + translation,
            velocity: velocity,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count),
            cardWidth: reveal.width)
        switch resting {
        case .closed:
            if reveal.start != 0 { Theme.Haptics.select() }
            snapReveal(to: 0, velocity: velocity)
        case .leading:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: SwipeReveal.revealWidth(count: leadingSwipe.count), velocity: velocity)
        case .trailing:
            if reveal.start == 0 { Theme.Haptics.select() }
            snapReveal(to: -SwipeReveal.revealWidth(count: trailingSwipe.count), velocity: velocity)
        case .commitLeading:
            Theme.Haptics.check()
            if let action = leadingSwipe.first { revealActionTapped(action) }
        case .commitTrailing:
            Theme.Haptics.check()
            if let action = trailingSwipe.first { revealActionTapped(action) }
        }
    }

    private func snapReveal(to target: CGFloat, velocity: CGFloat = 0) {
        reveal.snap(to: target, velocity: velocity, reduceMotion: reduceMotion)
    }
}

/// VoiceOver substitute for the reminder pan. This is attached to the
/// checkmark, not the row, so the visible reveal buttons stay hittable.
private struct ReminderVoiceOverActions: ViewModifier {
    let actions: [RevealAction]

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.accessibilityActions {
                ForEach(actions) { action in
                    Button(action.title, action: action.handler)
                }
            }
        }
    }
}
