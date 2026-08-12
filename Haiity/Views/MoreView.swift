import SwiftUI
import UniformTypeIdentifiers

/// Bildschirmartige Unterziele des Mehr-Bereichs — wertbasiert, damit
/// Deep-Links (haiity://stats, haiity://archive) direkt hinspringen können.
/// `Identifiable`, weil sie als `.sheet(item:)` präsentiert werden: in der
/// Tafel über der Leiste ist für eine eigene Seite kein Platz.
enum MoreRoute: Hashable, Identifiable {
    case stats, archive, about

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
            && a.statsCards === b.statsCards
    }

    let store: HabitStore
    /// Nur Anzeige: es gibt nichts einzurichten. Entweder iCloud läuft, oder
    /// die Zeile sagt, warum nicht.
    let cloudStatus: CloudSyncStatus
    /// Auswahl der Statistik-Karten über der Liste (höchstens zwei).
    let statsCards: StatsCardStore
    /// Ein seitenartiges Ziel öffnen (Statistik, Archiv, Über).
    let onOpen: (MoreRoute) -> Void

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var summaryDenied = false
    @State private var weeklyDenied = false
    @State private var testMessage: String?
    // App-Icon-Auswahl: was der Homescreen gerade zeigt, und ob der letzte
    // Wechsel scheiterte (supportsAlternateIcons == false o. ä.).
    @State private var currentIconName: String?
    @State private var iconChangeFailed = false
    // Eigene Farben: anlegen, bearbeiten, umbenennen, löschen.
    @State private var creatingPalette = false
    @State private var editingPalette: CustomPalette?
    @State private var renamingPalette: CustomPalette?
    @State private var renameText = ""
    @State private var deletingPalette: CustomPalette?
    @Environment(\.palettes) private var palettes

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

            appearanceSection
            paletteSection

            statsCardsSection
            compactModeSection

            dailySummarySection
            weeklySummarySection
            testNotificationSection

            Section {
                pageRow(.stats, title: String(localized: "Statistik"),
                        symbol: "chart.bar", identifier: "open-stats")
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
        .sheet(item: $editingPalette) { palette in
            CustomPaletteSheet(store: store, existing: palette).themed(store)
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

    // MARK: – Statistik-Karten
    //
    // Vier Karten, höchstens zwei aktiv. Die Mechanik ist „sperren +
    // Fußnote", nicht „älteste fliegt raus": ein Schalter, der beim
    // Einschalten still einen anderen ausschaltet, wäre der einzige in der
    // ganzen Tafel, der etwas Ungefragtes tut. Gesperrte Schalter bleiben
    // sichtbar (ausgegraut), die Fußnote sagt warum.

    private var statsCardsSection: some View {
        Section {
            ForEach(StatsCard.allCases) { card in
                Toggle(isOn: cardBinding(card)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(card.displayName, systemImage: card.symbol)
                        Text(card.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!statsCards.prefs.canToggle(card))
                .accessibilityIdentifier("stats-card-toggle-\(card.rawValue)")
            }
        } header: {
            Text(String(localized: "Statistik-Karten"))
        } footer: {
            Text(String(localized: "Bis zu zwei Karten stehen über der Habit-Liste. Sind zwei aktiv, schalte zuerst eine ab, um eine andere zu wählen."))
        }
    }

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

    private func cardBinding(_ card: StatsCard) -> Binding<Bool> {
        Binding(get: { statsCards.prefs.isActive(card) },
                set: { statsCards.setStatsCard(card, active: $0) })
    }

    // Die Nacharbeiten-Einstellung (Malen/Auswählen) stand hier — der
    // Malen-Modus ist auf Nutzerwunsch entfernt, die Karte arbeitet immer
    // im Auswählen-Modus. Der alte App-Group-Schlüssel „backfillMode" wird
    // schlicht nicht mehr gelesen.

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
            Text(String(localized: "Beim Anpassen des App-Icons fragt iOS einmal kurz nach. Für eigene Farben nimmt das Icon die nächstliegende der sechs eingebauten. Tippst du unten selbst ein Icon an, bleibt es fest — die automatische Anpassung geht dabei aus."))
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
            ForEach(GraphPalette.allCases) { palette in
                iconCell(palette)
            }
        }
        .padding(.vertical, 4)
        .onAppear { currentIconName = UIApplication.shared.alternateIconName }
    }

    /// Welche Familie gerade auf dem Homescreen liegt — mit Automatik die
    /// aus der Graph-Farbe hergeleitete, sonst das zuletzt gesetzte Icon.
    private var selectedIconPalette: GraphPalette {
        store.matchAppIcon
            ? AppIcons.iconPalette(for: store.palettes.global, customs: store.palettes.customs)
            : AppIcons.palette(forIconName: currentIconName)
    }

    private func iconCell(_ palette: GraphPalette) -> some View {
        let selected = selectedIconPalette == palette
        return Button {
            chooseIcon(palette)
        } label: {
            VStack(spacing: 4) {
                // Gezeichnet statt aus dem Katalog geladen: die
                // Alternate-Iconsets liegen in Assets.car, aber
                // `UIImage(named:)` findet .appiconset-Bilder nicht
                // zuverlässig (im Simulator gar nicht). Die Miniatur baut
                // das Icon-Motiv nach — dunkle Kachel, Raster in der Rampe.
                iconThumbnail(palette)
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
        .accessibilityLabel(palette.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("app-icon-\(palette.rawValue)")
    }

    /// Das Icon-Motiv als Miniatur: dunkle Kachel, darauf ein 2×2-Raster in
    /// den Stufen der Familie — dieselbe Rampe wie im Jahresraster.
    private func iconThumbnail(_ palette: GraphPalette) -> some View {
        ZStack {
            Color(red: 0.09, green: 0.11, blue: 0.10)
            VStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<2, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.level([2, 4, 3, 1][row * 2 + col],
                                                  dark: true, palette: palette.style))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    /// Manuelle Wahl: Automatik aus, Icon setzen, Ergebnis zurückmelden.
    private func chooseIcon(_ palette: GraphPalette) {
        store.matchAppIcon = false
        Task {
            let ok = await AppIcons.set(palette)
            await MainActor.run {
                iconChangeFailed = !ok
                // Nicht zurücklesen: `alternateIconName` hinkt der Animation
                // des System-Dialogs hinterher, und die Markierung stünde
                // einen Moment auf dem falschen Icon.
                currentIconName = ok ? AppIcons.name(for: palette)
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
                creatingPalette = true
            } label: {
                Label(String(localized: "Eigene Farbe …"), systemImage: "plus.circle")
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

    // MARK: – Die beiden Zusammenfassungen
    //
    // Sie sind der EINZIGE Ort in der App, an dem Benachrichtigungen
    // vorkommen — seit v5 auch der einzige, der die Berechtigung auslösen
    // darf. Vorher hatte jeder Habit seine eigene Erinnerung; zehn Habits
    // waren zehn Weckrufe, und keiner wusste, ob der Tag schon erledigt war.
    // Jetzt fasst EINE Meldung am Tag zusammen, was offen ist, und eine am
    // Ende der Woche, was gehalten wurde (siehe `SummaryText`).
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

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert. Dort einschalten, dann klappt die Zusammenfassung."))
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

    /// Der sichtbare Beweis, dass die Kette bis zum Banner reicht — eine
    /// echte, über den normalen Weg geplante Mitteilung in zehn Sekunden.
    private var testNotificationSection: some View {
        Section {
            Button {
                testMessage = nil
                Task {
                    let ok = await Reminders.scheduleTest()
                    await MainActor.run {
                        testMessage = ok
                            ? String(localized: "Kommt in 10 Sekunden — auch bei geöffneter App.")
                            : String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert.")
                        summaryDenied = !ok
                    }
                }
            } label: {
                Label(String(localized: "Test-Mitteilung"), systemImage: "bell.badge")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("test-notification")
            if let testMessage {
                Text(testMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(String(localized: "Prüft, ob Mitteilungen von hAiity ankommen."))
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

/// Kurz und ehrlich: das Kein-Server-Prinzip.
struct AboutView: View {
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
        }
        .navigationTitle(String(localized: "Über"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
