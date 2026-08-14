import Darwin
import Foundation
import StoreKit
import UIKit
import UserNotifications

/// Version, Build und Bundle-Kennung — an EINER Stelle abgelesen.
///
/// **Warum nicht zweimal `Bundle.main`.** Dieselben Zahlen stehen an zwei
/// Orten: in der Versionszeile unter „Über" (der versteckten Tür) und ganz
/// oben im Diagnosetext. Zwei Ableseorte wären zwei Gelegenheiten, sie
/// verschieden zusammenzusetzen — und dann streiten Meldung und Anzeige
/// darüber, welcher Build gemeint war.
///
/// **Warum im Modell und nicht in einer Ansicht.** Hier steht keine Ansicht,
/// nur ein Ablesen — und ZWEI Ansichten hängen daran (`AboutView` in
/// „Mehr", `DeveloperView`). Läge der Typ in einer der beiden, müsste die
/// andere für zwei Zahlen eine fremde Bildschirmdatei mitnehmen.
enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "" }

    /// „1.0.0 (44)" — unübersetzt, es sind zwei Zahlen.
    static var versionAndBuild: String { "\(version) (\(build))" }

    /// „hAiity 1.0.0 (44)" — der Text der versteckten Tür. Der Markenname
    /// steht in keinem Katalog und heißt in keiner Sprache anders.
    static var versionLine: String { "hAiity \(versionAndBuild)" }
}

/// Die versteckte Tür zum Entwicklerbereich.
///
/// **Warum das KEINE Debug-Klammer ist.** Der Entwicklerbereich ist ein
/// echtes Feature: Er soll genau dort Auskunft geben, wo eine Meldung
/// entsteht — auf dem Gerät eines Menschen, der einen Release-Build aus dem
/// App Store hat. Ein `#if DEBUG` würde ihn ausgerechnet dort wegnehmen. Die
/// Tür ist deshalb nicht der Übersetzer, sondern eine Geste, auf die niemand
/// zufällig kommt: sieben Tipps auf die Versionszeile.
///
/// **Warum `UserDefaults.standard` und nicht die App-Group.** Die
/// Freischaltung ist eine Aussage über DIESES Gerät und DIESE App, kein
/// Datum, das jemand mitspiegeln oder das Widget lesen müsste. In der
/// App-Group läge sie im selben Topf wie Kauf- und Kalender-Zustand und wäre
/// später schwerer wieder loszuwerden.
///
/// **Warum die Zählung hier pur ist.** `hint(for:)` und `next(taps:)` fassen
/// die Defaults NICHT an — sie rechnen nur. Geschrieben wird ausschliesslich
/// über `isUnlocked`, und zwar vom Aufrufer. So ist die Fortschaltung ohne
/// Ablage prüfbar, und es gibt genau EINEN Schreibpunkt.
enum DeveloperAccess {
    /// Sieben — genug, dass es kein Versehen ist, wenig genug, dass eine
    /// Anleitung am Telefon („tipp siebenmal auf die Version") funktioniert.
    static let tapsRequired = 7

    /// Ab diesem Tipp läuft der Countdown mit. Vorher bleibt die Zeile
    /// stumm, sonst wäre die Tür keine versteckte mehr.
    static let hintStartsAtTap = 4

    static let unlockedKey = "developerUnlocked"

    static var isUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: unlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: unlockedKey) }
    }

    /// Der dezente Countdown unter der Versionszeile — `nil` heisst: nichts
    /// anzeigen.
    ///
    /// `taps` ist die Zahl der BEREITS getätigten Tipps. Bis einschliesslich
    /// drei schweigt die Zeile; ab dem vierten Tipp nennt sie die Restzahl;
    /// ist die Tür offen (oder wurde übersprungen), schweigt sie wieder —
    /// ein „Noch 0 Tipps" wäre eine Lüge über einen Zustand, der schon
    /// eingetreten ist.
    static func hint(for taps: Int) -> String? {
        guard taps >= hintStartsAtTap, taps < tapsRequired else { return nil }
        let remaining = tapsRequired - taps
        if remaining == 1 { return String(localized: "Noch ein Tipp …") }
        return String(localized: "Noch \(remaining) Tipps …")
    }

    /// Ein Tipp weiter — reine Zustandsfortschaltung, ohne Ablage.
    ///
    /// Beim Erreichen meldet sie `unlocked` UND setzt den Zähler zurück auf
    /// 0: Wer den Bereich später wieder ausblendet, fängt sonst mit einem
    /// vollen Zähler an und wäre nach einem einzigen Tipp wieder drin.
    /// Negative Werte (nur aus Fehlgebrauch möglich) werden auf 0 geklemmt.
    static func next(taps: Int) -> (taps: Int, unlocked: Bool) {
        let raised = max(0, taps) + 1
        guard raised >= tapsRequired else { return (raised, false) }
        return (0, true)
    }

    // MARK: – Wem die Tür gehört

    /// Built-in owner identity. The opaque Apple user ID can replace the
    /// email comparison later once it is known.
    static let ownerAppleUserID: String? = nil
    static let ownerAppleEmail = "xianjie.zhan@icloud.com"

    /// Ist der Entwicklerbereich auf DIESEM Gerät erreichbar?
    ///
    /// The verified owner identity is checked at both navigation boundaries,
    /// so a stale local developer flag cannot grant access to another account.
    static func isAvailable(storedAppleUserID: String?, storedAppleEmail: String?) -> Bool {
        isOwnerDevice(storedAppleUserID: storedAppleUserID,
                      storedAppleEmail: storedAppleEmail)
    }

    /// Gehört DIESES Gerät dem Besitzer?
    ///
    /// Rein und prüfbar: der Aufrufer reicht `PersonalName.appleUserID`
    /// herein, hier wird nur verglichen.
    ///
    static func isOwnerDevice(storedAppleUserID: String?, storedAppleEmail: String?) -> Bool {
        let storedID = storedAppleUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerID = ownerAppleUserID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ownerID, !ownerID.isEmpty, storedID == ownerID { return true }

        let storedEmail = storedAppleEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return storedEmail == ownerAppleEmail.lowercased()
    }
}

/// Alles, was der Entwicklerbereich über diese Installation weiss — als
/// reine Werte, ohne Ansicht, ohne Dienst, ohne Uhr.
///
/// **Die Struktur IST die Datenschutzregel.** Ein Diagnosetext landet per
/// Zwischenablage in fremden Händen: in einer Mail, einem Forum, einem
/// Ticket. Deshalb gibt es hier keine Felder für Habit-Namen, für das
/// Zeichen eines Habits, für den Alias/Apple-Namen und für Log-Werte — nicht
/// „wir schreiben sie nicht raus", sondern „sie kommen gar nicht erst an".
/// Was ein Bericht nicht halten kann, kann er nicht verraten.
///
/// **Achtung beim Befüllen:** Aus einer Mitteilung darf NUR die Kennung und
/// der Zeitpunkt kommen. `title`/`body` einer `UNNotificationRequest` tragen
/// den Habit-Namen („Zeit für …") und gehören hier nirgends hin.
///
/// Alle Felder haben Vorgaben, damit ein Test genau die Ecke bauen kann, die
/// er prüft, ohne zwanzig Werte zu erfinden.
struct DiagnosticsFacts {

    // MARK: – Der Bericht über sich selbst

    /// Wann dieser Stand genommen wurde.
    ///
    /// **Warum ein Bericht seine eigene Uhrzeit braucht.** Jede Zeile hier
    /// ist eine Aussage über EINEN Moment. „notifications.next.1: …
    /// 06:00:00Z" beantwortet ohne diesen Zeitpunkt nicht einmal, ob der
    /// Wecker noch bevorsteht oder längst durch ist; „notifications.pending:
    /// 9" nicht, ob es vor oder nach der Test-Mitteilung gezählt wurde. Der
    /// Zeitpunkt des Sammelns ist dabei nichts über den Menschen am Gerät —
    /// er ist die Sekunde, in der jemand einen Fehler melden wollte.
    var collectedAt: Date?

    // MARK: – App

    var appVersion: String = ""
    var build: String = ""
    var bundleID: String = ""
    /// „Debug" oder „Release" — siehe `currentConfiguration`.
    var configuration: String = ""
    var systemVersion: String = ""
    /// Hardware-Kennung wie `iPhone17,1` (siehe `hardwareModel()`).
    var deviceModel: String = ""

    // MARK: – Daten

    var activeHabits: Int = 0
    var archivedHabits: Int = 0
    /// Summe aller Log-Einträge über alle Habits — eine ZAHL, keine Werte.
    var logEntries: Int = 0
    /// Ältester Tagesschlüssel (`JJJJ-MM-TT`, siehe `DayKey`), nicht der
    /// Eintrag dazu.
    var oldestLogDay: String?
    var dataFileBytes: Int?
    var dataFileModified: Date?
    /// NUR der letzte Teil des App-Group-Pfads (siehe `containerToken`) —
    /// nie der ganze Pfad.
    var appGroupContainer: String?

    // MARK: – iCloud

    /// Kurzer technischer Zustand (z. B. „active", „signedOut") — die
    /// Ansicht kennt `CloudState`, der Bericht nur diesen einen Wert.
    var cloudStatus: String = ""

    // MARK: – Mitteilungen

    var notificationAuthorization: String = ""
    var pendingNotifications: Int = 0
    /// Die nächsten geplanten Wecker. Kennung + Zeitpunkt, sonst nichts.
    var nextNotifications: [(id: String, date: Date)] = []

    // MARK: – Kalender

    var calendarEnabled: Bool = false
    /// Titel des Kalenders, den hAiity WIRKLICH führt — abgelesen über die
    /// gemerkte Kennung, also nie ein fremder Kalender und nie eine
    /// Termindatei. `nil` heißt: es gibt keinen (kein Zugriff, keine Quelle)
    /// — und das ist die Antwort auf „meine Habits stehen nicht im Kalender".
    var calendarTitle: String?
    /// Anzahl der Habits, für die eine Serie im Kalender liegt — je Eintrag
    /// EINE Wiederholungsserie, nicht ein einzelner Tag.
    var calendarEvents: Int = 0

    // MARK: – Pro

    var proUnlocked: Bool = false
    var proProductID: String = ""
    var proPrice: String?

    /// Debug oder Release — die einzige Stelle im Projekt, an der `#if DEBUG`
    /// etwas BERICHTET statt etwas wegzulassen. Ohne diese Zeile rät man bei
    /// jeder Meldung, welcher Build gemeint ist.
    static var currentConfiguration: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }

    /// Aus dem App-Group-Pfad wird nur sein LETZTER Teil — die Kennung des
    /// Containers (`28A6DD4E-…`) bzw. die Group-ID (`group.com.aiity.haiity`).
    ///
    /// **Warum nicht der ganze Pfad.** Auf dem iPhone ist er harmlos
    /// (`/private/var/mobile/Containers/Shared/AppGroup/<UUID>`). Im
    /// Simulator und unter „iPhone Apps on Mac" beginnt derselbe Pfad
    /// dagegen im HEIMATVERZEICHNIS — und der Kurzname eines Mac-Kontos ist
    /// regelmäßig der Vorname eines Menschen. Der Bericht verspricht „nur
    /// Zahlen, Zustände und technische Kennungen"; der letzte Teil hält
    /// dieses Versprechen und beantwortet dieselbe Frage: welchen Container
    /// benutzt diese Installation, und gibt es ihn überhaupt.
    static func containerToken(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let token = URL(fileURLWithPath: path).lastPathComponent
        return token.isEmpty || token == "/" ? nil : token
    }

    /// Hardware-Kennung (`iPhone17,1`), im Simulator die des simulierten
    /// Geräts.
    ///
    /// Bewusst über `sysctl` statt `UIDevice`: Letzteres sagt nur „iPhone"
    /// und zieht ausserdem UIKit in eine reine Modelldatei. Die Umgebung ist
    /// ein Parameter, damit der Simulator-Zweig prüfbar ist.
    static func hardwareModel(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [UInt8](repeating: 0, count: size)
        let read = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("hw.machine", buffer.baseAddress, &size, nil, 0)
        }
        guard read == 0 else { return "" }
        let text = bytes.prefix { $0 != 0 }
        return String(decoding: text, as: UTF8.self)
    }
}

/// Der kopierbare Diagnosetext.
///
/// **Warum feste, unübersetzte Schlüssel.** Der Text wird nicht gelesen, wo
/// er entsteht, sondern wo er ankommt — bei der Entwicklung. Eine auf Urdu
/// übersetzte Diagnose beantwortet dort keine Frage mehr, und ein Test, der
/// auf übersetzte Beschriftungen zeigt, misst die Sprache der Maschine statt
/// des Berichts. Übersetzt wird die SEITE, nicht ihr Auszug.
///
/// **Warum die Zeilenreihenfolge fest ist.** Zwei Meldungen desselben
/// Fehlers sollen sich untereinander legen lassen. Deshalb kommt jede Zeile
/// immer, auch wenn ihr Wert fehlt — dann eben als `n/a`.
enum DiagnosticsReport {
    /// Steht für „gibt es hier nicht" — ein fehlender Wert ist selbst ein
    /// Befund und darf keine Zeile verschlucken.
    static let unknown = "n/a"

    /// Obergrenze für die aufgeführten Wecker. Der Bericht geht in eine
    /// Zwischenablage, nicht in ein Protokoll; hundert Zeilen Wecker wären
    /// die Nadel im eigenen Heuhaufen.
    static let maxNextNotifications = 5

    static func text(_ facts: DiagnosticsFacts) -> String {
        var lines: [String] = ["hAiity Diagnose"]
        // Ganz oben, weil alles darunter eine Aussage über DIESEN Moment ist.
        lines.append(line("report.collected", facts.collectedAt))
        lines += appLines(facts)
        lines += dataLines(facts)
        lines.append(line("cloud.status", facts.cloudStatus))
        lines += notificationLines(facts)
        lines += calendarLines(facts)
        lines += proLines(facts)
        return lines.joined(separator: "\n")
    }

    /// UTC statt Ortszeit: Der Zeitstempel wird woanders gelesen als dort,
    /// wo er entstand — mit Zeitzone des Absenders wäre er nur ein Rätsel.
    static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    // MARK: – Abschnitte

    private static func appLines(_ facts: DiagnosticsFacts) -> [String] {
        [line("app.version", facts.appVersion),
         line("app.build", facts.build),
         line("app.bundle", facts.bundleID),
         line("app.configuration", facts.configuration),
         line("app.ios", facts.systemVersion),
         line("app.device", facts.deviceModel)]
    }

    private static func dataLines(_ facts: DiagnosticsFacts) -> [String] {
        [line("data.habits.active", facts.activeHabits),
         line("data.habits.archived", facts.archivedHabits),
         line("data.log.entries", facts.logEntries),
         line("data.log.oldest", facts.oldestLogDay),
         line("data.file.bytes", facts.dataFileBytes),
         line("data.file.modified", facts.dataFileModified),
         line("data.appgroup", facts.appGroupContainer)]
    }

    private static func notificationLines(_ facts: DiagnosticsFacts) -> [String] {
        var lines = [line("notifications.authorization", facts.notificationAuthorization),
                     line("notifications.pending", facts.pendingNotifications)]
        let next = facts.nextNotifications.prefix(maxNextNotifications)
        guard !next.isEmpty else {
            lines.append(line("notifications.next", nil as String?))
            return lines
        }
        for (index, entry) in next.enumerated() {
            let value = "\(entry.id) \(timestamp(entry.date))"
            lines.append(line("notifications.next.\(index + 1)", value))
        }
        return lines
    }

    private static func calendarLines(_ facts: DiagnosticsFacts) -> [String] {
        [line("calendar.enabled", facts.calendarEnabled),
         line("calendar.title", calendarTitleToken(facts.calendarTitle)),
         line("calendar.events", facts.calendarEvents)]
    }

    /// Was von einem umbenannten Kalender im Bericht übrig bleibt.
    ///
    /// **Warum der Titel nicht roh hinausgeht.** Er ist der einzige Wert im
    /// ganzen Bericht, den ein Mensch frei tippen kann: iOS lässt jeden
    /// Kalender in der Kalender-App umbenennen. Aus „hAiity" wird dann
    /// „Enricos Gewohnheiten 🌱" — ein Name und ein Zeichen, also genau das,
    /// was dieser Bericht laut seinem eigenen Versprechen NICHT trägt. Und
    /// dieses Versprechen ist kein Text im Blatt, sondern die Bauart: was
    /// nicht hinausgeht, kann nichts verraten.
    ///
    /// **Warum die Auskunft trotzdem vollständig bleibt.** Gefragt ist nie,
    /// WIE der Kalender heisst, sondern ob es noch der von hAiity angelegte
    /// ist — ein umbenannter wird beim nächsten Anlegen nicht wiedergefunden
    /// (siehe `CalendarSync`). `hAiity` heisst „unverändert", `renamed` heisst
    /// „umbenannt", `n/a` heisst „keiner da". Drei Antworten auf drei Fragen,
    /// und keine davon braucht den Namen selbst.
    static func calendarTitleToken(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed == CalendarSync.calendarTitle ? trimmed : "renamed"
    }

    private static func proLines(_ facts: DiagnosticsFacts) -> [String] {
        [line("pro.unlocked", facts.proUnlocked),
         line("pro.product", facts.proProductID),
         line("pro.price", facts.proPrice)]
    }

    // MARK: – Eine Zeile

    /// Werte werden EINZEILIG gemacht: Ein Zustand darf eine ganze Meldung
    /// mitbringen (iCloud tut das), und ein Zeilenumbruch mittendrin würde
    /// die feste Reihenfolge zerlegen, an der sich zwei Meldungen
    /// vergleichen lassen.
    private static func line(_ key: String, _ value: String?) -> String {
        let raw = value ?? ""
        let flat = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return "\(key): \(trimmed.isEmpty ? unknown : trimmed)"
    }

    private static func line(_ key: String, _ value: Int?) -> String {
        line(key, value.map { String($0) })
    }

    private static func line(_ key: String, _ value: Bool) -> String {
        line(key, value ? "true" : "false")
    }

    private static func line(_ key: String, _ value: Date?) -> String {
        line(key, value.map { timestamp($0) })
    }
}

/// Das Einsammeln — an EINER Stelle, für ZWEI Oberflächen.
///
/// **Warum das nicht mehr in der Entwicklerseite steht.** Seit dem
/// Melde-Blatt (Schütteln) gibt es zwei Orte, die denselben Stand brauchen:
/// die Seite, die ihn ANZEIGT, und das Blatt, das ihn VERSCHICKT. Zweimal
/// derselbe Sammelcode wären zwei Listen, die auseinanderlaufen — und die
/// Datenschutzregel („keine Habit-Namen, keine Zeichen, keine Werte") wäre
/// zweimal zu prüfen statt einmal. Genau eine dieser beiden Kopien würde
/// beim nächsten neuen Feld vergessen.
///
/// **Warum trotzdem hier und nicht in einem Dienst.** Was gesammelt wird,
/// steht in `DiagnosticsFacts`; wie es zu Text wird, in `DiagnosticsReport`.
/// Das Sammeln gehört dazwischen und damit in dieselbe Datei — es ist die
/// Antwort auf die Frage, die beide Typen offen lassen: woher kommen die
/// Werte.
///
/// **Datenschutz.** Es wird ausschließlich befüllt, was `DiagnosticsFacts`
/// tragen kann: Zahlen, Zustände, technische Kennungen. Aus einer geplanten
/// Mitteilung kommt NUR `identifier` und der Zeitpunkt — Titel und Text
/// tragen den Habit-Namen und werden hier nicht einmal angefasst.
@MainActor
enum DiagnosticsCollector {
    /// Der eine Zustand, aus dem die App selbst nicht mehr herausfindet —
    /// als Konstante, damit Anzeige und Bericht nicht auseinanderlaufen.
    static let deniedToken = "denied"

    /// Alles, was auf DIESEM Gerät sofort abzulesen ist.
    ///
    /// **Warum der Preis nicht dabei ist.** Alles hier ist gerätelokal und
    /// ohne Wartezeit da: Dateiattribute, Defaults, der Mitteilungsdienst.
    /// `Pro.product()` dagegen fragt den App Store und läuft ohne Netz bis in
    /// den Zeitablauf der URL-Sitzung. Hinge der ganze Stand an dieser einen
    /// Zeile, zeigte die Entwicklerseite minutenlang nichts und das
    /// Melde-Blatt einen leeren Anhang — ausgerechnet in der Lage, in der
    /// jemand einen Fehler meldet: auf einem Gerät ohne Netz. Deshalb ist der
    /// Preis ein eigener Schritt (`price()`), den jede Oberfläche selbst
    /// entscheidet.
    static func local(store: HabitStore, cloudStatus: CloudSyncStatus) async -> DiagnosticsFacts {
        var facts = DiagnosticsFacts()
        // Ganz zuerst: alles Folgende ist eine Aussage über DIESEN Moment.
        facts.collectedAt = .now
        fillApp(&facts)
        fillData(&facts, store: store)
        facts.cloudStatus = cloudToken(cloudStatus.state)
        await fillNotifications(&facts)
        fillCalendar(&facts)
        fillPro(&facts)
        return facts
    }

    /// Der Preis aus dem App Store — der einzige Wert, der über das Netz geht.
    static func price() async -> String? {
        await Pro.product()?.displayPrice
    }

    private static func fillApp(_ facts: inout DiagnosticsFacts) {
        facts.appVersion = AppBuildInfo.version
        facts.build = AppBuildInfo.build
        facts.bundleID = AppBuildInfo.bundleID
        facts.configuration = DiagnosticsFacts.currentConfiguration
        facts.systemVersion = UIDevice.current.systemVersion
        facts.deviceModel = DiagnosticsFacts.hardwareModel()
    }

    private static func fillData(_ facts: inout DiagnosticsFacts, store: HabitStore) {
        let habits = store.habits
        facts.activeHabits = habits.filter { $0.archivedAt == nil }.count
        facts.archivedHabits = habits.filter { $0.archivedAt != nil }.count
        // Nur die ANZAHL und der älteste Schlüssel: was an einem Tag steht,
        // geht einen Bericht nichts an.
        facts.logEntries = habits.reduce(0) { $0 + $1.log.count }
        facts.oldestLogDay = habits.flatMap { $0.log.keys }.min()
        let attributes = try? FileManager.default.attributesOfItem(atPath: store.url.path)
        facts.dataFileBytes = (attributes?[.size] as? NSNumber)?.intValue
        facts.dataFileModified = attributes?[.modificationDate] as? Date
        // Nur der letzte Pfadteil (siehe `containerToken`): der ganze Pfad
        // fängt im Simulator und unter „iPhone Apps on Mac" im
        // Heimatverzeichnis an und trüge den Kontonamen in einen fremden
        // Ticket-Thread.
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStorage.appGroup)?.path
        facts.appGroupContainer = DiagnosticsFacts.containerToken(container)
    }

    private static func fillNotifications(_ facts: inout DiagnosticsFacts) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        facts.notificationAuthorization = authorizationToken(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests()
        facts.pendingNotifications = pending.count
        facts.nextNotifications = upcoming(pending)
    }

    private static func fillCalendar(_ facts: inout DiagnosticsFacts) {
        facts.calendarEnabled = CalendarSync.isEnabled
        // GELESEN, nicht behauptet: `CalendarSync.calendarTitle` ist die
        // Konstante, mit der ein Kalender angelegt wird — sie stünde auch
        // dann hier, wenn es gar keinen gibt. `activeCalendarTitle` schlägt
        // die gemerkte Kennung nach; `n/a` heißt dann „kein Kalender", und
        // genau deswegen öffnet jemand diese Seite.
        facts.calendarTitle = CalendarSync.activeCalendarTitle
        // Die Zuordnung Habit → Serie liegt in den App-Group-Defaults; hier
        // interessiert nur, WIE VIELE Habits gespiegelt sind. Die Karte
        // bleibt stehen, wenn der Nutzer den Kalenderzugriff entzieht — der
        // dann fehlende Titel (`n/a`) ist das Zeichen dafür, dass die Zahl
        // von gestern ist.
        let defaults = UserDefaults(suiteName: SharedStorage.appGroup)
        let map = defaults?.dictionary(forKey: CalendarSync.mapKey) as? [String: String]
        facts.calendarEvents = map?.count ?? 0
    }

    /// Nur der gerätelokale Kaufzustand — der Preis kommt über `price()`.
    private static func fillPro(_ facts: inout DiagnosticsFacts) {
        facts.proUnlocked = Pro.isUnlocked
        facts.proProductID = Pro.productID
    }

    // MARK: – Übersetzungen in technische Kürzel
    //
    // Die Anzeige spricht die Sprache des Geräts, die WERTE hier bleiben
    // englische Kennungen: sie stehen so auch im kopierten Bericht, und wer
    // ihn liest, sucht nach „denied", nicht nach „abgelehnt".

    /// Der Zustand als Kürzel — und bei den beiden Störfällen zusätzlich der
    /// Satz, den das System dazu geliefert hat.
    ///
    /// **Warum hier eine übersetzte Stelle bleibt.** Das KÜRZEL steht vorn
    /// und ist immer ASCII (`waiting`, `failed`) — danach lässt sich sortieren
    /// und vergleichen. Der angehängte Satz kommt aus CloudKit
    /// (`localizedDescription`) und spricht die Sprache des Geräts. Er bleibt
    /// trotzdem drin, weil er der EINZIGE Weg ist, „iCloud-Speicher voll" von
    /// „Netz weg" zu unterscheiden; ihn wegzuwerfen machte aus zwei sehr
    /// verschiedenen Fehlerberichten denselben. Eine Zeile in einer fremden
    /// Sprache ist übersetzbar — eine fehlende Ursache nicht.
    private static func cloudToken(_ state: CloudState) -> String {
        switch state {
        case .active(let date):
            guard let date else { return "active" }
            return "active \(DiagnosticsReport.timestamp(date))"
        case .signedOut: return "signedOut"
        case .waiting(let reason): return "waiting: \(reason)"
        case .failed(let message): return "failed: \(message)"
        }
    }

    private static func authorizationToken(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return deniedToken
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    /// Die nächsten Wecker, früheste zuerst.
    ///
    /// Aus jeder Anfrage kommt AUSSCHLIESSLICH `identifier` und der nächste
    /// Zeitpunkt. Wecker ohne bestimmbaren Zeitpunkt (Ortsauslöser gibt es
    /// hier nicht, aber die API kennt sie) fallen heraus, statt mit einem
    /// erfundenen Datum dazustehen.
    private static func upcoming(_ requests: [UNNotificationRequest]) -> [(id: String, date: Date)] {
        var entries: [(id: String, date: Date)] = []
        for request in requests {
            guard let date = fireDate(request.trigger) else { continue }
            entries.append((id: request.identifier, date: date))
        }
        entries.sort { $0.date < $1.date }
        return Array(entries.prefix(DiagnosticsReport.maxNextNotifications))
    }

    private static func fireDate(_ trigger: UNNotificationTrigger?) -> Date? {
        if let calendar = trigger as? UNCalendarNotificationTrigger {
            return calendar.nextTriggerDate()
        }
        if let interval = trigger as? UNTimeIntervalNotificationTrigger {
            return interval.nextTriggerDate()
        }
        return nil
    }
}
