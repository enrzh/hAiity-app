import SwiftUI

/// Archivierte Habits: Historie bleibt erhalten, Wiederherstellen mit einem
/// Tipp. Endgültiges Löschen lebt NUR hier — mit Rückfrage.
struct ArchiveView: View {
    let store: HabitStore
    var routeToken: Int = 0
    @State private var detailID: UUID?
    @State private var pendingDelete: Habit?
    @State private var pendingRestore: Habit?
    @State private var paywall: PaywallContext?
    @State private var proStatus = ProStatus.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.palettes) private var palettes
    @Environment(\.appearancePreferences) private var preferences

    private var designStyle: AppDesignStyle { preferences.designStyle }

    private var archived: [Habit] { store.habits.filter { $0.archivedAt != nil } }
    private var unlocked: Bool {
        _ = proStatus.unlocked
        return Pro.isUnlocked
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: designStyle.sectionGap) {
                archiveSummary

                if archived.isEmpty {
                    emptyState
                } else {
                    Text(String(localized: "Archivierte Habits"))
                        .font(designStyle.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 4)

                    LazyVStack(spacing: designStyle.rowGap * 2) {
                        ForEach(archived) { habit in
                            row(for: habit)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.top, designStyle.cardPadding)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
            .frame(maxWidth: Theme.Metrics.readableContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .settingsChrome()
        .navigationTitle(String(localized: "Archiv"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailID) { id in
            HabitDetailView(store: store, habitID: id, now: .now,
                onEdit: { _ in }, onHistory: { _ in }, onToggleDay: { _, _ in },
                onIncrement: { _ in }, onAnswer: { _, _ in }, onToggleReminder: { _ in },
                onArchive: { _ in }, onDelete: { id in pendingDelete = archived.first { $0.id == id } },
                allowsArchived: true, onRestore: { id in
                    if let habit = archived.first(where: { $0.id == id }) { restore(habit) }
                })
        }
        .onChange(of: routeToken) { _, _ in
            detailID = nil
            pendingRestore = nil
            paywall = nil
        }
        .pageHeaderChrome()
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
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            HStack(spacing: Theme.Metrics.gap + 4) {
                Image(systemName: "archivebox.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accentText(palettes.style))
                    .frame(width: 48, height: 48)
                    .background(Theme.accentText(palettes.style).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: CornerRadius.panel, style: .continuous))

                Text(String(localized: "Archivierte Habits"))
                    .font(designStyle.sectionTitleFont)
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
        .padding(designStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .morePanel()
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: designStyle.rowGap * 2) {
            Image(systemName: "archivebox")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.12), in: Circle())
            Text(String(localized: "Archiv ist leer"))
                .font(designStyle.sectionTitleFont)
            Text(String(localized: "Hier erscheinen archivierte Einträge."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(designStyle.cardPadding)
        .morePanel()
    }

    private func row(for habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap * 2) {
            HStack(alignment: .top, spacing: Theme.Metrics.gap + 4) {
                habitSymbol(for: habit)
                Button { detailID = habit.id } label: {
                    titleBlock(for: habit)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.hit, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).layoutPriority(1)

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
        .padding(designStyle.cardPadding)
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
        .accessibilityHidden(true)
    }

    private func titleBlock(for habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: designStyle.rowGap) {
            Text(habit.name)
                .font(designStyle.rowTitleFont)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "Archiviert am \(habit.archivedAt ?? "–") · \(habit.checkInCount()) Check-ins"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restoreButton(for habit: Habit) -> some View {
        Button { restore(habit) } label: {
            Label(String(localized: "Wiederherstellen"), systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: Theme.Metrics.hit, minHeight: Theme.Metrics.hit)
                .background(Theme.accentText(palettes.style).opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.accentText(palettes.style))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("unarchive-habit")
    }

    private func restore(_ habit: Habit) {
        guard ProGate.mayUnarchiveTrackedHabit(
            isTracked: habit.isTrackedHabit,
            activeCount: store.activeTrackedHabits.count,
            unlocked: unlocked) else {
            pendingRestore = habit
            paywall = .habits
            return
        }
        store.unarchive(habit.id)
        if store.lastWriteError == nil { Theme.Haptics.success() }
    }
}
