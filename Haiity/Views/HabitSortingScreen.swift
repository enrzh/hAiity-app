import SwiftUI
import UIKit

/// The native table owns dragging; rows supply identity and accessibility.
@MainActor
struct HabitSortingRow: View {
    let habit: Habit
    let position: Int
    let count: Int
    var calendar: Calendar = .current
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    @Environment(\.appearancePreferences) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let style = preferences.designStyle
        HStack(spacing: Theme.Metrics.gap + 4) {
            if habit.emoji.isEmpty {
                AppIconBadge(symbol: habit.isReminder ? "bell" : "checkmark.circle")
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                Text(habit.emoji)
                    .font(.title3)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: style.rowGap) {
                Text(habit.name)
                    .font(style.rowTitleFont)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(habit.name)
                Text((habit.isReminder ? String(localized: "Erinnerung") : String(localized: "Habit"))
                     + " · " + RecurrenceText.summary(habit.recurrence,
                                                      timeMinutes: habit.timeMinutes, calendar: calendar))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Theme.Metrics.hit)
        .padding(style.cardPadding)
        .appSurface()
        .padding(.leading, Theme.Metrics.gutter)
        .padding(.vertical, style.rowGap)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sorting-row-\(habit.id.uuidString)")
        .accessibilityValue(String(localized: "Position \(position) von \(count)"))
        .accessibilityActions {
            if let moveUp { Button(String(localized: "Nach oben verschieben"), action: moveUp) }
            if let moveDown { Button(String(localized: "Nach unten verschieben"), action: moveDown) }
        }
    }
}

@MainActor
struct NativeHabitSortingList<Row: View>: UIViewControllerRepresentable {
    let habits: [Habit]
    let move: (IndexSet, Int) -> Void
    let content: (Int, Habit) -> Row

    func makeUIViewController(context: Context) -> NativeHabitSortingController<Row> {
        NativeHabitSortingController(habits: habits, move: move, content: content)
    }

    func updateUIViewController(_ controller: NativeHabitSortingController<Row>, context: Context) {
        controller.update(habits: habits, move: move, content: content)
    }
}

@MainActor
final class NativeHabitSortingController<Row: View>: UITableViewController {
    private var habits: [Habit]
    private var move: (IndexSet, Int) -> Void
    private var content: (Int, Habit) -> Row

    init(habits: [Habit], move: @escaping (IndexSet, Int) -> Void,
         content: @escaping (Int, Habit) -> Row) {
        self.habits = habits
        self.move = move
        self.content = content
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "habit-sorting-active"
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        tableView.sectionHeaderTopPadding = 0
        tableView.allowsSelection = false
        tableView.allowsSelectionDuringEditing = false
        tableView.register(NativeHabitSortingCell<Row>.self, forCellReuseIdentifier: "sorting")
        setEditing(true, animated: false)
    }

    func update(habits: [Habit], move: @escaping (IndexSet, Int) -> Void,
                content: @escaping (Int, Habit) -> Row) {
        let orderChanged = self.habits.map(\.id) != habits.map(\.id)
        self.habits = habits
        self.move = move
        self.content = content
        guard isViewLoaded else { return }
        if orderChanged {
            // Also reconciles a rejected save or an external membership/order change.
            tableView.reloadData()
        } else {
            DispatchQueue.main.async { self.refreshVisibleRows() }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        habits.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sorting", for: indexPath)
        configure(cell, at: indexPath.row)
        return cell
    }

    private func configure(_ cell: UITableViewCell, at index: Int) {
        guard habits.indices.contains(index), let cell = cell as? NativeHabitSortingCell<Row> else { return }
        let habit = habits[index]
        let row = content(index, habit)
        if cell.habitID == habit.id, let state = cell.rowState {
            // Diff the generic SwiftUI content without replacing the hosting configuration.
            state.row = row
        } else {
            let state = NativeHabitSortingRowState(row: row)
            cell.rowState = state
            cell.contentConfiguration = UIHostingConfiguration {
                NativeHabitSortingHostedRow(state: state)
                    .frame(minHeight: 44)
            }.margins(.all, 0)
        }
        cell.habitID = habit.id
        cell.backgroundColor = .clear
        cell.backgroundConfiguration = .clear()
        cell.selectionStyle = .none
        cell.showsReorderControl = true
        cell.isAccessibilityElement = false
        cell.accessibilityLabel = habit.name + ", " + (habit.isReminder
            ? String(localized: "Erinnerung") : String(localized: "Habit"))
    }

    private func refreshVisibleRows() {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            if let cell = tableView.cellForRow(at: indexPath) { configure(cell, at: indexPath.row) }
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

    override func tableView(_ tableView: UITableView,
                            editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath,
                            to destinationIndexPath: IndexPath) {
        let source = sourceIndexPath.row
        let target = destinationIndexPath.row
        guard source != target, habits.indices.contains(source), habits.indices.contains(target) else { return }
        let destination = target > source ? target + 1 : target
        habits.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
        move(IndexSet(integer: source), destination)
        DispatchQueue.main.async { self.refreshVisibleRows() }
    }
}

@MainActor
private final class NativeHabitSortingCell<Row: View>: UITableViewCell {
    var habitID: UUID?
    var rowState: NativeHabitSortingRowState<Row>?
}

@MainActor
private final class NativeHabitSortingRowState<Row: View>: ObservableObject {
    @Published var row: Row
    init(row: Row) { self.row = row }
}

@MainActor
private struct NativeHabitSortingHostedRow<Row: View>: View {
    @ObservedObject var state: NativeHabitSortingRowState<Row>
    var body: some View { state.row }
}
