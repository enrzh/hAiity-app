import UIKit

/// Schnellaktionen des Homescreens: langer Druck aufs App-Icon bietet
/// direkte Wege in die App („Neues Habit", „Statistik", „Einträge aufräumen",
/// „Archiv") plus den ersten noch offenen Habit-Check des Tages.
///
/// Alles läuft über DIESELBE Tür wie die Deep-Links: die Aktion wird als
/// `haiity://…`-Link in den App-Group-Defaults geparkt und erst mit
/// Verzögerung gemeldet — dasselbe Muster wie `NotificationActionRouter`,
/// weil eine Schnellaktion eintrifft, während UIKit die Szene noch
/// restauriert. Der Empfänger in ContentView holt den Link mit
/// `takePending()` ab, wenn das Fenster wirklich aktiv ist.
///
/// Bewusst KEINE statischen Info.plist-Einträge: die wären nicht
/// lokalisiert und könnten keinen Habit-Namen tragen. iOS zeigt bis zu
/// vier Einträge an; dynamische ersetzen statische vollständig.
enum HomeShortcuts {
    /// Wird nach dem Parken einer Schnellaktion gefeuert (ohne Payload).
    static let pendingDidChange = Notification.Name("haiity.shortcut-pending")

    private static let linkTypePrefix = "haiity.link."
    private static let checkTypePrefix = "haiity.check."
    private static let pendingKey = "pendingHomeShortcut"
    private static let maxItems = 4

    // MARK: – Reine Rechnung (ohne UIKit, getestet)

    struct Descriptor: Equatable {
        let type: String
        let title: String
        let subtitle: String?
        let iconSystemName: String
        let link: URL
        let checkHabitID: UUID?
    }

    /// Erster offener Check des Tages: aktives Checkbox-/Mengen-/Ja-Nein-
    /// Habit ohne heutigen Wert — dieselbe Hürde wie `applyQuickAction`
    /// (ein mit NEIN beantworteter Tag gilt als erledigt). Erinnerungen
    /// bewusst ausgenommen — ihre Terminlogik (Occurrence-Cursor)
    /// entscheidet anders über „offen", und eine Schnellaktion, die dann
    /// doch nichts tut, wäre eine Lüge.
    static func checkOffCandidate(_ habits: [Habit], day: String) -> Habit? {
        habits.first { habit in
            guard habit.archivedAt == nil, !habit.isReminder else { return false }
            return isOpen(habit, day: day)
        }
    }

    static func checkOffCandidate(_ habits: [Habit],
                                  defaultTimeZoneIdentifier: String?,
                                  now: Date = .now,
                                  calendar: Calendar = .current) -> Habit? {
        habits.first { habit in
            guard habit.archivedAt == nil, !habit.isReminder else { return false }
            let day = HabitTimeZone.today(for: habit,
                                          defaultIdentifier: defaultTimeZoneIdentifier,
                                          now: now,
                                          base: calendar)
            return isOpen(habit, day: day)
        }
    }

    private static func isOpen(_ habit: Habit, day: String) -> Bool {
        habit.kind == .yesNo ? !habit.isAnswered(day) : !habit.isDone(day)
    }

    static func descriptors(habits: [Habit], day: String) -> [Descriptor] {
        var result: [Descriptor] = []
        if let habit = checkOffCandidate(habits, day: day) {
            result.append(Descriptor(
                type: checkTypePrefix + habit.id.uuidString,
                title: habit.name,
                subtitle: String(localized: "Abhaken"),
                iconSystemName: "checkmark.circle",
                link: URL(string: "haiity://habits")!,
                checkHabitID: habit.id))
        }
        result.append(Descriptor(type: linkTypePrefix + "new",
                                 title: String(localized: "Neues Habit"),
                                 subtitle: nil,
                                 iconSystemName: "plus.app",
                                 link: URL(string: "haiity://new")!,
                                 checkHabitID: nil))
        result.append(Descriptor(type: linkTypePrefix + "stats",
                                 title: String(localized: "Statistik"),
                                 subtitle: nil,
                                 iconSystemName: "chart.bar",
                                 link: URL(string: "haiity://stats")!,
                                 checkHabitID: nil))
        result.append(Descriptor(type: linkTypePrefix + "cleanup",
                                 title: String(localized: "Einträge aufräumen"),
                                 subtitle: nil,
                                 iconSystemName: "arrow.triangle.2.circlepath",
                                 link: URL(string: "haiity://cleanup")!,
                                 checkHabitID: nil))
        result.append(Descriptor(type: linkTypePrefix + "archive",
                                 title: String(localized: "Archiv"),
                                 subtitle: nil,
                                 iconSystemName: "archivebox",
                                 link: URL(string: "haiity://archive")!,
                                 checkHabitID: nil))
        return Array(result.prefix(maxItems))
    }

    static func descriptors(habits: [Habit],
                            defaultTimeZoneIdentifier: String?,
                            now: Date = .now,
                            calendar: Calendar = .current) -> [Descriptor] {
        var result = descriptors(habits: [], day: "2000-01-01")
        if let habit = checkOffCandidate(habits,
                                         defaultTimeZoneIdentifier: defaultTimeZoneIdentifier,
                                         now: now,
                                         calendar: calendar) {
            result.insert(Descriptor(
                type: checkTypePrefix + habit.id.uuidString,
                title: habit.name,
                subtitle: String(localized: "Abhaken"),
                iconSystemName: "checkmark.circle",
                link: URL(string: "haiity://habits")!,
                checkHabitID: habit.id), at: 0)
        }
        return Array(result.prefix(maxItems))
    }

    /// `haiity://…`-Link hinter einem Typen; nil bei fremden Typen.
    static func linkURL(forType type: String) -> URL? {
        guard type.hasPrefix(linkTypePrefix) else { return nil }
        return URL(string: "haiity://" + type.dropFirst(linkTypePrefix.count))
            .flatMap(AppDestination.resolve(url:))
            .flatMap { $0.url }
    }

    /// Habit-ID hinter einem Check-Typen; nil bei allem anderen.
    static func checkHabitID(forType type: String) -> UUID? {
        guard type.hasPrefix(checkTypePrefix) else { return nil }
        return UUID(uuidString: String(type.dropFirst(checkTypePrefix.count)))
    }

    // MARK: – Registrierung

    /// Steht der Liste im Icon-Menü neu. Der Aufrufer reicht den bereits
    /// geladenen Store-Stand herein, damit Aktivwerden keinen zweiten
    /// synchronen JSON-Decode auf dem Main Thread auslöst.
    static func update(habits: [Habit], defaultTimeZoneIdentifier: String? = nil) {
        let visibleHabits = HabitVisibility.visibleActiveHabits(
            habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
        UIApplication.shared.shortcutItems =
            descriptors(habits: visibleHabits,
                        defaultTimeZoneIdentifier: defaultTimeZoneIdentifier)
                .map(\.shortcutItem)
    }

    // MARK: – Auswertung

    static func perform(_ item: UIApplicationShortcutItem) {
        // Check zuerst: er schreibt UND lenkt. applyQuickAction verweigert
        // einen Doppel-Check von selbst — ein zweites Auswerten ist harmlos.
        if let id = checkHabitID(forType: item.type), applyCheckOff(habitID: id) {
            pend(URL(string: "haiity://habits")!)
            return
        }
        if let url = linkURL(forType: item.type) {
            pend(url)
        }
    }

    /// Dieselben Schritte wie der Nicht-Öffnen-Zweig des
    /// NotificationPresenter: Store schreiben, Neuplanung anstoßen.
    private static func applyCheckOff(habitID: UUID) -> Bool {
        let store = HabitStore(url: SharedStorage.dataURL())
        guard let habit = HabitVisibility.visibleActiveHabits(
            store.habits,
            unlocked: HabitVisibility.sharedEntitlementIsUnlocked)
            .first(where: { $0.id == habitID }) else { return false }
        let calendar = HabitTimeZone.calendar(
            for: habit,
            defaultIdentifier: store.defaultTimeZoneIdentifier)
        guard Reminders.applyQuickAction(
                  NotificationQuickAction.forHabit(habit),
                  to: habit,
                  target: NotificationHabitTarget(habitID: habitID,
                                                  day: DayKey.today(calendar: calendar)),
                  store: store,
                  defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier,
                  calendar: calendar) else { return false }
        Task {
            await Reminders.reschedule(store: store)
            await Reminders.celebrateIfPerfectDay(store: store)
            update(habits: store.habits,
                   defaultTimeZoneIdentifier: store.defaultTimeZoneIdentifier)
        }
        return true
    }

    // MARK: – Die geparkte Tür

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    private static func pend(_ url: URL) {
        defaults.set(url.absoluteString, forKey: pendingKey)

        // Bewusst außerhalb des Szenen-Callbacks: die App restauriert beim
        // Start noch UIKit-Zustand, und ein sofortiges Umschalten würde
        // genau dort abstürzen (siehe Build 75/82). Die Meldung trägt keine
        // Payload; gelesen wird aus den Defaults.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
            NotificationCenter.default.post(name: pendingDidChange, object: nil)
        }
    }

    static func takePending() -> URL? {
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        return URL(string: raw)
    }
}

private extension HomeShortcuts.Descriptor {
    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: type,
                                  localizedTitle: title,
                                  localizedSubtitle: subtitle,
                                  icon: UIApplicationShortcutIcon(systemImageName: iconSystemName))
    }
}

// MARK: – Übergabe aus UIKit

/// Hängt den Szenen-Delegaten ein. Ohne ihn kommen Schnellaktionen in
/// SwiftUI-Lifecycle-Apps nirgends an.
final class ShortcutAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil,
                                                 sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShortcutSceneDelegate.self
        return configuration
    }
}

/// KALTSTART: der Punkt steckt dann in den ConnectionOptions und
/// `performActionFor` folgt dafür NICHT noch einmal. WARM: nur
/// `performActionFor`. Beide Wege enden in derselben Auswertung; ein
/// Doppeltreten ist durch die Guards unschädlich.
final class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            HomeShortcuts.perform(item)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        HomeShortcuts.perform(shortcutItem)
        completionHandler(true)
    }
}
