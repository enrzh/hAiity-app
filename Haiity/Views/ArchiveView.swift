import SwiftUI

/// Archivierte Habits: Historie bleibt erhalten, Wiederherstellen mit einem
/// Tipp. Endgültiges Löschen lebt NUR hier — mit Rückfrage.
struct ArchiveView: View {
    let store: HabitStore
    @State private var pendingDelete: Habit?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palettes) private var palettes

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
                    row(for: habit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = habit
                            } label: {
                                Label(String(localized: "Löschen"), systemImage: "trash")
                            }
                        }
                        // Ohne .contain schluckt der Container seine Kinder:
                        // eine Kennung auf der Zeile macht "unarchive-habit"
                        // im AX-Baum unauffindbar (auf HabitCard nachgewiesen).
                        .accessibilityElement(children: .contain)
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

    /// Archiv-Zeile. Ab den Accessibility-Größen bricht sie um — sonst
    /// drängt die Chip-Breite von "Wiederherstellen" den Namen auf ein paar
    /// Pixel zusammen und der Titel läuft hinter den Knopf. Gestapelt
    /// bekommt der Text die volle Breite und darf mehrzeilig werden, genau
    /// wie die Kopfzeile der Habit-Karte.
    @ViewBuilder
    private func row(for habit: Habit) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                titleBlock(for: habit)
                restoreButton(for: habit)
            }
        } else {
            HStack(spacing: 10) {
                titleBlock(for: habit)
                Spacer(minLength: 8)
                restoreButton(for: habit)
            }
        }
    }

    private func titleBlock(for habit: Habit) -> some View {
        HStack(spacing: 10) {
            if !habit.emoji.isEmpty { Text(habit.emoji) }
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(String(localized: "Archiviert am \(habit.archivedAt ?? "–") · \(habit.checkInCount()) Check-ins"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func restoreButton(for habit: Habit) -> some View {
        Button {
            store.unarchive(habit.id)
            Theme.Haptics.success()
        } label: {
            Text(String(localized: "Wiederherstellen"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.accentText(palettes.style).opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accentText(palettes.style))
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("unarchive-habit")
    }
}
