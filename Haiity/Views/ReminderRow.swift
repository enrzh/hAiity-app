import SwiftUI

@MainActor
final class ReminderToggleGate {
    static let shared = ReminderToggleGate()

    private var suppressedUntil: [UUID: Date] = [:]

    func suppress(_ habitID: UUID, for duration: TimeInterval = 2.5) {
        suppressedUntil[habitID] = .now.addingTimeInterval(duration)
    }

    func consumeSuppression(for habitID: UUID) -> Bool {
        guard let until = suppressedUntil[habitID] else { return false }
        suppressedUntil[habitID] = nil
        return until > .now
    }
}

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
    @Environment(\.interactionBridgesReady) private var interactionBridgesReady

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
            revealButtons(actions: leadingSwipe, alignment: .leading,
                          exposedWidth: max(revealOffset, 0),
                          containerWidth: revealRowWidth)
                .allowsHitTesting(revealOffset > 0)
            revealButtons(actions: trailingSwipe, alignment: .trailing,
                          exposedWidth: max(-revealOffset, 0),
                          containerWidth: revealRowWidth)
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            revealRowWidth = width
        }
        .background {
            if interactionBridgesReady {
                SwipeRevealPan(shouldBegin: revealShouldBegin,
                               began: { revealStart = revealOffset },
                               changed: revealChanged,
                               ended: revealEnded)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-row-\(habit.id.uuidString)")
        .onReceive(NotificationCenter.default.publisher(for: .swipeRevealDismissAll)) { _ in
            guard revealOffset != 0 else { return }
            closeReveal()
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
        revealOffset = SwipeReveal.offset(
            start: revealStart, translation: translation,
            leadingWidth: SwipeReveal.revealWidth(count: leadingSwipe.count),
            trailingWidth: SwipeReveal.revealWidth(count: trailingSwipe.count))
    }

    @ViewBuilder
    private func revealButtons(actions: [RevealAction], alignment: Alignment,
                               exposedWidth: CGFloat,
                               containerWidth: CGFloat) -> some View {
        let actionWidth = SwipeReveal.revealWidth(count: actions.count)
        let actionStack = HStack(spacing: SwipeReveal.buttonGap) {
            ForEach(actions) { action in
                revealButton(action)
            }
        }
        // Keep the action layer fixed to the row edge, matching HabitCard.
        // Only the exposed portion is clipped while the row moves above it;
        // the full button frame remains stable and hittable at rest.
        let actionLayer = actionStack
            .frame(width: actionWidth, alignment: alignment)
            .frame(height: Self.rowHeight)
        Group {
            if exposedWidth >= actionWidth {
                actionLayer
                    .frame(maxWidth: .infinity, alignment: alignment)
            } else {
                actionLayer
                    .frame(width: exposedWidth, alignment: alignment)
                    .clipped()
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        // Keep the trailing action inside the List cell's effective hit edge.
        // UIKit can report the visual cell a few points wider than its tappable
        // region on iOS 27.
        .padding(.trailing, alignment == .trailing ? Theme.Metrics.gap : 0)
        // Keep the final button inside the List cell's hit rect as well as its
        // visual rect. This avoids a one-pixel outside frame after rounding.
        .offset(x: alignment == .trailing ? -2 : 0)
        .accessibilityHidden(exposedWidth < actionWidth)
        .transition(.identity)
    }

    private func revealButton(_ action: RevealAction) -> some View {
        Button {
            // Defer both the mutation and the close until UIKit has finished
            // delivering this touch. Reset shares the checkmark's trailing
            // hit area; mutating the row from inside the button callback can
            // otherwise expose that control to the same touch.
            revealActionLock = true
            if action.operation == .reset { ReminderToggleGate.shared.suppress(habit.id) }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                action.handler()
                closeReveal()
                // XCTest and UIKit can finish dispatching a synthesized tap
                // after the button action returns. Keep the old row inert for
                // that tail so a reset cannot also toggle its checkmark.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                revealActionLock = false
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: action.symbol)
                    .font(.title3.weight(.semibold))
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(width: SwipeReveal.buttonWidth)
            .frame(maxHeight: .infinity)
            .background(action.tint,
                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                             style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: SwipeReveal.buttonWidth, height: Self.rowHeight)
        .contentShape(Rectangle())
        .zIndex(100)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("reveal-action-\(action.operation.rawValue)")
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
            snapReveal(to: 0)
        case .leading:
            if revealStart == 0 { Theme.Haptics.select() }
            snapReveal(to: SwipeReveal.revealWidth(count: leadingSwipe.count))
        case .trailing:
            if revealStart == 0 { Theme.Haptics.select() }
            snapReveal(to: -SwipeReveal.revealWidth(count: trailingSwipe.count))
        case .commitLeading:
            commitReveal(leadingSwipe.first)
        case .commitTrailing:
            commitReveal(trailingSwipe.first)
        }
    }

    private func commitReveal(_ action: RevealAction?) {
        Theme.Haptics.check()
        closeReveal()
        if action?.operation == .reset { ReminderToggleGate.shared.suppress(habit.id) }
        action?.handler()
    }

    /// Close synchronously before mutating the store. An animated close can
    /// leave the action layer above the newly rendered row for one layout
    /// pass, making the next action visible but not hittable.
    private func closeReveal() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            revealOffset = 0
            revealStart = 0
        }
    }

    private func snapReveal(to target: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            revealOffset = target
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
                if interactionBridgesReady {
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
        // A drag that starts on the checkmark can finish its delayed control
        // delivery after the revealed Reset action has already run. Consume
        // that one stale toggle without blocking a later deliberate tap.
        if ReminderToggleGate.shared.consumeSuppression(for: habit.id) { return }
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
