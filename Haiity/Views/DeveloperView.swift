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
    @State private var copiedSyncHint = false

    private enum ImportError: LocalizedError {
        case trackedHabitLimit

        var errorDescription: String? {
            switch self {
            case .trackedHabitLimit:
                return String(localized: "Dieser Import würde das kostenlose Limit von drei aktiven Habits überschreiten. Mit hAiity Pro kannst du ihn vollständig zusammenführen.")
            }
        }
    }

    /// Was angezeigt und kopiert wird. Vor dem Sammeln der leere Stand —
    /// jede ZAHL daraus wird von `count`/`yesNo`/`shortDate` zu `n/a`.
    private var facts: DiagnosticsFacts { collected ?? DiagnosticsFacts() }

    private var isCollected: Bool { collected != nil }

    var body: some View {
        // Not a `List`: iOS 27 drops taps on grouped list rows, and this page
        // is a column of tappable diagnostics and actions.
        ScrollView {
            VStack(spacing: Theme.Metrics.settingsSectionGap) {
                appSection
                dataSection
                cloudSection
                notificationSection
                calendarSection
                proSection
                dataTransferSection
                actionSection
                ownerSection
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.bottom, ChromeLayout.nativeTabBarClearance)
        }
        .scrollIndicators(.hidden)
        .softScrollEdges()
        .settingsChrome()
        .appPageHeader(String(localized: "Entwickler"))
        .task { await collect() }
        .onAppear { appleUserID = PersonalName.appleUserID }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    // MARK: – (1) App

    private var appSection: some View {
        AppSettingsGroup(title: String(localized: "App"), symbol: "app.badge") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                factRow(Text(String(localized: "Version")), facts.appVersion.isEmpty
                        ? nil : "\(facts.appVersion) (\(facts.build))")
                factRow(Text(verbatim: "Bundle-ID"), facts.bundleID)
                factRow(Text(String(localized: "Konfiguration")), facts.configuration)
                factRow(Text(verbatim: "iOS"), facts.systemVersion)
                factRow(Text(String(localized: "Gerät")), facts.deviceModel)
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    // MARK: – (2) Daten

    private var dataSection: some View {
        AppSettingsGroup(title: String(localized: "Daten"), symbol: "externaldrive") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                factRow(Text(String(localized: "Aktive Habits")), count(facts.activeHabits))
                factRow(Text(String(localized: "Archivierte Habits")), count(facts.archivedHabits))
                factRow(Text(String(localized: "Log-Einträge")), count(facts.logEntries))
                factRow(Text(String(localized: "Ältester Tag")), facts.oldestLogDay)
                factRow(Text(verbatim: "data.json"), fileSize)
                factRow(Text(String(localized: "Geändert")), shortDate(facts.dataFileModified))
                factRow(Text(verbatim: "App-Group"), facts.appGroupContainer)
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
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
        AppSettingsGroup(title: "iCloud", symbol: "icloud") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                factRow(Text(String(localized: "Status")), facts.cloudStatus)
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    // MARK: – (4) Mitteilungen

    private var notificationSection: some View {
        AppSettingsGroup(title: String(localized: "Mitteilungen"), symbol: "bell") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
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
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
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
        AppSettingsGroup(title: String(localized: "Kalender"), symbol: "calendar") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            factRow(Text(String(localized: "Habits im Kalender")), yesNo(facts.calendarEnabled))
            factRow(Text(String(localized: "Kalendertitel")), facts.calendarTitle)
            factRow(Text(String(localized: "Gespiegelte Termine")), count(facts.calendarEvents))
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    // MARK: – (6) Pro

    private var proSection: some View {
        AppSettingsGroup(title: "hAiity Pro", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
            factRow(Text(String(localized: "Freigeschaltet")), yesNo(facts.proUnlocked))
            factRow(Text(verbatim: "Produkt-ID"), facts.proProductID)
            factRow(Text(String(localized: "Preis")), facts.proPrice)
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    // MARK: – (7) Aktionen

    private var dataTransferSection: some View {
        AppSettingsGroup(title: String(localized: "Import & Export"), symbol: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
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
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
    }

    private var actionSection: some View {
        AppSettingsGroup(title: String(localized: "Aktionen"), symbol: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
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

            Button(role: .destructive) {
                store.removeBackgroundImage()
                actionMessage = String(localized: "Hintergrundbild entfernt.")
                Theme.Haptics.success()
            } label: {
                Label(String(localized: "Hintergrundbild erzwingen entfernen"),
                      systemImage: "photo.badge.minus")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("force-remove-background-image")

            HStack(spacing: Theme.Metrics.gap) {
                Label(String(localized: "Kennzeichnung für eigene Einträge"),
                      systemImage: "tag")
                Spacer(minLength: Theme.Metrics.gap)
                Button {
                    UIPasteboard.general.string = SyncWatermark.copyText
                    copiedSyncHint = true
                    Theme.Haptics.success()
                } label: {
                    Label(copiedSyncHint ? String(localized: "Kopiert")
                                         : String(localized: "Kopieren"),
                          systemImage: copiedSyncHint ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("copy-sync-watermark")
            }
            .padding(.vertical, 4)

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
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
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
        AppSettingsGroup(title: String(localized: "Besitzer"), symbol: "person.badge.key") {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
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
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
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
                let raw = try Data(contentsOf: url)
                let incoming = try JSONDecoder().decode(HabitData.self, from: raw)
                guard ProGate.mayImport(incoming: incoming,
                                        into: store.data,
                                        unlocked: Pro.isUnlocked) else {
                    throw ImportError.trackedHabitLimit
                }
                try store.importJSON(raw)
                importMessage = String(localized: "Import zusammengeführt.")
                Task { await collect() }
            } catch {
                importMessage = String(localized: "Import fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }

    // MARK: – Zeilen

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
