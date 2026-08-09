import SwiftUI

/// Archivierte Habits: Historie bleibt erhalten, Wiederherstellen mit einem
/// Tipp. Endgültiges Löschen lebt NUR hier — mit Rückfrage.
struct ArchiveView: View {
    let store: HabitStore
    @State private var pendingDelete: Habit?

    private var archived: [Habit] { store.habits.filter { $0.archivedAt != nil } }

    var body: some View {
        List {
            if archived.isEmpty {
                ContentUnavailableView(
                    String(localized: "Archiv ist leer"),
                    systemImage: "archivebox",
                    description: Text(String(localized: "Archivierte Habits behalten ihre Historie und tauchen hier auf.")))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(archived) { habit in
                    HStack(spacing: 10) {
                        if !habit.emoji.isEmpty { Text(habit.emoji) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(String(localized: "Archiviert am \(habit.archivedAt ?? "–") · \(habit.checkInCount()) Check-ins"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.unarchive(habit.id)
                            Theme.Haptics.success()
                        } label: {
                            Text(String(localized: "Wiederherstellen"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.accentText.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accentText)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("unarchive-habit")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = habit
                        } label: {
                            Label(String(localized: "Löschen"), systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("archived-habit")
                }
            }
        }
        .navigationTitle(String(localized: "Archiv"))
        .alert(String(localized: "Endgültig löschen?"),
               isPresented: Binding(
                   get: { pendingDelete != nil },
                   set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { habit in
            Button(String(localized: "Löschen"), role: .destructive) {
                store.remove(habit.id)
            }
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        } message: { habit in
            Text(String(localized: "„\(habit.name)“ und die komplette Historie (\(habit.checkInCount()) Check-ins) werden gelöscht. Das lässt sich nicht rückgängig machen."))
        }
    }
}
