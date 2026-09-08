import Foundation

/// Opt-in UI-test data lives in a separate simulator-only store. It must
/// never replace a user's App Group data or run cloud/native integrations.
enum DesignFixture {
    static var scenario: String? {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-design-fixture"), index + 1 < args.count,
              ["empty", "realistic", "crowded"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }

    static func makeStore() -> HabitStore? {
        guard let scenario else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("design-fixture.json")
        let store = HabitStore(url: url, loadFromDisk: false)
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-design-appearance"), index + 1 < args.count,
           let appearance = AppearanceSetting(rawValue: args[index + 1]) {
            store.appearance = appearance
        }
        let names = ["Read for twenty minutes", "Drink water", "Take a walk", "No late coffee",
                     "Stretch after work", "Practice Spanish", "Write a journal", "Call family",
                     "Learn something new", "Go outside", "Meditate", "Plan tomorrow"]
        let count = scenario == "empty" ? 0 : scenario == "crowded" ? 12 : 3
        let today = DayKey.today()
        for (index, name) in names.prefix(count).enumerated() {
            var habit = Habit(name: name,
                recurrence: Recurrence(target: index == 1 ? 3 : nil),
                kind: index == 1 ? .quantity : .checkbox)
            habit.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 700 + index))!
            habit.createdAt = DayKey.shifted(today, by: -84)!
            habit.notificationMode = .off
            habit.calendarSyncEnabled = false
            for offset in 0..<84 where (offset + index) % 4 != 0 {
                if let day = DayKey.shifted(today, by: -offset) {
                    habit.log[day] = index == 1 ? 3 : 1
                }
            }
            if index == 0 { habit.log[today] = nil }
            if index == 1 { habit.log[today] = 1 }
            store.add(habit)
        }
        return store
    }
}
