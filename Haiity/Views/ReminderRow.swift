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
    @State private var reveal = SwipeRevealSession()
    @State private var isContextMenuVisible = false
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.editMode) private var editMode
    private var isSorting: Bool { editMode?.wrappedValue == .active }

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar.timeZone.identifier == rhs.calendar.timeZone.identifier
    }

    var body: some View {
        ReminderSlidingSurface(reveal: reveal,
                               leadingSwipe: leadingSwipe,
                               trailingSwipe: trailingSwipe,
                               layoutDirection: layoutDirection,
                               onAction: revealActionTapped,
                               rowContent: { rowContent })
        .background {
            if isSorting {
                SortingReorderPan()
            } else {
                SwipeRevealPan(shouldBegin: revealShouldBegin,
                               began: { reveal.begin() },
                               changed: revealChanged,
                               ended: revealEnded,
                               cancelled: { snapReveal(to: 0) },
                               isOpen: { reveal.offset != 0 },
                               ownerID: habit.id)
            }
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
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .appSurface()
            .opacity(isContextMenuVisible ? 0 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
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
        guard !revealActionLock else { return }
        revealActionLock = true
        // Finish closing before a completion can remove this row from the list.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22), completionCriteria: .removed) {
            snapReveal(to: 0)
        } completion: {
            action.handler()
            revealActionLock = false
        }
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
        guard abs(target - reveal.offset) > 0.5 else { return }
        if let animation = SwipeRevealMotion.settleAnimation(
            reduceMotion: reduceMotion,
            velocity: velocity,
            distance: target - reveal.offset) {
            withAnimation(animation) {
                reveal.offset = target
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                reveal.offset = target
            }
        }
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
        HStack(spacing: 14) {
            reminderIcon(size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Image(systemName: state.isChecked(now: now, calendar: calendar)
                  ? "checkmark.circle.fill" : "circle")
                .font(.title.weight(.semibold))
                .foregroundStyle(state.isChecked(now: now, calendar: calendar)
                                 ? Color.green : Color.secondary)
                .accessibilityLabel(String(localized: "Erledigt"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
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
        HStack(spacing: Theme.Metrics.gap) {
            HStack(spacing: Theme.Metrics.gap) {
                if habit.emoji.isEmpty {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                } else {
                    Text(habit.emoji)
                        .font(.title3)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            // The row is intentionally edited from its long-press menu. A
            // tap gesture here can be mistaken for a tap when a horizontal
            // swipe starts in the title and ends inside the same area.
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep the context-menu host off the checkmark. A full-row UIKit
            // host becomes the hit-test winner and prevents the native button
            // from receiving ordinary taps.
            .overlay {
                GraphContextMenu(cardRadius: Theme.Metrics.cardRadius,
                                 previewWidth: previewWidth,
                                 previewHeight: Self.contextPreviewHeight,
                                 previewAccessibilityIdentifier: "reminder-preview",
                                 preview: { AnyView(reminderPreview) },
                                 actions: menuActions,
                                 commit: onEdit,
                                 onMenuVisibilityChanged: { visible in
                                     isContextMenuVisible = visible
                                 })
                    .frame(maxWidth: previewWidth)
                    .allowsHitTesting(!isSorting)
            }

            Button(action: toggleFromCheckmark) {
                Image(systemName: state.isChecked(now: now, calendar: calendar)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.isChecked(now: now, calendar: calendar)
                             ? Color.green : Color.secondary)
            .accessibilityLabel(String(localized: "Erledigt"))
            .accessibilityValue(state.isChecked(now: now, calendar: calendar)
                                ? String(localized: "Erledigt")
                                : String(localized: "Offen"))
            .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
            // VoiceOver cannot perform the row pan. Named actions live on the
            // checkmark so the revealed buttons stay independently hittable.
            .modifier(ReminderVoiceOverActions(actions: leadingSwipe + trailingSwipe))
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 10)
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
                               height: ReminderRow.rowHeight,
                               onAction: onAction)
                .allowsHitTesting(revealOffset > 0)
            SwipeRevealActions(actions: trailingSwipe,
                               alignment: .trailing,
                               exposedWidth: max(-revealOffset, 0),
                               height: ReminderRow.rowHeight,
                               onAction: onAction)
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            reveal.width = width
        }
    }
}

/// Compact search hit: name and subtitle only. Search must not mount
/// contribution graphs — those rows are the measured hitch when the Search
/// tab stays alive beside Habits.
struct SearchResultRow: View, Equatable {
    let habit: Habit
    let onEdit: () -> Void
    var onToggleReminder: () -> Void = {}
    var now: Date = .now
    var calendar: Calendar = .current
    var leadingSwipe: [RevealAction] = []
    var trailingSwipe: [RevealAction] = []
    @State private var reveal = SwipeRevealSession()
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: SearchResultRow, rhs: SearchResultRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar.timeZone.identifier == rhs.calendar.timeZone.identifier
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
        HStack(spacing: Theme.Metrics.gap) {
            Button(action: onEdit) {
                HStack(spacing: Theme.Metrics.gap) {
                    if habit.emoji.isEmpty {
                        Image(systemName: habit.isReminder ? "bell.fill" : "square.grid.3x3.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    } else {
                        Text(habit.emoji)
                            .font(.title3)
                            .frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if habit.isReminder {
                Button(action: onToggleReminder) {
                    Image(systemName: reminderChecked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(reminderChecked ? Color.green : Color.secondary)
                .accessibilityLabel(String(localized: "Erledigt"))
                .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
                .modifier(ReminderVoiceOverActions(actions: leadingSwipe + trailingSwipe))
            }
        }
        .padding(.horizontal, Theme.Metrics.cardPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: ReminderRow.rowHeight)
        .appSurface()
    }

    private var reminderState: ReminderOccurrenceState {
        ReminderOccurrenceEngine.state(for: habit, now: now, calendar: calendar)
    }

    private var reminderChecked: Bool {
        reminderState.isChecked(now: now, calendar: calendar)
    }

    private var subtitle: String {
        if habit.isReminder {
            guard let occurrence = reminderState.actionable else {
                return String(localized: "Kein weiterer Termin")
            }
            return ReminderOccurrenceText.label(
                for: occurrence,
                includesTime: Habit.sanitizedMinutes(habit.timeMinutes ?? habit.reminderMinutes) != nil,
                now: now,
                calendar: calendar)
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
        guard !reveal.actionLock else { return }
        reveal.actionLock = true
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22), completionCriteria: .removed) {
            snapReveal(to: 0)
        } completion: {
            action.handler()
            reveal.actionLock = false
        }
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
