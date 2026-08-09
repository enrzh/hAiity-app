import SwiftUI
import UniformTypeIdentifiers

/// Unterseiten des Mehr-Bereichs — wertbasiert, damit Deep-Links
/// (haiity://stats, haiity://archive) direkt hinspringen können.
enum MoreRoute: Hashable {
    case stats, archive, about
}

/// "Mehr": iCloud-Status, Abend-Zusammenfassung, Statistik, Archiv,
/// Export/Import und Über/Datenschutz. Läuft im selben NavigationStack wie
/// die Habit-Liste — die Bottom-Bar bleibt sichtbar.
struct MoreView: View {
    let store: HabitStore
    /// Nur Anzeige: es gibt nichts einzurichten. Entweder iCloud läuft, oder
    /// die Zeile sagt, warum nicht.
    let cloudStatus: CloudSyncStatus

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var summaryDenied = false
    // Eigene Farben: anlegen, bearbeiten, umbenennen, löschen.
    @State private var creatingPalette = false
    @State private var editingPalette: CustomPalette?
    @State private var renamingPalette: CustomPalette?
    @State private var renameText = ""
    @State private var deletingPalette: CustomPalette?
    @Environment(\.palettes) private var palettes

    private var archivedCount: Int { store.habits.filter { $0.archivedAt != nil }.count }

    var body: some View {
        List {
            Section {
                iCloudRow
            } footer: {
                Text(String(localized: "Deine Habits liegen auf diesem Gerät. Ist es bei iCloud angemeldet, spiegelt hAiity sie zusätzlich in deine private iCloud — nichts einzurichten, kein Konto bei uns, kein Server bei uns."))
            }

            appearanceSection
            paletteSection
            swipeSection

            Section {
                Toggle(isOn: summaryEnabled) {
                    Label(String(localized: "Abend-Zusammenfassung"), systemImage: "moon")
                }
                .accessibilityIdentifier("summary-toggle")
                if store.summaryMinutes != nil {
                    DatePicker(String(localized: "Uhrzeit"),
                               selection: summaryTime,
                               displayedComponents: .hourAndMinute)
                }
                if summaryDenied {
                    Text(String(localized: "Benachrichtigungen sind in den iOS-Einstellungen deaktiviert. Dort einschalten, dann klappt die Zusammenfassung."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(String(localized: "Erinnert abends einmal an alle noch offenen Habits."))
            }

            Section {
                NavigationLink(value: MoreRoute.stats) {
                    Label(String(localized: "Statistik"), systemImage: "chart.bar")
                }
                .accessibilityIdentifier("open-stats")
                NavigationLink(value: MoreRoute.archive) {
                    HStack {
                        Label(String(localized: "Archiv"), systemImage: "archivebox")
                        Spacer()
                        if archivedCount > 0 {
                            Text("\(archivedCount)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("open-archive")
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
                NavigationLink(value: MoreRoute.about) {
                    Label(String(localized: "Über & Datenschutz"), systemImage: "lock.shield")
                }
                .accessibilityIdentifier("open-about")
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
        } header: {
            Text(String(localized: "Darstellung"))
        } footer: {
            Text(String(localized: "Beim Anpassen des App-Icons fragt iOS einmal kurz nach. Für eigene Farben nimmt das Icon die nächstliegende der sechs eingebauten."))
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

    // MARK: – Wischgesten
    //
    // Die Richtungen sind BENANNT, nicht „links"/„rechts": ein Wisch heißt
    // hier nach der BEWEGUNG des Fingers, weil genau das die Rückmeldung war
    // („von links nach rechts = erledigt"). In RTL dreht das System die
    // Kanten selbst — die Beschriftung folgt dem System, nicht der Kante.

    private var swipeSection: some View {
        Section {
            swipePicker(String(localized: "Von links nach rechts"),
                        symbol: "arrow.right",
                        selection: swipeBinding(\.leadingSwipe),
                        identifier: "swipe-leading-picker")
            swipePicker(String(localized: "Von rechts nach links"),
                        symbol: "arrow.left",
                        selection: swipeBinding(\.trailingSwipe),
                        identifier: "swipe-trailing-picker")
        } header: {
            Text(String(localized: "Wischgesten"))
        } footer: {
            Text(String(localized: "Ist ein Habit heute schon erledigt, bietet die Geste von rechts nach links zusätzlich „Rückgängig“ an. Voll durchziehen löst nur „Erledigt“ und „Rückgängig“ aus — Archivieren nie."))
        }
    }

    private func swipePicker(_ title: String,
                             symbol: String,
                             selection: Binding<SwipeAction>,
                             identifier: String) -> some View {
        Picker(selection: selection) {
            ForEach(SwipeAction.allCases) { action in
                Text(action.title).tag(action)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(identifier)
    }

    private func swipeBinding(_ keyPath: ReferenceWritableKeyPath<HabitStore, SwipeAction>) -> Binding<SwipeAction> {
        Binding(get: { store[keyPath: keyPath] },
                set: { store[keyPath: keyPath] = $0 })
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
                Task { await AppIcons.apply(book) }
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

    // MARK: – Abend-Zusammenfassung

    private var summaryEnabled: Binding<Bool> {
        Binding(
            get: { store.summaryMinutes != nil },
            set: { on in
                if on {
                    Task {
                        let granted = await Reminders.ensurePermission()
                        await MainActor.run {
                            if granted {
                                store.summaryMinutes = store.summaryMinutes ?? 20 * 60
                                summaryDenied = false
                            } else {
                                summaryDenied = true
                            }
                        }
                    }
                } else {
                    store.summaryMinutes = nil
                }
            })
    }

    private var summaryTime: Binding<Date> {
        Binding(
            get: {
                let m = store.summaryMinutes ?? 20 * 60
                return Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? .now
            },
            set: { date in
                store.summaryMinutes = Calendar.current.component(.hour, from: date) * 60
                    + Calendar.current.component(.minute, from: date)
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
