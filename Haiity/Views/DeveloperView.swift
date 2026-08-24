import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
    /// Eigene Quittung für den Besitzer-Abschnitt — sie steht dort, wo
    /// getippt wurde, statt zwei Abschnitte weiter oben.
    @State private var ownerMessage: String?
    /// Die gespeicherte Apple-Kennung, EINMAL abgelesen. Gespiegelt statt bei
    /// jedem Rumpf gefragt: sie ändert sich nur in „Mehr", und diese Seite
    /// wird beim Zurückkommen ohnehin neu aufgebaut.
    @State private var appleUserID: String?
    @State private var showImporter = false
    @State private var importMessage: String?

    /// Was angezeigt und kopiert wird. Vor dem Sammeln der leere Stand —
    /// jede ZAHL daraus wird von `count`/`yesNo`/`shortDate` zu `n/a`.
    private var facts: DiagnosticsFacts { collected ?? DiagnosticsFacts() }

    private var isCollected: Bool { collected != nil }

    var body: some View {
        List {
            appSection.settingsListRow()
            dataSection.settingsListRow()
            cloudSection.settingsListRow()
            notificationSection.settingsListRow()
            calendarSection.settingsListRow()
            proSection.settingsListRow()
            dataTransferSection.settingsListRow()
            actionSection.settingsListRow()
            ownerSection.settingsListRow()
        }
        .settingsSurface()
        .navigationTitle(String(localized: "Entwickler"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await collect() }
        .onAppear { appleUserID = PersonalName.appleUserID }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
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
        facts.notificationAuthorization == DiagnosticsCollector.deniedToken
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

    private var dataTransferSection: some View {
        Section {
            ShareLink(item: HabitExport(data: store.exportJSON() ?? Data()),
                      preview: SharePreview(String(localized: "hAiity-Export"))) {
                Label(String(localized: "Exportieren"), systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("export-data")

            Button {
                showImporter = true
            } label: {
                Label(String(localized: "Importieren"), systemImage: "square.and.arrow.down")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("import-data")

            if let importMessage {
                Text(importMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader(String(localized: "Import & Export"), symbol: "arrow.up.arrow.down")
        }
    }

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
                store.resetBackground()
                actionMessage = String(localized: "Hintergrund zurückgesetzt.")
                Theme.Haptics.success()
            } label: {
                Label(String(localized: "Hintergrund zurücksetzen"),
                      systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("reset-background")

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
        }
    }

    // MARK: – (8) Besitzer

    /// Wem die Tür gehört — und wie der Besitzer das eintragen kann.
    ///
    /// **Warum diese Zeile überhaupt sichtbar ist.** `DeveloperAccess.
    /// ownerAppleUserID` ist eine eingebaute Konstante. Sie zu setzen setzt
    /// voraus, sie zu KENNEN — und Apple zeigt die Kennung nirgends an. Ohne
    /// diese Zeile wäre der Schlüssel für immer hinter der Tür eingesperrt.
    ///
    /// **Warum sie keinen Namen verrät.** Die Kennung ist eine undurchsichtige
    /// Zeichenfolge, die Apple je (Entwicklerteam, Apple-ID) vergibt; aus ihr
    /// lässt sich kein Mensch ablesen. Sie steht deshalb hier — und trotzdem
    /// NICHT im Diagnosetext: dieser wird verschickt, diese Seite nicht.
    private var ownerSection: some View {
        Section {
            factRow(Text(String(localized: "Apple-Kennung dieses Geräts")),
                    appleUserID ?? String(localized: "Nicht angemeldet"))
            Button {
                guard let appleUserID else { return }
                UIPasteboard.general.string = appleUserID
                ownerMessage = String(localized: "Kennung kopiert.")
                Theme.Haptics.success()
            } label: {
                Label(String(localized: "Kennung kopieren"), systemImage: "doc.on.doc")
            }
            .foregroundStyle(.primary)
            // Ohne Anmeldung gibt es nichts zu kopieren — ein Knopf, der eine
            // leere Zwischenablage hinterlässt, sieht aus wie ein Fehler.
            .disabled(appleUserID == nil)
            .accessibilityIdentifier("copy-apple-user-id")

            if let ownerMessage {
                Text(ownerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader(String(localized: "Besitzer"), symbol: "person.badge.key")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.importJSON(Data(contentsOf: url))
                importMessage = String(localized: "Import zusammengeführt.")
                Task { await collect() }
            } catch {
                importMessage = String(localized: "Import fehlgeschlagen: \(error.localizedDescription)")
            }
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
    /// **Warum das Sammeln selbst im Modell steht.** Denselben Stand braucht
    /// auch das Melde-Blatt (Schütteln): dort wird er verschickt, hier
    /// angezeigt. Zwei Kopien des Sammelcodes wären zwei Listen, die
    /// auseinanderlaufen — und die Datenschutzregel wäre zweimal zu prüfen
    /// (siehe `DiagnosticsCollector`).
    ///
    /// **Warum der Preis hinterherkommt.** Alles andere ist gerätelokal und
    /// sofort da: Dateiattribute, Defaults, der Mitteilungsdienst. Der Preis
    /// kommt aus dem App Store — ohne Netz läuft das bis in den Zeitablauf
    /// der URL-Sitzung. Hinge der ganze Stand an dieser einen Zeile, zeigte
    /// die Seite ausgerechnet dann minutenlang nichts, wenn sie am nötigsten
    /// ist: auf einem Gerät ohne Netz, im Moment eines Fehlerberichts.
    ///
    /// **Warum genau zwei Schreibpunkte.** Der erste setzt einen
    /// vollständigen, in sich stimmigen Stand; der zweite trägt nur den
    /// Preis nach. Ein Bericht aus der Zwischenzeit ist damit nie hohl,
    /// sondern nur um eine Zeile ärmer — und die sagt ehrlich `n/a`.
    @MainActor
    private func collect() async {
        var gathered = await DiagnosticsCollector.local(store: store, cloudStatus: cloudStatus)
        // Ein bereits geholter Preis überlebt das Auffrischen (nach der
        // Test-Mitteilung wird neu gesammelt) — sonst ginge jedes Mal ein
        // Netzabruf für dieselbe Auskunft raus.
        gathered.proPrice = collected?.proPrice
        collected = gathered
        guard gathered.proPrice == nil else { return }
        collected?.proPrice = await DiagnosticsCollector.price()
    }
}
