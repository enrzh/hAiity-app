import StoreKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// Der Entwicklerbereich: was diese Installation über sich selbst weiß.
///
/// **Warum das ein echtes Feature ist und keine Debug-Klammer.** Eine Meldung
/// entsteht nicht auf dem Rechner der Entwicklung, sondern auf dem Gerät
/// eines Menschen mit einem Release-Build aus dem App Store. Genau dort muss
/// diese Seite Auskunft geben können — ein `#if DEBUG` nähme sie ausgerechnet
/// dort weg. Versteckt ist sie trotzdem: hinter sieben Tipps auf die
/// Versionszeile (siehe `DeveloperAccess` und `AboutView`).
///
/// **Was die Seite ZEIGT und was sie KOPIERT, sind zwei Dinge.** Die Anzeige
/// spricht Deutsch (bzw. die Sprache des Geräts), der kopierbare Text spricht
/// feste ASCII-Schlüssel (siehe `DiagnosticsReport`): gelesen wird er dort,
/// wo er ankommt, nicht dort, wo er entsteht.
///
/// **Datenschutz.** Gesammelt wird ausschließlich das, was `DiagnosticsFacts`
/// tragen kann — Zahlen, Zustände, technische Kennungen. Kein Habit-Name,
/// kein Emoji, kein Alias, kein Log-Wert. Aus einer geplanten Mitteilung
/// kommt deshalb NUR `identifier` und Zeitpunkt; `title`/`body` tragen den
/// Habit-Namen und werden hier nicht einmal angefasst.
struct DeveloperView: View {
    let store: HabitStore
    /// Nur Anzeige — die Seite prüft nichts nach und heilt nichts.
    let cloudStatus: CloudSyncStatus

    @Environment(\.dismiss) private var dismiss
    /// Der eingesammelte Stand — `nil`, solange nichts gesammelt ist.
    ///
    /// **Warum optional und nicht einfach ein leerer Stand.** Ein leerer
    /// `DiagnosticsFacts` sieht nicht leer aus: `activeHabits` wäre eine
    /// glatte 0, und die Seite behauptete „keine Habits, keine geplanten
    /// Mitteilungen" über ein Gerät, das sie noch gar nicht gefragt hat.
    /// `nil` sagt stattdessen überall `n/a` — und der Kopierknopf bleibt so
    /// lange stumm, statt einen hohlen Bericht auszugeben.
    @State private var collected: DiagnosticsFacts?
    /// Rückmeldung der Test-Mitteilung — wortgleich mit der Zeile, die
    /// früher in „Mehr" stand.
    @State private var testMessage: String?
    /// Wahr, wenn der letzte Testversuch an der Berechtigung scheiterte —
    /// dann braucht die Seite den Sprung in die iOS-Einstellungen.
    @State private var testFailed = false
    /// Quittung für Kopieren und Widget-Neuladen: eine Aktion ohne sichtbare
    /// Wirkung fühlt sich kaputt an.
    @State private var actionMessage: String?

    /// Was angezeigt und kopiert wird. Vor dem Sammeln der leere Stand —
    /// jede ZAHL daraus wird von `count`/`yesNo`/`shortDate` zu `n/a`.
    private var facts: DiagnosticsFacts { collected ?? DiagnosticsFacts() }

    private var isCollected: Bool { collected != nil }

    var body: some View {
        List {
            appSection
            dataSection
            cloudSection
            notificationSection
            calendarSection
            proSection
            actionSection
            lockSection
        }
        .navigationTitle(String(localized: "Entwickler"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await collect() }
    }

    // MARK: – (1) App

    private var appSection: some View {
        Section {
            factRow(Text(String(localized: "Version")), facts.appVersion.isEmpty
                    ? nil : "\(facts.appVersion) (\(facts.build))")
            factRow(Text(verbatim: "Bundle-ID"), facts.bundleID)
            factRow(Text(String(localized: "Konfiguration")), facts.configuration)
            factRow(Text(verbatim: "iOS"), facts.systemVersion)
            factRow(Text(String(localized: "Gerät")), facts.deviceModel)
        } header: {
            sectionHeader(String(localized: "App"), symbol: "app.badge")
        }
    }

    // MARK: – (2) Daten

    private var dataSection: some View {
        Section {
            factRow(Text(String(localized: "Aktive Habits")), count(facts.activeHabits))
            factRow(Text(String(localized: "Archivierte Habits")), count(facts.archivedHabits))
            factRow(Text(String(localized: "Log-Einträge")), count(facts.logEntries))
            factRow(Text(String(localized: "Ältester Tag")), facts.oldestLogDay)
            factRow(Text(verbatim: "data.json"), fileSize)
            factRow(Text(String(localized: "Geändert")), shortDate(facts.dataFileModified))
            factRow(Text(verbatim: "App-Group"), facts.appGroupContainer)
        } header: {
            sectionHeader(String(localized: "Daten"), symbol: "externaldrive")
        }
    }

    /// Die Dateigröße menschlich („12 KB"); die Zahl in Bytes steht im
    /// kopierten Bericht.
    private var fileSize: String? {
        guard isCollected, let bytes = facts.dataFileBytes else { return nil }
        return Int64(bytes).formatted(.byteCount(style: .file))
    }

    // MARK: – (3) iCloud

    private var cloudSection: some View {
        Section {
            factRow(Text(String(localized: "Status")), facts.cloudStatus)
        } header: {
            sectionHeader("iCloud", symbol: "icloud", localized: false)
        }
    }

    // MARK: – (4) Mitteilungen

    private var notificationSection: some View {
        Section {
            factRow(Text(String(localized: "Berechtigung")), facts.notificationAuthorization)
            factRow(Text(String(localized: "Geplant")), count(facts.pendingNotifications))
            // Kennung und Zeitpunkt — mehr trägt `nextNotifications` nicht,
            // und mehr darf hier auch nicht stehen: der Text einer Mitteilung
            // nennt den Habit beim Namen.
            //
            // Über die INDIZES, nicht über `id: \.id`: Swift kann keinen
            // Schlüsselpfad auf ein Tupel-Element bilden.
            ForEach(facts.nextNotifications.indices, id: \.self) { index in
                factRow(Text(verbatim: facts.nextNotifications[index].id),
                        shortDate(facts.nextNotifications[index].date))
            }
            testNotificationButton
            if let testMessage {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if testFailed || isNotificationAccessDenied { notificationSettingsLink }
        } header: {
            sectionHeader(String(localized: "Mitteilungen"), symbol: "bell")
        } footer: {
            Text(String(localized: "Prüft, ob Mitteilungen von hAiity ankommen."))
        }
    }

    /// Wortgleich mit der Zeile, die bis v17 in „Mehr" stand — sie ist
    /// Diagnose, keine Einstellung, und wohnt deshalb jetzt hier.
    private var testNotificationButton: some View {
        Button {
            testMessage = nil
            Task {
                let ok = await Reminders.scheduleTest()
                await MainActor.run {
                    testMessage = testResult(ok)
                    testFailed = !ok
                }
                // Der Knopf verändert genau die Zahlen, die diese Seite
                // meldet (geplante Mitteilungen und die nächsten fünf) —
                // also wird der Stand danach neu genommen. Sonst verschickte
                // jemand einen Bericht, in dem die eben gestellte Mitteilung
                // fehlt, und die Uhrzeit oben stimmte auch nicht mehr.
                await collect()
            }
        } label: {
            Label(String(localized: "Test-Mitteilung"), systemImage: "bell.badge")
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("test-notification")
    }

    private func testResult(_ ok: Bool) -> String {
        ok ? String(localized: "Kommt in 10 Sekunden — auch bei geöffneter App.")
           : String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert.")
    }

    /// „denied" heißt: kein Knopf in der App richtet noch etwas aus.
    private var isNotificationAccessDenied: Bool {
        facts.notificationAuthorization == Self.deniedToken
    }

    /// Der Ausgang aus der Sackgasse.
    ///
    /// **Warum der Sprung mitziehen musste.** Bis v17 stand die
    /// Test-Mitteilung in „Mehr" und setzte dort bei fehlender Berechtigung
    /// die Fahne, die den Hinweis samt „iOS-Einstellungen öffnen" einblendet.
    /// Nach dem Umzug hierher wäre der Satz „Benachrichtigungen sind
    /// deaktiviert" eine Auskunft ohne Ausweg — und in „Mehr" erscheint der
    /// Hinweis nicht mehr, weil das ein anderes Blatt ist. Gezeigt wird er
    /// auch ungefragt, wenn der gesammelte Stand schon „denied" sagt: dann
    /// ist der Testversuch von vornherein vergeblich.
    private var notificationSettingsLink: some View {
        // Der direkte Sprung statt einer Wegbeschreibung: iOS öffnet die
        // Mitteilungs-Einstellungen DIESER App.
        Button(String(localized: "iOS-Einstellungen öffnen")) {
            guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
                return
            }
            UIApplication.shared.open(url)
        }
        .font(.caption.weight(.semibold))
        .accessibilityIdentifier("open-notification-settings")
    }

    // MARK: – (5) Kalender

    private var calendarSection: some View {
        Section {
            factRow(Text(String(localized: "Habits im Kalender")), yesNo(facts.calendarEnabled))
            factRow(Text(String(localized: "Kalendertitel")), facts.calendarTitle)
            factRow(Text(String(localized: "Gespiegelte Termine")), count(facts.calendarEvents))
        } header: {
            sectionHeader(String(localized: "Kalender"), symbol: "calendar")
        }
    }

    // MARK: – (6) Pro

    private var proSection: some View {
        Section {
            factRow(Text(String(localized: "Freigeschaltet")), yesNo(facts.proUnlocked))
            factRow(Text(verbatim: "Produkt-ID"), facts.proProductID)
            factRow(Text(String(localized: "Preis")), facts.proPrice)
        } header: {
            sectionHeader("hAiity Pro", symbol: "checkmark.seal", localized: false)
        }
    }

    // MARK: – (7) Aktionen

    private var actionSection: some View {
        Section {
            Button {
                WidgetCenter.shared.reloadAllTimelines()
                actionMessage = String(localized: "Widgets neu geladen.")
                Theme.Haptics.success()
            } label: {
                Label(String(localized: "Widgets neu laden"), systemImage: "arrow.clockwise")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("reload-widgets")

            Button {
                // Bewusst das ALLGEMEINE Pasteboard, ohne `.localOnly`: Der
                // Bericht SOLL das Gerät verlassen — der übliche Weg ist,
                // ihn am iPhone zu kopieren und am Mac in eine Mail zu
                // setzen. Ihn auf das Gerät zu sperren nähme dem Knopf genau
                // seinen Zweck. Dass er unterwegs sicher ist, macht nicht
                // die Zwischenablage, sondern sein Inhalt: Zahlen, Zustände,
                // technische Kennungen (siehe `DiagnosticsFacts`).
                UIPasteboard.general.string = DiagnosticsReport.text(facts)
                actionMessage = String(localized: "Diagnose kopiert.")
                Theme.Haptics.success()
            } label: {
                Label(String(localized: "Diagnose kopieren"), systemImage: "doc.on.doc")
            }
            .foregroundStyle(.primary)
            // Nichts gesammelt, nichts zu kopieren: ein Bericht aus lauter
            // `n/a` und glatten Nullen wäre schlimmer als keiner — er sähe
            // aus wie ein Befund.
            .disabled(!isCollected)
            .accessibilityIdentifier("copy-diagnostics")

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader(String(localized: "Aktionen"), symbol: "wrench.and.screwdriver")
        } footer: {
            Text(String(localized: "Der kopierte Text enthält keine Habit-Namen, keine Emojis und keine Werte — nur Zahlen, Zustände und technische Kennungen."))
        }
    }

    private var lockSection: some View {
        Section {
            Button {
                DeveloperAccess.isUnlocked = false
                dismiss()
            } label: {
                Label(String(localized: "Entwicklerbereich ausblenden"), systemImage: "lock")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("lock-developer")
        } footer: {
            Text(String(localized: "Die Seite verschwindet. Sieben Tipps auf die Versionszeile in Über holen sie zurück."))
        }
    }

    // MARK: – Zeilen

    private func sectionHeader(_ title: String, symbol: String,
                               localized: Bool = true) -> some View {
        // `localized: false` ist für Namen, die in keiner Sprache anders
        // heißen (iCloud, hAiity Pro) — sie gehören in keinen Katalog.
        Label {
            localized ? Text(title) : Text(verbatim: title)
        } icon: {
            Image(systemName: symbol)
        }
    }

    /// Eine Tatsache: links die Frage, rechts die Antwort. Fehlt sie, steht
    /// dort dasselbe `n/a` wie im Bericht — ein leeres Feld sähe aus wie ein
    /// Fehler der Seite statt wie ein Befund.
    private func factRow(_ label: Text, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.gap) {
            label
                .font(.subheadline)
            Spacer(minLength: Theme.Metrics.gap)
            Text(valueText(value))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                // Einzelne Werte lassen sich so herausgreifen, ohne den
                // ganzen Bericht zu kopieren (Pfade sind lang).
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func valueText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return DiagnosticsReport.unknown }
        return value
    }

    /// Zahlen als Text — mit Ziffern gleicher Breite (siehe `factRow`), damit
    /// untereinander stehende Werte nicht tanzen.
    ///
    /// Vor dem Sammeln `nil` und damit `n/a`: Eine 0 wäre hier keine Auskunft,
    /// sondern eine Behauptung über etwas, das noch niemand gefragt hat.
    private func count(_ value: Int) -> String? { isCollected ? String(value) : nil }

    private func yesNo(_ value: Bool) -> String? {
        guard isCollected else { return nil }
        return value ? String(localized: "Ja") : String(localized: "Nein")
    }

    private func shortDate(_ date: Date?) -> String? {
        guard isCollected, let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: – Sammeln

    /// Alles einsammeln — und zwar in ZWEI Schritten.
    ///
    /// **Warum der Preis hinterherkommt.** Alles andere ist gerätelokal und
    /// sofort da: Dateiattribute, Defaults, der Mitteilungsdienst.
    /// `Pro.product()` dagegen fragt den App Store — ohne Netz läuft das bis
    /// in den Zeitablauf der URL-Sitzung. Hinge der ganze Stand an dieser
    /// einen Zeile, zeigte die Seite ausgerechnet dann minutenlang nichts,
    /// wenn sie am nötigsten ist: auf einem Gerät ohne Netz, im Moment eines
    /// Fehlerberichts.
    ///
    /// **Warum genau zwei Schreibpunkte.** Der erste setzt einen
    /// vollständigen, in sich stimmigen Stand; der zweite trägt nur den
    /// Preis nach. Ein Bericht aus der Zwischenzeit ist damit nie hohl,
    /// sondern nur um eine Zeile ärmer — und die sagt ehrlich `n/a`.
    @MainActor
    private func collect() async {
        var gathered = DiagnosticsFacts()
        gathered.collectedAt = .now
        fillApp(&gathered)
        fillData(&gathered)
        gathered.cloudStatus = Self.cloudToken(cloudStatus.state)
        await fillNotifications(&gathered)
        fillCalendar(&gathered)
        fillPro(&gathered)
        // Ein bereits geholter Preis überlebt das Auffrischen (nach der
        // Test-Mitteilung wird neu gesammelt) — sonst ginge jedes Mal ein
        // Netzabruf für dieselbe Auskunft raus.
        gathered.proPrice = collected?.proPrice
        collected = gathered
        guard gathered.proPrice == nil else { return }
        collected?.proPrice = await Pro.product()?.displayPrice
    }

    private func fillApp(_ facts: inout DiagnosticsFacts) {
        facts.appVersion = AppBuildInfo.version
        facts.build = AppBuildInfo.build
        facts.bundleID = AppBuildInfo.bundleID
        facts.configuration = DiagnosticsFacts.currentConfiguration
        facts.systemVersion = UIDevice.current.systemVersion
        facts.deviceModel = DiagnosticsFacts.hardwareModel()
    }

    private func fillData(_ facts: inout DiagnosticsFacts) {
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

    private func fillNotifications(_ facts: inout DiagnosticsFacts) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        facts.notificationAuthorization = Self.authorizationToken(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests()
        facts.pendingNotifications = pending.count
        facts.nextNotifications = Self.upcoming(pending)
    }

    private func fillCalendar(_ facts: inout DiagnosticsFacts) {
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

    /// Nur der gerätelokale Kaufzustand — der Preis kommt in `collect()`
    /// hinterher, weil er aus dem Netz kommt.
    private func fillPro(_ facts: inout DiagnosticsFacts) {
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

    /// Der eine Zustand, aus dem die App selbst nicht mehr herausfindet —
    /// als Konstante, damit Anzeige und Bericht nicht auseinanderlaufen.
    private static let deniedToken = "denied"

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
