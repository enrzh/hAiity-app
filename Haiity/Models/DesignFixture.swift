import Foundation
import UIKit

/// Opt-in UI-test data lives in a separate simulator-only store. It must
/// never replace a user's App Group data or run cloud/native integrations.
enum DesignFixture {
    static var scenario: String? {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-design-fixture"), index + 1 < args.count,
              ["empty", "realistic", "crowded", "mixed", "sorting"].contains(args[index + 1]) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }

    static func makeStore() -> HabitStore? {
        guard let scenario else { return nil }
        var url = FileManager.default.temporaryDirectory.appendingPathComponent("design-fixture-\(UUID()).json")
        #if DEBUG && targetEnvironment(simulator)
        // Accept an ID, never an arbitrary URL into real user/App Group data.
        if scenario == "sorting",
           let rawID = ProcessInfo.processInfo.environment["HAIITY_SORTING_FIXTURE_ID"],
           let id = UUID(uuidString: rawID) {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("design-fixture-sorting-\(id.uuidString).json")
            if FileManager.default.fileExists(atPath: url.path) {
                // Relaunch must exercise the durable store, not reseed its order.
                return HabitStore(url: url)
            }
        }
        #endif
        let store = HabitStore(url: url, loadFromDisk: false)
        let args = ProcessInfo.processInfo.arguments
        // Personalization fixtures use a separate defaults suite as well.
        PersonalName.alias = nil
        PersonalName.appleName = nil
        PersonalName.appleUserID = nil
        PersonalName.appleEmail = nil
        if let index = args.firstIndex(of: "-design-account"), index + 1 < args.count,
           args[index + 1] == "connected" {
            PersonalName.alias = "Alex"
            PersonalName.appleName = "Alex Morgan"
            PersonalName.appleUserID = "fixture-apple-account"
            PersonalName.appleEmail = "alex@privaterelay.appleid.com"
        }
        if let index = args.firstIndex(of: "-design-appearance"), index + 1 < args.count,
           let appearance = AppearanceSetting(rawValue: args[index + 1]) {
            store.appearance = appearance
        }
        if let index = args.firstIndex(of: "-design-material"), index + 1 < args.count,
           let material = AppearanceMaterial(rawValue: args[index + 1]) {
            store.appearancePreferences.material = material
        }
        if let index = args.firstIndex(of: "-design-style"), index + 1 < args.count,
           let style = AppDesignStyle(rawValue: args[index + 1]) {
            store.appearancePreferences.designStyle = style
        }
        if args.contains("-design-photo") {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 400)).image { context in
                for index in 0..<8 {
                    (index.isMultiple(of: 2) ? UIColor.white : UIColor.black).setFill()
                    context.fill(CGRect(x: 0, y: index * 50, width: 200, height: 50))
                }
            }
            var preferences = store.appearancePreferences
            preferences.backgroundMode = .image
            preferences.backgroundImageData = image.jpegData(compressionQuality: 0.8)
            store.appearancePreferences = preferences
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
        if scenario == "mixed" || scenario == "sorting" {
            var reminder = Habit(name: "Call the dentist to confirm the appointment and discuss the treatment plan",
                                 itemType: .reminder)
            reminder.id = UUID(uuidString: "00000000-0000-0000-0000-000000000799")!
            reminder.notificationMode = .off
            reminder.calendarSyncEnabled = false
            store.add(reminder)
        }
        if scenario == "sorting" {
            // The first four rows retain the mixed fixture's IDs, including 799.
            // Daily recurrence keeps all 40 rows eligible in Today scope.
            for index in 3..<39 {
                let name = index.isMultiple(of: 5)
                    ? "Plan a long walk after work and remember to bring water and a rain jacket \(index)"
                    : "\(names[index % names.count]) \(index)"
                var habit = Habit(name: name, itemType: index.isMultiple(of: 3) ? .reminder : .habit,
                                  notificationMode: .off)
                habit.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 700 + index))!
                habit.calendarSyncEnabled = false
                store.add(habit)
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        if args.contains("-design-write-conflict") {
            // A second isolated writer makes the next UI save reject its
            // stale baseline. The user's App Group file is never involved.
            HabitStore(url: url).summaryMinutes = 12 * 60
        }
        #endif
        return store
    }
}
