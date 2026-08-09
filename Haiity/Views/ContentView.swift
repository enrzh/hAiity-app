import SwiftUI

struct ContentView: View {
    @State private var store = HabitStore()
    @State private var sync = GitHubSync()
    @State private var connectedLogin: String?
    @State private var editing: Habit?
    @State private var showAdd = false
    @State private var showSync = false
    @State private var syncStatus = ""
    @State private var pushTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if store.habits.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.habits) { habit in
                                HabitCard(
                                    habit: habit,
                                    onToggleDay: { store.toggle(habit.id, day: $0) },
                                    onEdit: { editing = habit }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("hAiity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSync = true
                    } label: {
                        Image(systemName: connectedLogin == nil ? "icloud.slash" : "checkmark.icloud")
                    }
                    .accessibilityLabel(String(localized: "GitHub-Sync"))
                    .accessibilityIdentifier("open-sync")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Habit hinzufügen"))
                    .accessibilityIdentifier("add-habit")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !syncStatus.isEmpty {
                    Text(syncStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }
        }
        .sheet(isPresented: $showAdd) { EditHabitSheet(store: store) }
        .sheet(item: $editing) { EditHabitSheet(store: store, existing: $0) }
        .sheet(isPresented: $showSync) {
            SyncSheet(store: store, sync: sync, connectedLogin: $connectedLogin)
        }
        .task { await boot() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await rescheduleReminders() } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DemoGrid()
            Text(String(localized: "Noch keine Habits"))
                .font(.title3.bold())
            Text(String(localized: "Leg einen an und fang an, Quadrate zu füllen — jeder Tag, an dem du dranbleibst, färbt eine Zelle."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Text(String(localized: "Ersten Habit anlegen"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-first-habit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boot() async {
        await sync.restore()
        connectedLogin = await sync.login
        store.onChange = { [weak store] in
            guard let store else { return }
            schedulePush(store)
            Task { await rescheduleReminders() }
        }
        if connectedLogin != nil, let remote = try? await sync.pull() {
            store.merge(remote: remote)
        }
        await rescheduleReminders()
    }

    private func rescheduleReminders() async {
        await Reminders.reschedule(
            habits: store.habits,
            summaryMinutes: store.summaryMinutes,
            openToday: store.openToday())
    }

    private func schedulePush(_ store: HabitStore) {
        guard connectedLogin != nil else { return }
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let payload = store.exportJSON() else { return }
            do {
                try await sync.push(payload) { remote in
                    if let remote {
                        await MainActor.run { store.merge(remote: remote) }
                    }
                    return await MainActor.run { store.exportJSON() ?? payload }
                }
                await MainActor.run { syncStatus = String(localized: "✓ synchronisiert") }
            } catch {
                await MainActor.run { syncStatus = error.localizedDescription }
            }
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run { syncStatus = "" }
        }
    }
}

/// Deko fürs Empty-State: ein kleines zufälliges Contribution-Muster.
private struct DemoGrid: View {
    @Environment(\.colorScheme) private var scheme
    private let pattern: [Int] = (0..<48).map { _ in
        Bool.random() && Bool.random() ? Int.random(in: 1...4) : 0
    }

    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(14), spacing: 3), count: 12)
        LazyVGrid(columns: cols, spacing: 3) {
            ForEach(Array(pattern.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.level(level, dark: scheme == .dark))
                    .frame(height: 14)
            }
        }
        .frame(width: 12 * 17)
        .accessibilityHidden(true)
    }
}
