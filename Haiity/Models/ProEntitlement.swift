import Foundation
import Observation
import StoreKit

/// Der beobachtbare Speicher hinter `Pro.isUnlocked`.
///
/// **Warum es diese Klasse gibt.** Ein Kauf muss nicht in dieser Ansicht
/// passieren: er kommt vom anderen Gerät, aus einer bestätigten
/// Familien-Kaufanfrage oder als Erstattung — alles Meldungen, die
/// `Transaction.updates` bringt, ohne dass jemand etwas angetippt hätte.
/// `enum Pro` ist statischer Zustand und für SwiftUI unsichtbar; ohne diesen
/// Speicher bliebe die Statistik gesperrt und die Einstellungen böten den
/// Kauf weiter an, bis der Rumpf zufällig aus anderem Grund neu ausgewertet
/// wird. Genau das versprach die Kaufseite bei der Kaufanfrage NICHT zu tun
/// („schaltet sich von selbst frei").
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
/// **Family Sharing kommt geschenkt.** Geteilte Käufe stehen in
/// `currentEntitlements` wie eigene; es gibt hier nichts zu unterscheiden.
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
        return ProStatus.shared.unlocked
    }

    /// Der eine Schreibpunkt. Alles, was StoreKit erfährt, landet hier —
    /// und nur hier steht die Debug-Klammer.
    private static func cache(_ unlocked: Bool) {
        #if DEBUG
        if debugOverride != nil { return }
        #endif
        guard ProStatus.shared.unlocked != unlocked else { return }
        writeGeneration &+= 1
        defaults.set(unlocked, forKey: unlockedKey)
        ProStatus.shared.unlocked = unlocked
    }

    /// Bestand prüfen: was steht heute auf diesem Konto (inkl. Family
    /// Sharing)? Zurückgezogene Käufe (Erstattung) zählen nicht mehr.
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
                  transaction.revocationDate == nil
            else { continue }
            unlocked = true
        }
        // Der Lauscher war schneller: seine Meldung ist die jüngere Aussage.
        guard generation == writeGeneration else { return }
        guard unlocked || mayDowngrade else { return }
        cache(unlocked)
    }

    /// Meldungen, die NICHT aus einem Kauf in dieser App stammen: Kauf auf
    /// einem anderen Gerät, Family-Sharing-Freigabe, Erstattung. Ohne diesen
    /// Lauscher bliebe eine Erstattung bis zum nächsten Start unbemerkt.
    ///
    /// `finish()` ist Pflicht: unbeendete Transaktionen meldet StoreKit bei
    /// jedem Start erneut.
    static func startTransactionListener() {
        guard listener == nil else { return }
        listener = Task { @MainActor in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                if transaction.productID == productID {
                    cache(transaction.revocationDate == nil)
                }
                await transaction.finish()
            }
        }
    }

    /// Das Produkt für die Kaufseite (echter Preis in echter Währung —
    /// niemals ein hart geschriebener Betrag).
    static func product() async -> Product? {
        try? await Product.products(for: [productID]).first
    }

    /// Kaufen. `true` = ab jetzt freigeschaltet; `false` = der Nutzer hat
    /// abgebrochen oder der Kauf wartet auf eine Freigabe (Family Sharing:
    /// „Kaufanfrage"). Beides ist kein Fehler und darf keinen Alarm auslösen.
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
/// **Das Limit greift NUR beim Anlegen.** Bestehende Daten bleiben immer
/// voll nutzbar — wer aus dem Archiv zurückholt, importiert oder von iCloud
/// mehr als drei aktive Habits bekommt, behält sie. Gegated wird die
/// Anlege-Absicht, nicht der Bestand.
enum ProGate {
    /// Drei aktive Habits sind gratis. Archivierte zählen nicht mit — sie
    /// stehen in keiner Liste und kosten keine Aufmerksamkeit.
    static let freeHabitLimit = 3

    static func mayAddHabit(activeCount: Int, unlocked: Bool) -> Bool {
        unlocked || activeCount < freeHabitLimit
    }

    /// Trivial — und trotzdem eine eigene Funktion: so heißt jede gegatete
    /// Stelle im Code gleich, und ein späterer Wechsel (Probezeit, Rabatt,
    /// zweites Produkt) hat genau einen Ort.
    static func mayUseProFeature(unlocked: Bool) -> Bool {
        unlocked
    }
}
