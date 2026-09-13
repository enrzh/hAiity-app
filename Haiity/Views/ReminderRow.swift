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
    @State private var revealOffset: CGFloat = 0
    @State private var revealStart: CGFloat = 0
    @State private var revealRowWidth: CGFloat = 0
    @State private var revealActionLock = false
    @State private var isContextMenuVisible = false
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.palettes) private var palettes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.habit == rhs.habit
            && DayKey.key(for: lhs.now, calendar: lhs.calendar)
                == DayKey.key(for: rhs.now, calendar: rhs.calendar)
            && lhs.leadingSwipe == rhs.leadingSwipe
            && lhs.trailingSwipe == rhs.trailingSwipe
            && lhs.calendar.timeZone.identifier == rhs.calendar.timeZone.identifier
    }

    var body: some View {
        ZStack {
            rowContent
                .offset(x: revealOffset * mirror)
                .zIndex(1)
                .allowsHitTesting(revealOffset == 0 && !revealActionLock)
                .accessibilityHidden(revealOffset != 0 || revealActionLock)
            SwipeRevealActions(actions: leadingSwipe,
                               alignment: .leading,
                               exposedWidth: max(revealOffset, 0),
                               height: Self.rowHeight,
                               onAction: revealActionTapped)
                .allowsHitTesting(revealOffset > 0)
            SwipeRevealActions(actions: trailingSwipe,
                               alignment: .trailing,
                               exposedWidth: max(-revealOffset, 0),
                               height: Self.rowHeight,
                               onAction: revealActionTapped)
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            revealRowWidth = width
        }
        .background {
            SwipeRevealPan(shouldBegin: revealShouldBegin,
                           began: { revealStart = revealOffset },
                           changed: revealChanged,
                           ended: revealEnded,
                           cancelled: { snapReveal(to: 0) },
                           ownerID: habit.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-row-\(habit.id.uuidString)")
        .allowsHitTesting(!revealActionLock)
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDismissAll)) { _ in
            guard revealOffset != 0 else { return }
            snapReveal(to: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDidBegin)) { note in
            guard let ownerID = note.object as? UUID, ownerID != habit.id,
                  revealOffset != 0 else { return }
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

    private var mirror: CGFloat {
        layoutDirection == .rightToLeft ? -1 : 1
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
        let offset = SwipeReveal.offset(
            start: revealStart, translation: translation,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count))
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            revealOffset = offset
        }
    }

    private func revealActionTapped(_ action: RevealAction) {
        guard !revealActionLock else { return }
        revealActionLock = true
        // Finish closing before a completion can remove this row from the list.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22), completionCriteria: .removed) {
            revealOffset = 0
        } completion: {
            action.handler()
            revealActionLock = false
        }
    }

    private func revealEnded(_ translation: CGFloat, velocity: CGFloat) {
        let resting = SwipeReveal.resting(
            pull: revealStart + translation,
            velocity: velocity,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count),
            cardWidth: revealRowWidth)
        switch resting {
        case .closed:
            if revealStart != 0 { Theme.Haptics.select() }
            snapReveal(to: 0, velocity: velocity)
        case .leading:
            if revealStart == 0 { Theme.Haptics.select() }
            snapReveal(to: SwipeReveal.revealWidth(count: leadingSwipe.count), velocity: velocity)
        case .trailing:
            if revealStart == 0 { Theme.Haptics.select() }
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
        guard abs(target - revealOffset) > 0.5 else { return }
        if let animation = SwipeRevealMotion.settleAnimation(
            reduceMotion: reduceMotion,
            velocity: velocity,
            distance: target - revealOffset) {
            withAnimation(animation) {
                revealOffset = target
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                revealOffset = target
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
