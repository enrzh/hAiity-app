import SwiftUI

/// Archivierte Habits: Historie bleibt erhalten, Wiederherstellen mit einem
/// Tipp. Endgültiges Löschen lebt NUR hier — mit Rückfrage.
struct ArchiveView: View {
    let store: HabitStore
    @State private var pendingDelete: Habit?
    @State private var pendingRestore: Habit?
    @State private var paywall: PaywallContext?
    @State private var proStatus = ProStatus.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palettes) private var palettes

    private var archived: [Habit] { store.habits.filter { $0.archivedAt != nil } }
    private var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                archiveSummary

                if archived.isEmpty {
                    emptyState
                } else {
                    Text(String(localized: "Archivierte Habits"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    LazyVStack(spacing: 10) {
                        ForEach(archived) { habit in
                            row(for: habit)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance + 20)
        }
        .scrollIndicators(.hidden)
        .moreSettingsSurface()
        .appPageHeader(String(localized: "Archiv"))
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
        .sheet(item: $paywall) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: {
                            if let pendingRestore {
                                store.unarchive(pendingRestore.id)
                                Theme.Haptics.success()
                                self.pendingRestore = nil
                            }
                            paywall = nil
                        })
                .themed(store, palettes: palettes)
        }
    }

    private var archiveSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "archivebox.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accentText(palettes.style))
                    .frame(width: 48, height: 48)
                    .background(Theme.accentText(palettes.style).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous))

                Text(String(localized: "Archivierte Habits"))
                    .font(.headline.weight(.semibold))
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text("\(archived.count)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .accessibilityLabel(Text(String(localized: "Archivierte Habits")))
            }

            Text(String(localized: "Archivierte Habits behalten ihre Historie und tauchen hier auf."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.12), in: Circle())
            Text(String(localized: "Archiv ist leer"))
                .font(.headline.weight(.semibold))
            Text(String(localized: "Hier erscheinen archivierte Einträge."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .morePanel()
    }

    private func row(for habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                habitSymbol(for: habit)
                titleBlock(for: habit)
                    .layoutPriority(1)

                Menu {
                    Button(role: .destructive) {
                        pendingDelete = habit
                    } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Metrics.hit, height: Theme.Metrics.hit)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(String(localized: "Weitere Aktionen")))
            }

            HStack {
                Spacer(minLength: 0)
                restoreButton(for: habit)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archived-habit")
    }

    private func habitSymbol(for habit: Habit) -> some View {
        Group {
            if habit.emoji.isEmpty {
                Image(systemName: "archivebox.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText(palettes.style))
            } else {
                Text(habit.emoji)
                    .font(.title3)
            }
        }
        .frame(width: 36, height: 36)
        .background(Theme.accentText(palettes.style).opacity(0.11), in: Circle())
    }

    private func titleBlock(for habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(habit.name)
                .font(.body.weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Archiviert am \(habit.archivedAt ?? "–") · \(habit.checkInCount()) Check-ins"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restoreButton(for habit: Habit) -> some View {
        Button {
            guard ProGate.mayUnarchiveTrackedHabit(
                isTracked: habit.isTrackedHabit,
                activeCount: store.activeTrackedHabits.count,
                unlocked: unlocked) else {
                pendingRestore = habit
                paywall = .habits
                return
            }
            store.unarchive(habit.id)
            Theme.Haptics.success()
        } label: {
            Label(String(localized: "Wiederherstellen"), systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.accentText(palettes.style).opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accentText(palettes.style))
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("unarchive-habit")
    }
}
