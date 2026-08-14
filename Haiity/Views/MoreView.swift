import Combine
import SwiftUI
import UniformTypeIdentifiers
import AuthenticationServices

/// Bildschirmartige Unterziele des Mehr-Bereichs — wertbasiert, damit
/// Deep-Links (haiity://stats, haiity://archive) direkt hinspringen können.
/// `Identifiable`, weil sie als `.sheet(item:)` präsentiert werden: in der
/// Tafel über der Leiste ist für eine eigene Seite kein Platz.
/// `developer` ist kein Deep-Link-Ziel und steht in keiner Liste: dorthin
/// führt nur die versteckte Tür in `AboutView` (sieben Tipps auf die
/// Versionszeile), und zwar als SCHUB im Blatt darüber — ein zweites Blatt
/// aus einem offenen Blatt heraus verschluckt iOS. Als Route zählt sie
/// trotzdem, damit `moreDestination` der EINE Ort bleibt, an dem steht,
/// welche Seite hinter welchem Ziel liegt.
enum MoreRoute: Hashable, Identifiable {
    case archive, about, developer

    var id: Self { self }
}

/// "Mehr": iCloud-Status, Darstellung, Graph-Farbe, die beiden
/// Zusammenfassungen (Tag und Woche), Statistik, Archiv, Export/Import und
/// Über/Datenschutz.
///
/// Wohnt auf der MEHR-SEITE (fullScreenCover aus dem Menü oben rechts,
/// siehe ContentView.morePage) — wieder eine eigene Seite mit
/// System-Navigationsleiste. Die drei seitenartigen Ziele bleiben Knöpfe,
/// die ein Blatt öffnen (`onOpen`), präsentiert vom Aufrufer ÜBER der Seite.
///
/// **`Equatable`.** Verglichen wird nur, worauf die Ansicht ZEIGT; echte
/// Änderungen an den Daten kommen über Observation an und nicht über diesen
/// Vergleich. (Stammt aus der Tafel-Zeit, kostet nichts und bleibt.)
struct MoreView: View, Equatable {
    static func == (a: MoreView, b: MoreView) -> Bool {
        a.store === b.store && a.cloudStatus === b.cloudStatus
            && a.statsCards === b.statsCards && a.routeToken == b.routeToken
    }

    let store: HabitStore
    /// Nur Anzeige: es gibt nichts einzurichten. Entweder iCloud läuft, oder
    /// die Zeile sagt, warum nicht.
    let cloudStatus: CloudSyncStatus
    /// Auswahl der Statistik-Karten über der Liste (höchstens zwei).
    let statsCards: StatsCardStore
    /// Ein seitenartiges Ziel öffnen (Statistik, Archiv, Über).
    let onOpen: (MoreRoute) -> Void
    /// Zählt die eingetroffenen Deep-Links (siehe ContentView). Ein Link ist
    /// eine Absage an das, was gerade offen ist: der Tab wechselt unter dem
    /// Kaufblatt, und ohne dieses Signal bliebe der Nutzer auf einer
    /// Kaufseite sitzen, die zu einem Bereich gehört, den er verlassen hat.
    var routeToken: Int = 0

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var summaryDenied = false
    @State private var calendarDenied = false
    @State private var weeklyDenied = false
    @State private var motivationDenied = false
    @State private var showReminderSetup = false
    // App-Icon-Auswahl: was der Homescreen gerade zeigt, und ob der letzte
    // Wechsel scheiterte (supportsAlternateIcons == false o. ä.).
    @State private var currentIconName: String?
    @State private var iconChangeFailed = false
    @State private var aliasDraft = ""
    @State private var storedAppleName: String?
    /// Gespiegelt statt bei jedem Rumpf gelesen: `ShakeToReport` ist eine
    /// stumme Ablage, keine beobachtbare Quelle — ohne diesen Zustand spränge
    /// der Schalter nach dem Umlegen optisch zurück.
    @State private var shakeToReport = true
    @State private var appleSignInCameBackEmpty = false
    @Environment(\.colorScheme) private var colorScheme
    /// Startwert = Petrol: bewusst KEINE der 18 Ankerfarben, damit die
    /// Vorschau sofort zeigt, dass frei gewählt und ehrlich gerundet wird.
    @State private var freeIconColor: Color = Theme.color(0x0F766E)
    // Eigene Farben: anlegen, bearbeiten, umbenennen, löschen.
    @State private var creatingPalette = false
    @State private var editingPalette: CustomPalette?
    @State private var renamingPalette: CustomPalette?
    @State private var renameText = ""
    @State private var deletingPalette: CustomPalette?
    /// Das Kaufblatt: `nil` heisst geschlossen. Der Kontext bestimmt nur die
    /// Kopfzeile — vier Zeilen dieser Seite können es öffnen.
    @State private var paywall: PaywallContext?
    /// Die Absicht, die das Kaufblatt unterbrochen hat — gesetzt NUR, wenn
    /// der Kauf wirklich vorliegt. Sie wird beim Zufahren des Blatts
    /// ausgeführt: bezahlen und dann vor demselben Schloss stehen ist der
    /// Moment, in dem sich ein Kauf wie ein Fehler anfühlt.
    @State private var purchased: PaywallContext?
    @Environment(\.palettes) private var palettes

    /// Der eine Lesepunkt dieser Seite — und ein beobachtbarer (siehe
    /// `ProStatus`). Bewusst KEIN gespiegelter Zustand: der Kauf kann von
    /// einem anderen Blatt, einem anderen Gerät oder aus einer bestätigten
    /// Familien-Kaufanfrage kommen, und dann müssen die Schlösser hier
    /// trotzdem aufgehen.
    private var unlocked: Bool { Pro.isUnlocked }

    private var archivedCount: Int { store.habits.filter { $0.archivedAt != nil }.count }

    var body: some View {
        #if DEBUG
        FrameProbe.shared.mark("MoreView.body")
        #endif
        return List {
            Group {
            Section {
                iCloudRow
            } footer: {
                Text(String(localized: "Deine Habits liegen auf diesem Gerät. Ist es bei iCloud angemeldet, spiegelt hAiity sie zusätzlich in deine private iCloud — nichts einzurichten, kein Konto bei uns, kein Server bei uns."))
            }

            proSection

            appearanceSection
            paletteSection

            compactModeSection
            swipeActionsSection

            calendarSection

            personalSection

            dailySummarySection
            weeklySummarySection
            motivationSection
            // „Test-Mitteilung" stand hier. Sie ist Diagnose, keine
            // Einstellung — und wohnt jetzt im Entwicklerbereich
            // (DeveloperView), wortgleich und mit derselben Kennung.
            Section {
                Button { showReminderSetup = true } label: {
                    Label(String(localized: "Erinnerungen einrichten"), systemImage: "bell")
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-reminder-setup")
            }

            Section {
                pageRow(.archive, title: String(localized: "Archiv"),
                        symbol: "archivebox", identifier: "open-archive",
                        badge: archivedCount > 0 ? "\(archivedCount)" : nil)
            }

            Section {
                ShareLink(item: HabitExport(data: store.exportJSON() ?? Data()),
                          preview: SharePreview(String(localized: "hAiity-Export"))) {
                    Label(String(localized: "Exportieren"), systemImage: "square.and.arrow.up")
                }
                // ShareLink zieht sich sonst den Tint und leuchtet grün,
                // während "Importieren" daneben neutral bleibt.
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
            } footer: {
                Text(String(localized: "Import führt zusammen — kein Check-in geht verloren."))
            }

            shakeToReportSection

            Section {
                pageRow(.about, title: String(localized: "Über & Datenschutz"),
                        symbol: "lock.shield", identifier: "open-about")
            }
            }
        }
        // Farbe und Tint noch einmal: ein Blatt ist eine eigene Präsentation
        // und erbt die Umgebung des Bildschirms darunter nicht (siehe
        // ContentView).
        .sheet(isPresented: $creatingPalette) {
            CustomPaletteSheet(store: store).themed(store)
        }
        .onAppear {
            #if DEBUG
            // Nur Debug: das Farb-Blatt direkt zeigen — Klicks durch die
            // Liste sind in der Sim-Automatisierung unzuverlässig.
            if ProcessInfo.processInfo.arguments.contains("-show-custom-palette") {
                creatingPalette = true
            }
            #endif
        }
        .sheet(item: $editingPalette) { palette in
            CustomPaletteSheet(store: store, existing: palette).themed(store)
        }
        .sheet(item: $paywall, onDismiss: resumeAfterPurchase) { context in
            PaywallView(context: context, store: store,
                        onUnlocked: { purchased = context })
                .themed(store)
        }
        // Ein Deep-Link gewinnt gegen jedes offene Kaufblatt: der Tab
        // wechselt darunter, also darf es nicht darüber liegen bleiben.
        .onChange(of: routeToken) { _, _ in
            purchased = nil
            paywall = nil
        }
        .fullScreenCover(isPresented: $showReminderSetup) {
            ReminderSetupView(isPresented: $showReminderSetup, store: store).themed(store)
        }
        .alert(String(localized: "Farbe umbenennen"),
               isPresented: Binding(get: { renamingPalette != nil },
                                    set: { if !$0 { renamingPalette = nil } })) {
            TextField(String(localized: "Name"), text: $renameText)
                .accessibilityIdentifier("palette-rename-field")
            Button(String(localized: "Abbrechen"), role: .cancel) { renamingPalette = nil }
            Button(String(localized: "Sichern")) { commitRename() }
                .accessibilityIdentifier("palette-rename-save")
        }
        // Rückfrage NUR, wenn die Farbe wirklich benutzt wird — sonst wäre
        // sie eine Gebühr auf jeden Aufräumvorgang. Der Text sagt konkret,
        // was danach passiert, statt „Wirklich löschen?".
        .confirmationDialog(deleteQuestion,
                            isPresented: Binding(get: { deletingPalette != nil },
                                                 set: { if !$0 { deletingPalette = nil } }),
                            titleVisibility: .visible) {
            Button(String(localized: "Löschen"), role: .destructive) {
                if let id = deletingPalette?.id { store.removeCustomPalette(id) }
                deletingPalette = nil
            }
            .accessibilityIdentifier("palette-delete-confirm")
            Button(String(localized: "Abbrechen"), role: .cancel) { deletingPalette = nil }
        } message: {
            Text(String(localized: "Alles, was diese Farbe benutzt, fällt auf die Standardfarbe zurück."))
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        // Das App-Icon folgt der GLOBALEN Farbe — egal ob sie umgestellt oder
        // die aktive eigene Farbe umgefärbt wurde. Eine Stelle statt einer
        // Wiederholung an jedem Schreibvorgang.
        .onChange(of: store.palettes) { _, book in
            guard store.matchAppIcon else { return }
            Task { await AppIcons.apply(book) }
        }
    }

    // Die Statistik-Karten-Auswahl stand hier (bis zu zwei Karten über der
    // Habit-Liste). Die Karten wohnen jetzt vollzählig im eigenen
    // Statistik-Tab — es gibt nichts mehr auszuwählen. `StatsCardPrefs`
    // bleibt als Datenformat bestehen (alte Dateien und iCloud-Stände
    // decodieren unverändert), nur die Oberfläche dazu ist weg.

    private var compactModeSection: some View {
        Section {
            Toggle(String(localized: "Kompakte Ansicht"), isOn: Binding(
                get: { statsCards.compactMode },
                set: { statsCards.compactMode = $0 }))
            .accessibilityIdentifier("compact-mode-toggle")
        } footer: {
            Text(String(localized: "Verdichtet die Habit-Liste und die untere Navigation dauerhaft."))
        }
    }

    private var swipeActionsSection: some View {
        Section {
            Toggle(String(localized: "Wischaktionen"), isOn: Binding(
                get: { statsCards.preferences.swipeActions.enabled },
                set: { enabled in
                    statsCards.update { $0.swipeActions.enabled = enabled }
                }))
            .accessibilityIdentifier("swipe-actions-toggle")

            if statsCards.preferences.swipeActions.enabled {
                Picker(String(localized: "Nach rechts wischen"), selection: swipeLeadingBinding) {
                    ForEach(SwipeActionChoice.selectable) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("swipe-leading-picker")

                Picker(String(localized: "Nach links wischen"), selection: swipeTrailingBinding) {
                    ForEach(SwipeActionChoice.selectable) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("swipe-trailing-picker")
            }
        } header: {
            Text(String(localized: "Wischaktionen"))
        } footer: {
            Text(String(localized: "Erledigt, +1, Ja und Nein liegen fest auf den Wischgesten. Hier wählst du, was als zweiter Knopf dahinter erscheint."))
        }
    }

    /// Die Altlasten `primary`/`secondary` lesen sich als „keine
    /// Extra-Aktion" — genau so löst ContentView sie auch auf.
    private func normalized(_ choice: SwipeActionChoice) -> SwipeActionChoice {
        SwipeActionChoice.selectable.contains(choice) ? choice : .none
    }

    private var swipeLeadingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(statsCards.preferences.swipeActions.leading) },
                set: { choice in statsCards.update { $0.swipeActions.leading = choice } })
    }

    private var swipeTrailingBinding: Binding<SwipeActionChoice> {
        Binding(get: { normalized(statsCards.preferences.swipeActions.trailing) },
                set: { choice in statsCards.update { $0.swipeActions.trailing = choice } })
    }

    // Die Nacharbeiten-Einstellung (Malen/Auswählen) stand hier — der
    // Malen-Modus ist auf Nutzerwunsch entfernt, die Karte arbeitet immer
    // im Auswählen-Modus. Der alte App-Group-Schlüssel „backfillMode" wird
    // schlicht nicht mehr gelesen.

    // MARK: – Schütteln zum Melden

    /// Der zweite Ort für DENSELBEN Schalter — der erste steht im Melde-Blatt
    /// („Beim Schütteln nicht mehr fragen").
    ///
    /// **Warum beide denselben Schlüssel schreiben.** Zwei Ablagen wären zwei
    /// Wahrheiten: hier stünde „ein", während das Blatt sich abgeschaltet
    /// hätte. Geschrieben wird deshalb nur über `ShakeToReport` (siehe dort).
    ///
    /// **Warum die Zeile hier unten steht** und nicht bei den Mitteilungen:
    /// Melden ist keine Erinnerung. Zwischen die beiden Zusammenfassungen
    /// gesetzt, läse sie sich wie eine dritte Sorte Benachrichtigung.
    /// **Warum der Spiegel zusätzlich auf die Mitteilung hört.** „Mehr" liegt
    /// UNTER dem Melde-Blatt und bleibt dabei sichtbar: Schaltet dort jemand
    /// „nicht mehr fragen", fährt das Blatt zu — und `onAppear` feuert nicht,
    /// weil diese Seite nie weg war. Der Schalter zeigte weiter „ein", während
    /// die Ablage längst „aus" sagt. Genau die zwei Wahrheiten, die der eine
    /// Schlüssel verhindern soll.
    private var shakeToReportSection: some View {
        Section {
            Toggle(String(localized: "Schütteln zum Melden"), isOn: Binding(
                get: { shakeToReport },
                set: { on in
                    shakeToReport = on
                    ShakeToReport.isEnabled = on
                }))
            .accessibilityIdentifier("shake-to-report-toggle")
        } footer: {
            Text(String(localized: "Schüttle das iPhone, wenn etwas nicht stimmt: hAiity fragt dann, was passiert ist. Was mitgeht, siehst du vorher — deine Beschreibung und technische Angaben ohne Habit-Namen."))
        }
        .onAppear { shakeToReport = ShakeToReport.isEnabled }
        .onReceive(NotificationCenter.default.publisher(for: ShakeToReport.didChange)) { _ in
            shakeToReport = ShakeToReport.isEnabled
        }
    }

    // MARK: – hAiity Pro
    //
    // Steht direkt unter dem iCloud-Status und spricht dessen Sprache:
    // Symbolkachel, Titel, ein Satz. Und unmittelbar DARUNTER stehen die drei
    // Zeilen, die davon abhängen (Icon per Farbrad, eigene Farbe, Kalender) —
    // wer hier kauft, sieht das Ergebnis, ohne zu scrollen.
    //
    // Der Markenname bleibt unübersetzt (`verbatim`): er steht in keinem
    // Katalog und darf in keiner Sprache anders heissen.

    @ViewBuilder
    private var proSection: some View {
        Section {
            if unlocked {
                // Kein Kaufknopf für etwas, das schon gekauft ist — und keine
                // Zeile, die ins Leere tippt. Nur der Dank.
                proRow(symbol: "checkmark.seal.fill",
                       detail: String(localized: "Freigeschaltet. Danke."),
                       highlighted: true)
                    .accessibilityIdentifier("pro-status")
            } else {
                Button {
                    paywall = .settings
                } label: {
                    HStack(spacing: Theme.Metrics.gap) {
                        proRow(symbol: "lock",
                               detail: String(localized: "Unbegrenzte Habits, eigene Farben, Kalender und volle Statistik."),
                               highlighted: false)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-paywall")
            }
        } footer: {
            Text(String(localized: "Einmal kaufen. Kein Abo, kein Konto, kein Server."))
        }
    }

    /// Dieselbe Form wie die iCloud-Zeile darüber — zwei Statuszeilen
    /// untereinander, die sich unterscheiden, lesen sich wie ein Bruch.
    private func proRow(symbol: String, detail: String, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(highlighted ? AnyShapeStyle(Theme.accentFill(palettes.style))
                                        : AnyShapeStyle(Color.secondary),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "hAiity Pro")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(Theme.accentText(palettes.style))
                                                 : AnyShapeStyle(HierarchicalShapeStyle.primary))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Das eine Schloss-Zeichen gegateter Zeilen. Es sagt VOR dem Tippen, was
    /// passiert — ein Schalter, der wortlos zurückspringt, wirkt kaputt.
    private var proLock: some View {
        Image(systemName: "lock")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
    }

    // MARK: – Kalender
    //
    // EIN Schalter: die Habits mit Termin erscheinen in einem eigenen
    // hAiity-Kalender — und damit in Apple Kalender und (wenn das
    // Standardkonto ein Google-Konto ist) auch in Google Kalender. Der
    // Schalter ist GERÄTELOKAL (jedes Gerät entscheidet selbst); die
    // Berechtigung wird nur beim aktiven Einschalten erfragt.

    private var calendarSection: some View {
        Section {
            Toggle(isOn: calendarBinding) {
                HStack {
                    Label(String(localized: "Habits im Kalender"), systemImage: "calendar.badge.plus")
                    // Das Schloss meint das EINschalten. Läuft der Spiegel
                    // bereits (Erstattung, Bestandsgerät), wäre es eine
                    // Falschaussage neben einem Schalter, der an ist — und
                    // VoiceOver läse „Nur mit hAiity Pro, Schalter, ein".
                    if !unlocked && !CalendarSync.isEnabled {
                        Spacer(minLength: Theme.Metrics.gap)
                        proLock
                    }
                }
            }
            .accessibilityIdentifier("calendar-sync-toggle")
            if calendarDenied {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Der Kalender-Zugriff ist in den iOS-Einstellungen deaktiviert. Dort erlauben, dann klappt der Kalender."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(String(localized: "iOS-Einstellungen öffnen")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("open-calendar-settings")
                }
            }
        } footer: {
            Text(String(localized: "Legt einen eigenen hAiity-Kalender an und trägt dort die Termine deiner Habits ein — sichtbar in Apple Kalender und, je nach Standardkonto, in Google Kalender. Deine übrigen Kalender bleiben unberührt."))
        }
    }

    // MARK: – Anrede
    //
    // Der Name macht Mitteilungen persönlich („Stark, Mo!") — mehr nicht.
    // Zwei Quellen: der Alias (geht IMMER, kein Konto nötig) und optional
    // der Vorname aus der Apple-Anmeldung; der Alias gewinnt. Apple liefert
    // den Namen nur bei der ERSTEN Anmeldung — schlägt das fehl oder kommt
    // leer zurück, sagt die Zeile das ehrlich, statt still nichts zu tun.

    private var personalSection: some View {
        Section {
            TextField(String(localized: "Alias"),
                      text: aliasBinding,
                      prompt: Text(String(localized: "Wie dürfen wir dich nennen?")))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityIdentifier("personal-alias")
            if let appleName = storedAppleName {
                HStack {
                    Label(String(format: String(localized: "Angemeldet als %@"), appleName),
                          systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Entfernen")) {
                        PersonalName.appleName = nil
                        // Die Kennung kam aus DEMSELBEN Anmeldevorgang und
                        // geht mit ihm: „Entfernen" heißt abmelden, und was
                        // dann noch läge, wäre ein Rest einer Anmeldung, die
                        // der Nutzer gerade zurückgenommen hat.
                        PersonalName.appleUserID = nil
                        storedAppleName = nil
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("apple-name-remove")
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    // Nur der Name — keine E-Mail, kein Konto, kein Server.
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 40)
                .accessibilityIdentifier("apple-signin")
                if appleSignInCameBackEmpty {
                    Text(String(localized: "Apple nennt den Vornamen nur bei der allerersten Anmeldung. Kein Problem — trag einfach einen Alias ein."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(String(localized: "Anrede"))
        } footer: {
            Text(String(localized: "Für persönlichere Mitteilungen, etwa den Glückwunsch zum perfekten Tag. Der Name bleibt auf dem Gerät. Anmelden ist optional — ein Alias genügt immer und gewinnt gegen den Apple-Namen."))
        }
        .onAppear {
            aliasDraft = PersonalName.alias ?? ""
            storedAppleName = PersonalName.appleName
        }
    }

    private var aliasBinding: Binding<String> {
        Binding(get: { aliasDraft },
                set: { value in
                    aliasDraft = value
                    PersonalName.alias = value
                })
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            // Abbruch/Fehler: kein Banner, keine Strafe — der Alias bleibt
            // der immer offene Weg.
            return
        }
        let formatter = PersonNameComponentsFormatter()
        let name = credential.fullName?.givenName
            ?? credential.fullName.map { formatter.string(from: $0) }
        // Die undurchsichtige Kennung IMMER mitnehmen — auch wenn Apple
        // keinen Vornamen liefert (das tut es nur bei der allerersten
        // Anmeldung). Sie ist der einzige Weg, dieses Gerät später als das
        // des Besitzers zu erkennen (siehe `DeveloperAccess.isOwnerDevice`),
        // und sie hängt nicht daran, ob ein Name dabei war.
        PersonalName.appleUserID = credential.user
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            PersonalName.appleName = name
            storedAppleName = PersonalName.appleName
            appleSignInCameBackEmpty = false
            Theme.Haptics.success()
        } else {
            appleSignInCameBackEmpty = true
        }
    }

    private var calendarBinding: Binding<Bool> {
        Binding(
            get: { CalendarSync.isEnabled },
            set: { on in
                guard on else {
                    CalendarSync.disable()
                    return
                }
                // AUSschalten bleibt immer frei — auch nach einer Erstattung
                // darf niemand mit einem Schalter zurückbleiben, den er nicht
                // mehr umlegen kann. Nur das EINschalten ist Pro, und es fragt
                // dann gar nicht erst nach dem Kalender-Zugriff: eine
                // Berechtigung für eine Funktion, die danach doch nicht läuft,
                // ist eine Frage unter falschem Vorwand.
                guard ProGate.mayUseProFeature(unlocked: unlocked) else {
                    paywall = .calendar
                    return
                }
                Task {
                    let granted = await CalendarSync.requestAccess()
                    await MainActor.run {
                        calendarDenied = !granted
                        guard granted else { return }
                        CalendarSync.isEnabled = true
                        CalendarSync.reconcile(habits: store.habits)
                    }
                }
            })
    }

    // MARK: – Darstellung
    //
    // Erscheinungsbild und Graph-Farbe stehen bewusst in EINEM Abschnitt und
    // trotzdem als zwei getrennte Einstellungen: beides beantwortet „wie
    // sieht die App aus", aber niemand will Hell/Dunkel mitverstellen, nur
    // weil er das Grün loswerden möchte.

    private var appearanceSection: some View {
        Section {
            Picker(selection: appearanceBinding) {
                ForEach(AppearanceSetting.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            } label: {
                Label(String(localized: "Erscheinungsbild"), systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("appearance-picker")

            Toggle(isOn: matchIconBinding) {
                Label(String(localized: "App-Icon anpassen"), systemImage: "app.badge")
            }
            .accessibilityIdentifier("match-icon-toggle")

            iconGrid

            if iconChangeFailed {
                Text(String(localized: "Der Icon-Wechsel ist auf diesem Gerät gerade nicht möglich."))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(String(localized: "Darstellung"))
        } footer: {
            Text(String(localized: "Beim Anpassen des App-Icons fragt iOS einmal kurz nach. iOS kann nur mitgelieferte Icons setzen — hAiity bringt 18 mit; eine frei gewählte Farbe bekommt das nächstliegende davon. Tippst du oben selbst ein Icon an, bleibt es fest — die automatische Anpassung geht dabei aus."))
        }
    }

    // MARK: – App-Icon-Auswahl
    //
    // Der Schalter darüber ist der AUTOMATIK-Modus (Icon folgt der
    // Graph-Farbe). Das Raster ist der manuelle: ein Tipp setzt das Icon fest
    // und schaltet die Automatik aus. Vorher gab es NUR den Schalter — und
    // wer die grüne Standardfarbe benutzt, sah beim Umlegen exakt nichts
    // (Grün ist das Primär-Icon), was sich als „deaktiviert" las.

    private var iconGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(GraphPalette.allCases) { palette in
                    iconCell(named: AppIcons.name(for: palette),
                             style: palette.style,
                             label: palette.displayName,
                             identifier: "app-icon-\(palette.rawValue)")
                }
                ForEach(AppIcons.hues) { hue in
                    iconCell(named: hue.name,
                             style: hue.style,
                             label: String(localized: "Farbton \(hue.degrees)°"),
                             identifier: "app-icon-h\(hue.degrees)")
                }
            }
            freeIconColorRow
        }
        .padding(.vertical, 4)
        .onAppear { currentIconName = UIApplication.shared.alternateIconName }
    }

    /// Welches Icon gerade auf dem Homescreen liegt — mit Automatik das aus
    /// der Graph-Farbe hergeleitete, sonst das zuletzt gesetzte.
    private var selectedIconName: String? {
        store.matchAppIcon
            ? AppIcons.iconName(for: store.palettes.global, customs: store.palettes.customs)
            : currentIconName
    }

    private func iconCell(named name: String?, style: PaletteStyle,
                          label: String, identifier: String) -> some View {
        let selected = selectedIconName == name
        return Button {
            chooseIcon(named: name)
        } label: {
            VStack(spacing: 4) {
                // Gezeichnet statt aus dem Katalog geladen: die
                // Alternate-Iconsets liegen in Assets.car, aber
                // `UIImage(named:)` findet .appiconset-Bilder nicht
                // zuverlässig (im Simulator gar nicht). Die Miniatur baut
                // das Icon-Motiv nach — dunkle Kachel, Raster in der Rampe.
                iconThumbnail(style: style)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Theme.accentFill(palettes.style)
                                                   : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 2.5 : 1))
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(selected
                                     ? AnyShapeStyle(Theme.accentText(palettes.style))
                                     : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// Freie Farbe: das Farbrad wählt, die Miniatur daneben zeigt EHRLICH
    /// das eingebaute Icon, das daraus wird (iOS kann nur mitgelieferte
    /// Icons setzen), und „Anwenden" setzt genau dieses.
    private var freeIconColorRow: some View {
        HStack(spacing: 12) {
            ColorPicker(selection: $freeIconColor, supportsOpacity: false) {
                Label(String(localized: "Eigene Icon-Farbe"), systemImage: "paintpalette")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("icon-color-picker")
            .frame(maxWidth: .infinity)
            iconThumbnail(style: AppIcons.style(forIconName: snappedFreeIconName))
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            freeIconColorAction
        }
    }

    /// Gegated ist nur das SETZEN. Farbrad und ehrliche Vorschau bleiben —
    /// wer sehen will, welches der 18 Icons aus seiner Farbe würde, soll das
    /// sehen dürfen; die 18 Kacheln darüber sind ohnehin frei.
    @ViewBuilder
    private var freeIconColorAction: some View {
        if unlocked {
            Button(String(localized: "Anwenden")) {
                chooseIcon(named: snappedFreeIconName)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.accentFill(palettes.style))
            .accessibilityIdentifier("icon-color-apply")
        } else {
            Button {
                paywall = .icon
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock")
                    Text(verbatim: "Pro")
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "Nur mit hAiity Pro"))
            .accessibilityIdentifier("icon-color-pro")
        }
    }

    private var snappedFreeIconName: String? {
        AppIcons.iconName(forBase: Theme.hex(from: freeIconColor))
    }

    /// Das Icon-Motiv als Miniatur: dunkle Kachel, darauf ein 2×2-Raster in
    /// den Stufen der Familie — dieselbe Rampe wie im Jahresraster.
    private func iconThumbnail(style: PaletteStyle) -> some View {
        ZStack {
            Color(red: 0.09, green: 0.11, blue: 0.10)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.level([2, 4, 3, 1][row * 2 + col],
                                                  dark: true, palette: style))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    /// Manuelle Wahl: Automatik aus, Icon setzen, Ergebnis zurückmelden.
    private func chooseIcon(named name: String?) {
        store.matchAppIcon = false
        Task {
            let ok = await AppIcons.set(name)
            await MainActor.run {
                iconChangeFailed = !ok
                // Nicht zurücklesen: `alternateIconName` hinkt der Animation
                // des System-Dialogs hinterher, und die Markierung stünde
                // einen Moment auf dem falschen Icon.
                currentIconName = ok ? name
                                     : UIApplication.shared.alternateIconName
            }
        }
    }

    // MARK: – Graph-Farbe
    //
    // Die Auswahl IST das Raster: jede Zeile zeigt ihre fünf Stufen als
    // dieselben Quadrate, die später im Jahresraster stehen (`GridCell`),
    // nicht als Farbpunkte. Eine eigene Farbe steht gleichberechtigt zwischen
    // den eingebauten — sie kann nur zusätzlich umbenannt, umgefärbt und
    // gelöscht werden.

    private var paletteSection: some View {
        Section {
            ForEach(GraphPalette.allCases) { palette in
                PaletteRow(style: palette.style,
                           title: palette.displayName,
                           selected: store.palette == .builtin(palette)) {
                    select(.builtin(palette))
                }
                .accessibilityIdentifier("palette-row-\(palette.rawValue)")
            }
            ForEach(store.customPalettes) { custom in
                PaletteRow(style: custom.style,
                           title: custom.displayName,
                           selected: store.palette == .custom(custom.id)) {
                    select(.custom(custom.id))
                }
                .accessibilityIdentifier("palette-row-custom-\(custom.id.uuidString)")
                .swipeActions(edge: .trailing) {
                    // Rot EXPLIZIT: der App-Tint (die eigene Farbe!) würde die
                    // zerstörende Rolle sonst übermalen — eine Löschen-Taste in
                    // Petrol sieht aus wie eine harmlose Aktion.
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                    .tint(.red)
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        renameText = custom.name
                        renamingPalette = custom
                    } label: {
                        Label(String(localized: "Umbenennen"), systemImage: "pencil")
                    }
                    Button { editingPalette = custom } label: {
                        Label(String(localized: "Bearbeiten"), systemImage: "paintpalette")
                    }
                    Button(role: .destructive) { requestDelete(custom) } label: {
                        Label(String(localized: "Löschen"), systemImage: "trash")
                    }
                }
            }
            Button {
                requestCustomPalette()
            } label: {
                HStack {
                    Label(String(localized: "Eigene Farbe …"), systemImage: "plus.circle")
                    if !unlocked {
                        Spacer(minLength: Theme.Metrics.gap)
                        proLock
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("palette-add-custom")
        } header: {
            Text(String(localized: "Graph-Farbe"))
        } footer: {
            Text(String(localized: "Gilt für alle Habits; einzelne Habits können beim Bearbeiten eine eigene Farbe bekommen. Bei eigenen Farben wählst du eine Grundfarbe — die fünf Stufen rechnet hAiity daraus. Streichen oder lange drücken: umbenennen, bearbeiten, löschen."))
        }
    }

    /// Frage im Löschen-Dialog. Sie NENNT, was betroffen ist — eine Farbe,
    /// die gerade nichts einfärbt, wird ohne Rückfrage gelöscht.
    private var deleteQuestion: String {
        guard let palette = deletingPalette else { return "" }
        return String(localized: "„\(palette.displayName)“ wird noch benutzt. Löschen?")
    }

    /// Eigene Farben ANLEGEN ist Pro — der Bestand nicht: vorhandene eigene
    /// Farben bleiben wählbar, umbenennbar, bearbeitbar und löschbar. Bezahlt
    /// wird das Neue, nie das Vorhandene.
    private func requestCustomPalette() {
        guard ProGate.mayUseProFeature(unlocked: unlocked) else {
            paywall = .palette
            return
        }
        creatingPalette = true
    }

    /// Was nach einem erfolgreichen Kauf weiterläuft. Erst beim ZUFAHREN des
    /// Blatts: eine zweite Präsentation, die im Abgang der ersten startet,
    /// schluckt iOS.
    ///
    /// `.settings` steht bewusst nicht hier — diese Zeile hat nichts
    /// unterbrochen, die Seite zeigt den Kauf jetzt einfach als
    /// freigeschaltet. `.habits` und `.stats` gehören anderen Bildschirmen.
    private func resumeAfterPurchase() {
        guard let intent = purchased else { return }
        purchased = nil
        switch intent {
        case .calendar:
            // Über die Bindung, nicht daran vorbei: sie ist der EINE Weg,
            // der das Gate prüft und danach den Kalender-Zugriff erfragt.
            calendarBinding.wrappedValue = true
        case .palette:
            creatingPalette = true
        case .icon:
            chooseIcon(named: snappedFreeIconName)
        case .habits, .stats, .settings:
            break
        }
    }

    private func requestDelete(_ palette: CustomPalette) {
        if store.isCustomPaletteInUse(palette.id) {
            deletingPalette = palette
        } else {
            store.removeCustomPalette(palette.id)
        }
    }

    private func commitRename() {
        guard var palette = renamingPalette else { return }
        palette.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateCustomPalette(palette)
        renamingPalette = nil
    }

    /// Global gibt es kein „Wie App": eine Farbe ist immer gesetzt.
    private func select(_ ref: PaletteRef) {
        guard ref != store.palette else { return }
        store.palette = ref
    }

    // MARK: – Seitenartige Ziele
    //
    // Statistik, Archiv und Über sind SEITEN und werden als Blatt geöffnet.
    // Sie sehen aus wie ein `NavigationLink` (Chevron rechts), weil sie sich
    // genauso anfühlen sollen — nur dass sie nicht in einen Stapel schieben,
    // den die Tafel gar nicht hat.
    //
    // Hier stand einmal der Abschnitt „Wischgesten" mit zwei Pickern. Die
    // Gesten selbst sind weg (lange drücken statt wischen, siehe HabitCard),
    // und damit auch die Einstellung: eine sichtbare Aktionsliste muss
    // niemand einstellen.

    private func pageRow(_ route: MoreRoute,
                         title: String,
                         symbol: String,
                         identifier: String,
                         badge: String? = nil) -> some View {
        Button {
            onOpen(route)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
    }

    private var appearanceBinding: Binding<AppearanceSetting> {
        Binding(get: { store.appearance }, set: { store.appearance = $0 })
    }

    private var matchIconBinding: Binding<Bool> {
        Binding(
            get: { store.matchAppIcon },
            set: { on in
                store.matchAppIcon = on
                // Einschalten holt das Icon sofort nach, Ausschalten stellt
                // das Standard-Icon wieder her — sonst bliebe ein oranges
                // Icon kleben, obwohl die Kopplung aus ist.
                let book = on ? store.palettes : PaletteBook()
                Task {
                    await AppIcons.apply(book)
                    await MainActor.run {
                        currentIconName = UIApplication.shared.alternateIconName
                    }
                }
            })
    }

    // MARK: – iCloud-Zeile
    //
    // KEIN Knopf, kein Blatt, kein Einrichten: es gibt nichts zu verbinden.
    // Die Zeile ist reiner Status und sagt in jedem Zustand die Wahrheit —
    // „aktiv“, „nur auf diesem Gerät“ (nicht angemeldet), „warten“ (offline)
    // oder der echte Fehlertext. Nur der aktive Zustand trägt die
    // Markenfarbe; alles andere bleibt sekundär, damit ein Problem nicht wie
    // ein Erfolg aussieht.

    private var iCloudRow: some View {
        let state = cloudStatus.state
        let ok: Bool = { if case .active = state { return true }; return false }()
        return HStack(spacing: 12) {
            Image(systemName: state.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(ok ? AnyShapeStyle(Theme.accentFill(palettes.style))
                               : AnyShapeStyle(Color.secondary),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ok ? AnyShapeStyle(Theme.accentText(palettes.style))
                                        : AnyShapeStyle(HierarchicalShapeStyle.primary))
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("icloud-status")
    }

    // MARK: – Mitteilungen
    //
    // Tages- und Wochenzusammenfassung tragen den Stand, die Motivation
    // einen ruhigen Satz aus dem lokalen Vorrat. Alle drei bleiben getrennt:
    // wer Zahlen will, will nicht automatisch einen Gedanken dazu — und
    // jede Meldung darf zu ihrer eigenen Uhrzeit kommen.
    //
    // Das Berechtigungs-Gate bleibt exakt wie gehabt: gefragt wird NUR beim
    // aktiven Einschalten, nie beim Start.

    private var dailySummarySection: some View {
        Section {
            Toggle(isOn: dailyEnabled) {
                Label(String(localized: "Tageszusammenfassung"), systemImage: "sun.max")
            }
            .accessibilityIdentifier("summary-toggle")
            if store.summaryMinutes != nil {
                DatePicker(String(localized: "Uhrzeit"),
                           selection: dailyTime,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("summary-time")
            }
            if summaryDenied { permissionHint }
        } footer: {
            Text(String(localized: "Einmal am Tag: wie viel von heute erledigt ist und was noch offen steht. Gezählt wird nur, was heute laut Regel ansteht."))
        }
    }

    private var weeklySummarySection: some View {
        Section {
            Toggle(isOn: weeklyEnabled) {
                Label(String(localized: "Wochenzusammenfassung"), systemImage: "calendar")
            }
            .accessibilityIdentifier("weekly-summary-toggle")
            if store.weeklySummaryMinutes != nil {
                Picker(String(localized: "Wochentag"), selection: weeklyWeekday) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        Text(RecurrenceText.weekdayName(day)).tag(day)
                    }
                }
                .accessibilityIdentifier("weekly-summary-weekday")
                DatePicker(String(localized: "Uhrzeit"),
                           selection: weeklyTime,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("weekly-summary-time")
            }
            if weeklyDenied { permissionHint }
        } footer: {
            Text(String(localized: "Einmal in der Woche: wie viele der fälligen Termine du gehalten hast — und welche Habits zurückliegen."))
        }
    }

    private var motivationSection: some View {
        Section {
            Toggle(isOn: motivationEnabled) {
                Label(String(localized: "Tägliche Motivation"), systemImage: "quote.bubble")
            }
            .accessibilityIdentifier("motivation-toggle")
            if store.motivationMinutes != nil {
                DatePicker(String(localized: "Uhrzeit"),
                           selection: motivationTime,
                           displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("motivation-time")
            }
            if motivationDenied { permissionHint }
        } footer: {
            Text(String(localized: "Jeden Tag ein anderer kurzer Gedanke aus deinem Raster — ruhig, ohne Druck."))
        }
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert."))
                .font(.caption)
                .foregroundStyle(.orange)
            // Der direkte Sprung statt einer Wegbeschreibung: iOS öffnet die
            // Mitteilungs-Einstellungen DIESER App.
            Button(String(localized: "iOS-Einstellungen öffnen")) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("open-notification-settings")
        }
    }

    /// Wochentage in der Reihenfolge des Nutzerkalenders (Mo … So in
    /// Deutschland, So … Sa in den USA).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    /// Standardzeiten: der Tag klingt abends aus, die Woche sonntags am
    /// frühen Abend — beides nach dem letzten sinnvollen Moment, an dem man
    /// noch etwas nachholen kann.
    private static let defaultDailyMinutes = 20 * 60
    private static let defaultWeeklyMinutes = 18 * 60
    private static let defaultMotivationMinutes = 8 * 60

    private var dailyEnabled: Binding<Bool> {
        Binding(
            get: { store.summaryMinutes != nil },
            set: { on in
                guard on else { store.summaryMinutes = nil; return }
                askThen { granted in
                    if granted {
                        store.summaryMinutes = store.summaryMinutes ?? Self.defaultDailyMinutes
                        summaryDenied = false
                    } else {
                        summaryDenied = true
                    }
                }
            })
    }

    private var weeklyEnabled: Binding<Bool> {
        Binding(
            get: { store.weeklySummaryMinutes != nil },
            set: { on in
                guard on else { store.weeklySummaryMinutes = nil; return }
                askThen { granted in
                    if granted {
                        store.weeklySummaryMinutes = store.weeklySummaryMinutes
                            ?? Self.defaultWeeklyMinutes
                        weeklyDenied = false
                    } else {
                        weeklyDenied = true
                    }
                }
            })
    }

    private var motivationEnabled: Binding<Bool> {
        Binding(
            get: { store.motivationMinutes != nil },
            set: { on in
                guard on else { store.motivationMinutes = nil; return }
                askThen { granted in
                    if granted {
                        store.motivationMinutes = store.motivationMinutes
                            ?? Self.defaultMotivationMinutes
                        motivationDenied = false
                    } else {
                        motivationDenied = true
                    }
                }
            })
    }

    /// Das Gate an EINER Stelle: fragen, dann auf dem Hauptthread entscheiden.
    private func askThen(_ body: @escaping @MainActor (Bool) -> Void) {
        Task {
            let granted = await Reminders.ensurePermission()
            await MainActor.run { body(granted) }
        }
    }

    private var dailyTime: Binding<Date> {
        timeBinding(get: { store.summaryMinutes ?? Self.defaultDailyMinutes },
                    set: { store.summaryMinutes = $0 })
    }

    private var weeklyTime: Binding<Date> {
        timeBinding(get: { store.weeklySummaryMinutes ?? Self.defaultWeeklyMinutes },
                    set: { store.weeklySummaryMinutes = $0 })
    }

    private var motivationTime: Binding<Date> {
        timeBinding(get: { store.motivationMinutes ?? Self.defaultMotivationMinutes },
                    set: { store.motivationMinutes = $0 })
    }

    private var weeklyWeekday: Binding<Int> {
        Binding(get: { store.weeklySummaryWeekday },
                set: { store.weeklySummaryWeekday = $0 })
    }

    /// Minuten seit Mitternacht <-> Datum. Zweimal dieselbe Rechnung wäre
    /// zweimal dieselbe Gelegenheit, sie unterschiedlich zu runden.
    private func timeBinding(get minutes: @escaping () -> Int,
                             set store: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let m = minutes()
                return Calendar.current.date(from: DateComponents(hour: m / 60,
                                                                  minute: m % 60)) ?? .now
            },
            set: { date in
                store(Calendar.current.component(.hour, from: date) * 60
                      + Calendar.current.component(.minute, from: date))
            })
    }

    // MARK: – Import

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let raw = try Data(contentsOf: url)
                try store.importJSON(raw)
                importMessage = String(localized: "Import zusammengeführt.")
            } catch {
                importMessage = String(localized: "Import fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
}

/// Export als teilbare JSON-Datei — die Daten entstehen erst beim Teilen.
struct HabitExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("haiity-export.json")
    }
}

/// Kurz und ehrlich: das Kein-Server-Prinzip — und ganz unten die
/// Versionszeile, hinter der die versteckte Tür zum Entwicklerbereich sitzt.
struct AboutView: View {
    /// Bereits getätigte Tipps auf die Versionszeile. Bewusst NICHT
    /// gespeichert: eine halb geöffnete Tür soll den Bildschirm nicht
    /// überleben (siehe `DeveloperAccess`).
    @State private var taps = 0
    /// Gespiegelt statt bei jedem Rumpf gelesen — beim Zurückkehren von der
    /// Entwicklerseite (dort kann man sie wieder ausblenden) frischt
    /// `onAppear` den Stand auf.
    ///
    /// **„Erreichbar" ist mehr als „freigeschaltet".** Gefragt wird beides auf
    /// einmal (`DeveloperAccess.isAvailable`): Die Freischaltung liegt
    /// dauerhaft in den Defaults, das Gerät kann aber trotzdem nicht mehr das
    /// des Besitzers sein — dann verschwindet die Zeile wieder.
    @State private var developerAvailable = false

    var body: some View {
        List {
            Section(String(localized: "Über hAiity")) {
                Text(String(localized: "hAiity füllt Quadrate: jeder Tag, an dem du dranbleibst, färbt eine Zelle — wie ein Contribution-Graph für dein Leben."))
                    .font(.subheadline)
            }
            Section(String(localized: "Datenschutz")) {
                Text(String(localized: "hAiity hat keinen Server. Deine Daten liegen auf diesem Gerät — und, wenn du bei iCloud angemeldet bist, zusätzlich in deiner eigenen privaten iCloud. Wir sehen sie nie. Keine Analyse, kein Tracking, keine Konten."))
                    .font(.subheadline)
            }
            Section {
                versionRow
                if developerAvailable { developerRow }
            }
        }
        .navigationTitle(String(localized: "Über"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            developerAvailable = DeveloperAccess.isAvailable(
                storedAppleUserID: PersonalName.appleUserID)
        }
    }

    /// Die Tür. Sie sieht aus wie eine Fußzeile und ist eine: die Version
    /// gehört ohnehin in jede Meldung. Erst ab dem vierten Tipp verrät der
    /// Countdown, dass da etwas ist — vorher wäre sie keine versteckte Tür.
    private var versionRow: some View {
        Button {
            tapVersion()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AppBuildInfo.versionLine)
                if let hint = DeveloperAccess.hint(for: taps) {
                    Text(hint)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("app-version")
    }

    private var developerRow: some View {
        NavigationLink(value: MoreRoute.developer) {
            Label(String(localized: "Entwickler"), systemImage: "hammer")
        }
        .accessibilityIdentifier("open-developer")
    }

    /// Ein Tipp weiter. Gerechnet wird in `DeveloperAccess`; hier steht nur,
    /// was die ANSICHT damit tut — den einen Schreibvorgang und den Stups,
    /// der das Aufgehen der Tür spürbar macht.
    ///
    /// **Auf fremden Geräten passiert NICHTS.** Kein Countdown, keine
    /// Zählung, kein Stups — die Zeile bleibt eine Versionszeile. Eine Tür,
    /// die sich einen Spalt bewegt, verrät, dass sie eine ist; und der
    /// Countdown „Noch 3 Tipps …" wäre die Anleitung gleich dazu. Wem die Tür
    /// gehört, entscheidet `DeveloperAccess.isOwnerDevice` — solange dort
    /// keine Kennung eingebaut ist, gilt das für jedes Gerät (Bootstrap,
    /// siehe `DeveloperAccess.ownerAppleUserID`).
    private func tapVersion() {
        guard DeveloperAccess.isOwnerDevice(storedAppleUserID: PersonalName.appleUserID) else {
            return
        }
        let step = DeveloperAccess.next(taps: taps)
        taps = step.taps
        guard step.unlocked else { return }
        DeveloperAccess.isUnlocked = true
        // Ohne Nachfrage: Der Riegel oben hat gerade bestätigt, dass dieses
        // Gerät dem Besitzer gehört — ein zweiter Aufruf derselben Regel im
        // selben Atemzug wäre nur eine Wiederholung.
        developerAvailable = true
        Theme.Haptics.success()
    }
}
