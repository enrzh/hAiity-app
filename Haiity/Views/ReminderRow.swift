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
    @Environment(\.layoutDirection) private var layoutDirection

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
                .allowsHitTesting(revealOffset == 0)
            if revealOffset != 0 {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                                   style: .continuous))
                    .offset(x: revealOffset * mirror)
                    .onTapGesture {
                        Theme.Haptics.select()
                        snapReveal(to: 0)
                    }
            }
            revealButtons(actions: leadingSwipe, alignment: .leading,
                          exposedWidth: max(revealOffset, 0))
                .allowsHitTesting(revealOffset > 0)
            revealButtons(actions: trailingSwipe, alignment: .trailing,
                          exposedWidth: max(-revealOffset, 0))
                .allowsHitTesting(revealOffset < 0)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            revealRowWidth = width
        }
        .background {
            SwipeRevealPan(shouldBegin: revealShouldBegin,
                           began: { revealStart = revealOffset },
                           changed: revealChanged,
                           ended: revealEnded)
        }
        .accessibilityRevealActions(leadingSwipe + trailingSwipe)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminder-row-\(habit.id.uuidString)")
    }

    private var rowContent: some View {
        rowLayout
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .appSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius,
                                           style: .continuous))
            .contextMenu {
                Button(action: onEdit) {
                    Label(String(localized: "Bearbeiten"), systemImage: "pencil")
                }
                if habit.recurrence.frequency != .once {
                    Button(action: onCreateOneTime) {
                        Label(String(localized: "Einmalig anlegen"), systemImage: "plus.square")
                    }
                }
                Button(action: onRevert) {
                    Label(String(localized: "Rückgängig"),
                          systemImage: "arrow.uturn.backward")
                }
                Button(action: onArchive) {
                    Label(String(localized: "Archivieren"), systemImage: "archivebox")
                }
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "Löschen"), systemImage: "trash")
                }
                Button(action: onEnableSorting) {
                    Label(String(localized: "Sortieren"), systemImage: "arrow.up.arrow.down")
                }
            }
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
                               exposedWidth: CGFloat) -> some View {
        HStack(spacing: SwipeReveal.buttonGap) {
            ForEach(actions) { action in
                Button {
                    snapReveal(to: 0)
                    action.handler()
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
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("reveal-action-\(action.operation.rawValue)")
    }
        }
        // Give the underlay a real exposed width before expanding it to the
        // row. A mask on a full-width frame still leaves a full-width layout
        // surface on iOS 27, which can bleed through translucent cards.
        .frame(width: exposedWidth, alignment: alignment)
        .frame(maxHeight: .infinity)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: alignment)
        // Keep the trailing action inside the List row's effective content
        // edge. SwiftUI's List can expose a wider accessibility frame than
        // its hittable trailing area after cell reuse.
        .padding(.trailing, alignment == .trailing ? Theme.Metrics.gap : 0)
        // The card's horizontal offset is the reveal animation. Keep the
        // action layer stable so it appears from the card edge, not by fading
        // or scaling independently.
        .transition(.identity)
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
        snapReveal(to: 0)
        action?.handler()
    }

    private func snapReveal(to target: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            revealOffset = target
        }
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
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)

            Button(action: onToggle) {
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
