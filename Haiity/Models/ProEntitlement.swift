import Foundation
import Observation
import StoreKit

/// Der beobachtbare Speicher hinter `Pro.isUnlocked`.
///
/// **Warum es diese Klasse gibt.** Ein Kauf muss nicht in dieser Ansicht
/// passieren: er kommt vom anderen Gerät oder als Erstattung — alles
/// Meldungen, die
/// `Transaction.updates` bringt, ohne dass jemand etwas angetippt hätte.
/// `enum Pro` ist statischer Zustand und für SwiftUI unsichtbar; ohne diesen
/// Speicher bliebe die Statistik gesperrt und die Einstellungen böten den
/// Kauf weiter an, bis der Rumpf zufällig aus anderem Grund neu ausgewertet
/// wird. Genau das verhindert, dass die Kaufseite nach einem Kauf auf einem
/// anderen Gerät den alten Sperrzustand zeigt.
///
/// Gelesen wird trotzdem ausschliesslich über `Pro.isUnlocked` — ein zweiter
/// Lesepunkt wäre ein zweiter Ort, an dem die Debug-Klammer fehlen kann.
@MainActor
@Observable
final class ProStatus {
    static let shared = ProStatus()

    /// Schreiben darf nur `Pro` (siehe `Pro.cache`).
    fileprivate(set) var unlocked: Bool

    private init() {
        unlocked = (UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard)
            .bool(forKey: Pro.unlockedKey)
    }
}

/// hAiity Pro — EIN nicht-verbrauchbarer Kauf. Einmal kaufen, kein Abo,
/// kein Konto, kein Server.
///
/// **Warum ein lokaler Merker.** Der App Store ist eine Netzleitung, eine
/// Liste ist es nicht: keine Oberfläche darf warten, bis StoreKit geantwortet
/// hat, und ohne Netz (Flugmodus, Zug, erster Start am Morgen) käme gar keine
/// Antwort. `proUnlocked` ist deshalb die Wahrheit, aus der die Gates lesen —
/// StoreKit korrigiert sie beim Start, beim Kauf, beim Wiederherstellen und
/// bei jeder Transaktionsmeldung.
///
/// **Und deshalb stuft der Bestandsabgleich nur HOCH.** Eine Wahrheit, die
/// ein fehlgeschlagener Abgleich stillschweigend auf `false` setzt, ist
/// keine: `Transaction.currentEntitlements` unterscheidet „kein Anspruch"
/// nicht von „gerade nichts zu holen". Herabgestuft wird nur dort, wo eine
/// Aussage vorliegt — beim Lauscher (Erstattung) und nach einem
/// nachweislich erfolgreichen `AppStore.sync()`.
///
/// **Warum die App-Group und nicht `.standard`.** Derselbe Ort, an dem schon
/// der Kalender-Schalter und der Glückwunsch-Merker wohnen. Das Widget ist in
/// v1 bewusst NICHT gegated, aber der Schlüssel liegt dort, wo ein zweiter
/// Prozess ihn lesen KÖNNTE — so muss die Ablage später nicht umziehen.
///
/// **Family Sharing ist nicht Teil des Produkts.** Der StoreKit-Katalog und
/// die Entitlement-Prüfung akzeptieren deshalb nur direkt gekaufte Käufe.
///
/// **Was hier NICHT hingehört.** Die Frage „darf ich das?" beantwortet
/// `ProGate` — pur, ohne StoreKit, damit sie testbar ist. `Pro` weiß nur, OB
/// gekauft wurde, nie WOFÜR es reicht.
@MainActor
enum Pro {
    static let productID = "com.aiity.haiity.pro"
    static let unlockedKey = "proUnlocked"

    /// Fehler, die eine Oberfläche unterscheiden muss. Bewusst ohne Text:
    /// die Sätze gehören auf die Kaufseite, nicht in die Datenschicht.
    enum PurchaseError: Error {
        /// Das Produkt kam nicht aus dem Store (falsche ID, kein Netz, in
        /// App Store Connect noch nicht freigegeben).
        case productUnavailable
        /// Der Kauf lief durch, aber Apples Signatur trägt ihn nicht.
        case unverified
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    private static var listener: Task<Void, Never>?
    private static var entitlementMonitor: Task<Void, Never>?
    private static let entitlementPollInterval: Duration = .seconds(15)

    /// Zählt jede ECHTE Zustandsänderung. `refresh()` läuft über ein `await`
    /// und schreibt sein Ergebnis danach zurück — trifft in diesem Fenster
    /// eine Meldung des Lauschers ein (Freigabe, Kauf auf einem anderen
    /// Gerät, Erstattung), ist das Ergebnis von vorhin veraltet und darf sie
    /// nicht überschreiben.
    private static var writeGeneration = 0

    #if DEBUG
    /// Der Debug-Haken `-pro on|off` gewinnt gegen JEDE spätere Prüfung.
    /// Grund: `handleLaunchScreenArgument()` läuft NACH `boot()`, der dort
    /// gestartete `refresh()` antwortet aber erst Sekunden später — ohne
    /// diese Klammer würde StoreKit den gesetzten Zustand wieder wegräumen
    /// und die Gates wären im Simulator nicht prüfbar.
    private(set) static var debugOverride: Bool?
    #endif

    /// Der eine Lesepunkt für alle Gates — und beobachtbar, damit ein Kauf,
    /// der anderswo passiert, die Sperren auch anderswo aufgehen lässt.
    static var isUnlocked: Bool {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        return DeveloperAccess.isOwnerDevice(
            storedAppleUserID: PersonalName.appleUserID,
            storedAppleEmail: PersonalName.appleEmail
        ) || ProStatus.shared.unlocked
    }

    /// Der eine Schreibpunkt. Alles, was StoreKit erfährt, landet hier —
    /// und nur hier steht die Debug-Klammer.
    private static func cache(_ unlocked: Bool) {
        #if DEBUG
        if debugOverride != nil { return }
        #endif
        let ownerDevice = DeveloperAccess.isOwnerDevice(
            storedAppleUserID: PersonalName.appleUserID,
            storedAppleEmail: PersonalName.appleEmail
        )
        let effectiveUnlocked = unlocked || ownerDevice
        if !effectiveUnlocked {
            CalendarSync.disable()
            ReminderSync.disable()
        }
        guard ProStatus.shared.unlocked != effectiveUnlocked else { return }
        writeGeneration &+= 1
        defaults.set(effectiveUnlocked, forKey: unlockedKey)
        ProStatus.shared.unlocked = effectiveUnlocked
    }

    /// Bestand prüfen: was steht heute auf diesem Konto? Zurückgezogene oder
    /// über Family Sharing erhaltene Käufe zählen nicht als eigener Kauf.
    ///
    /// - Parameter mayDowngrade: Nur nach einem nachweislich erfolgreichen
    ///   `AppStore.sync()` wahr. Ohne diese Zusage darf eine leere Aufzählung
    ///   nichts bedeuten: sie ist beim Start ohne Netz genauso leer wie auf
    ///   einem Gerät, das den Kauf wirklich nicht hat — und ein Merker, den
    ///   der erste Start am Morgen löscht, ist keine Wahrheit, sondern eine
    ///   zweite Kaufaufforderung an jemanden, der schon bezahlt hat.
    static func refresh(mayDowngrade: Bool = false) async {
        let generation = writeGeneration
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.ownershipType == .purchased,
                  transaction.revocationDate == nil
            else { continue }
            unlocked = true
        }
        // Der Lauscher war schneller: seine Meldung ist die jüngere Aussage.
        guard generation == writeGeneration else { return }
        guard unlocked || mayDowngrade else { return }
        cache(unlocked)
    }

    /// Meldungen aus Käufen auf anderen Geräten oder Erstattungen. Ohne
    /// diesen Lauscher bliebe eine Erstattung bis zum nächsten Start unbemerkt.
    ///
    /// `finish()` ist Pflicht: unbeendete Transaktionen meldet StoreKit bei
    /// jedem Start erneut.
    static func startTransactionListener() {
        guard listener == nil else { return }
        listener = Task { @MainActor in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                if transaction.productID == productID,
                   transaction.ownershipType == .purchased {
                    cache(transaction.revocationDate == nil)
                }
                await transaction.finish()
            }
        }
    }

    /// StoreKit emits revocations promptly, but a process can miss an update
    /// while suspended. Re-check the current entitlement while the app is
    /// alive so a revoked purchase relocks observed surfaces without waiting
    /// for a new launch. The guard makes this safe to call from every boot
    /// path and from previews/tests.
    static func startEntitlementMonitor() {
        guard entitlementMonitor == nil else { return }
        entitlementMonitor = Task { @MainActor in
            while !Task.isCancelled {
                await refresh(mayDowngrade: true)
                do {
                    try await Task.sleep(for: entitlementPollInterval)
                } catch {
                    break
                }
            }
        }
    }

    /// Das Produkt für die Kaufseite (echter Preis in echter Währung —
    /// niemals ein hart geschriebener Betrag).
    static func product() async -> Product? {
        try? await Product.products(for: [productID]).first
    }

    /// Kaufen. `true` = ab jetzt freigeschaltet; `false` = der Nutzer hat
    /// abgebrochen oder der Kauf wartet auf die Bestätigung des Stores.
    /// Beides ist kein Fehler und darf keinen Alarm auslösen.
    @discardableResult
    static func purchase() async throws -> Bool {
        guard let product = try await Product.products(for: [productID]).first
        else { throw PurchaseError.productUnavailable }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification
            else { throw PurchaseError.unverified }
            await transaction.finish()
            cache(true)
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Wiederherstellen — Pflichtknopf auf der Kaufseite (App-Store-Regel
    /// 3.1.1). `AppStore.sync()` fragt nach dem Konto-Passwort und zieht die
    /// Historie neu; danach beantwortet `refresh()` die eigentliche Frage.
    ///
    /// **Der Fehler wird weitergereicht, nicht verschluckt.** „Keine
    /// Verbindung" und „auf diesem Konto liegt kein Kauf" sind zwei
    /// verschiedene Aussagen, und nur eine davon stimmt im Zug. Wer die
    /// falsche liest, kauft ein zweites Mal.
    static func restore() async throws {
        try await AppStore.sync()
        // Erst NACH einer echten Antwort des Stores darf herabgestuft
        // werden — hier ist die Aufzählung nachweislich vollständig.
        await refresh(mayDowngrade: true)
    }

    #if DEBUG
    /// Nur Debug: `-pro on|off`. Schreibt den Merker in die App-Group-Defaults
    /// (`simctl defaults write` schreibt an ihnen VORBEI) und klemmt ihn fest,
    /// damit ein laufender `refresh()` ihn nicht überschreibt.
    static func setDebugUnlocked(_ unlocked: Bool) {
        debugOverride = unlocked
        // Invalidate an entitlement refresh that started before the override.
        // The override remains authoritative, but the generation keeps the
        // normal refresh race from becoming observable when it is removed.
        writeGeneration &+= 1
        if unlocked {
            defaults.set(true, forKey: unlockedKey)
        } else {
            defaults.removeObject(forKey: unlockedKey)
        }
        // Auch der Haken muss beobachtbar sein: er wird NACH dem ersten
        // Rumpf gesetzt (handleLaunchScreenArgument läuft nach `boot()`),
        // sonst stünden die Gates im Simulator auf dem Stand von vorher.
        ProStatus.shared.unlocked = unlocked
    }
    #endif
}

/// Die Frage „darf ich das?" — pur, ohne StoreKit, ohne Defaults, ohne
/// Hauptakteur. Deshalb testbar, und deshalb der EINE benannte Prüfpunkt:
/// keine Ansicht rechnet selbst mit `freeHabitLimit`.
///
/// **Das Limit schützt auch einen abgelaufenen Pro-Bestand.** Vorhandene
/// Daten bleiben erhalten und dürfen archiviert oder gelöscht werden. Ein
/// freier Bestand bis zum Limit bleibt editierbar; ein übergroßer Bestand
/// kann erst wieder normal bearbeitet werden, wenn Pro aktiv ist.
enum ProGate {
    /// Drei aktive Habits sind gratis. Archivierte zählen nicht mit — sie
    /// stehen in keiner Liste und kosten keine Aufmerksamkeit.
    static let freeHabitLimit = HabitVisibility.freeHabitLimit

    /// Keep over-limit data in storage, but expose only the free tracked-habit
    /// allowance while Pro is locked. Reminders remain free and ordering stays
    /// stable so reactivation can reveal the preserved entries again.
    static func visibleActiveHabits(_ habits: [Habit], unlocked: Bool) -> [Habit] {
        HabitVisibility.visibleActiveHabits(habits, unlocked: unlocked)
    }

    static func mayAddHabit(activeCount: Int, unlocked: Bool) -> Bool {
        unlocked || activeCount < freeHabitLimit
    }

    /// Reminders can always be created and existing free habits remain
    /// editable. A tracked habit from an expired over-limit Pro set must not
    /// be an escape hatch around the three-habit limit; archive/delete remain
    /// available so the user can reduce the active set.
    static func maySaveTrackedHabit(existingIsTracked: Bool,
                                    targetIsTracked: Bool,
                                    activeCount: Int,
                                    unlocked: Bool) -> Bool {
        guard targetIsTracked else { return true }
        guard !unlocked else { return true }
        if existingIsTracked {
            return activeCount <= freeHabitLimit
        }
        return activeCount < freeHabitLimit
    }

    /// Restoring an archived tracked habit is another creation path. A
    /// reminder stays free, while a tracked habit can return only if the
    /// active free allowance still has room.
    static func mayUnarchiveTrackedHabit(isTracked: Bool,
                                         activeCount: Int,
                                         unlocked: Bool) -> Bool {
        !isTracked || unlocked || activeCount < freeHabitLimit
    }

    /// Imports are a second creation path, so they must be evaluated against
    /// the same active tracked-habit limit as the editor. Existing IDs are
    /// replacements during merge; new reminders and archived entries do not
    /// consume a tracked-habit slot.
    static func mayImport(incoming: HabitData,
                          into local: HabitData,
                          unlocked: Bool) -> Bool {
        guard !unlocked else { return true }

        var merged = Dictionary(uniqueKeysWithValues: local.habits.map { ($0.id, $0) })
        let remoteNewer = incoming.updatedAt > local.updatedAt
        for habit in incoming.habits {
            if merged[habit.id] == nil || remoteNewer {
                merged[habit.id] = habit
            }
        }

        let activeTracked = merged.values.filter {
            $0.archivedAt == nil && $0.isTrackedHabit
        }.count
        return activeTracked <= freeHabitLimit
    }

    /// Trivial — und trotzdem eine eigene Funktion: so heißt jede gegatete
    /// Stelle im Code gleich, und ein späterer Wechsel (Probezeit, Rabatt,
    /// zweites Produkt) hat genau einen Ort.
    static func mayUseProFeature(unlocked: Bool) -> Bool {
        unlocked
    }

    static func restrictedCloudPreferences(_ preferences: CloudPreferences,
                                           unlocked: Bool) -> CloudPreferences {
        guard !unlocked else { return preferences }
        var restricted = preferences
        restricted.calendarSyncHabits = false
        restricted.calendarSyncReminders = false
        restricted.nativeReminderSync = false
        return restricted
    }
}
