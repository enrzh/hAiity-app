import SwiftUI
import UniformTypeIdentifiers

/// Unterseiten des Mehr-Bereichs — wertbasiert, damit Deep-Links
/// (haiity://stats, haiity://archive) direkt hinspringen können.
enum MoreRoute: Hashable {
    case stats, archive, about
}

/// "Mehr": GitHub-Sync, Abend-Zusammenfassung, Statistik, Archiv,
/// Export/Import und Über/Datenschutz. Läuft im selben NavigationStack wie
/// die Habit-Liste — die Bottom-Bar bleibt sichtbar.
struct MoreView: View {
    let store: HabitStore
    let sync: GitHubSync
    @Binding var connectedLogin: String?

    @State private var showSync = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var summaryDenied = false
    @Environment(\.graphPalette) private var palette

    private var archivedCount: Int { store.habits.filter { $0.archivedAt != nil }.count }

    var body: some View {
        List {
            Section {
                Button {
                    showSync = true
                } label: {
                    if let login = connectedLogin { connectedSyncRow(login) } else { connectSyncRow }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("open-sync")
            } footer: {
                Text(connectedLogin == nil
                     ? String(localized: "Optional: deine Daten in einem privaten Repo deines GitHub-Accounts. Ein Tipp, ein Code, fertig.")
                     : String(localized: "Optional: deine Daten in einem privaten Repo deines GitHub-Accounts."))
            }

            appearanceSection
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
        .sheet(isPresented: $showSync) {
            SyncSheet(store: store, sync: sync, connectedLogin: $connectedLogin)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .task {
            #if DEBUG
            // Nur Debug: `-screen sync` öffnet das Sync-Blatt direkt — für
            // Screenshot-Verifikation ohne UI-Automatisierung.
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count,
                  args[i + 1] == "sync" else { return }
            try? await Task.sleep(for: .milliseconds(900))
            showSync = true
            #endif
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

            VStack(alignment: .leading, spacing: 6) {
                Label(String(localized: "Graph-Farbe"), systemImage: "square.grid.3x3.fill")
                PalettePicker(selection: paletteBinding)
            }
            .padding(.vertical, 2)

            Toggle(isOn: matchIconBinding) {
                Label(String(localized: "App-Icon anpassen"), systemImage: "app.badge")
            }
            .accessibilityIdentifier("match-icon-toggle")
        } header: {
            Text(String(localized: "Darstellung"))
        } footer: {
            Text(String(localized: "Die Graph-Farbe gilt für alle Habits. Einzelne Habits können beim Bearbeiten eine eigene Farbe bekommen. Beim Anpassen des App-Icons fragt iOS einmal kurz nach."))
        }
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

    /// Global gibt es kein „Wie App" — deshalb wird nil hier nie gesetzt und
    /// ein nil-Set (das der Picker in dieser Rolle gar nicht auslöst)
    /// ignoriert, statt die Palette zurückzusetzen.
    private var paletteBinding: Binding<GraphPalette?> {
        Binding(
            get: { store.palette },
            set: { new in
                guard let new, new != store.palette else { return }
                store.palette = new
                if store.matchAppIcon { Task { await AppIcons.apply(new) } }
            })
    }

    private var matchIconBinding: Binding<Bool> {
        Binding(
            get: { store.matchAppIcon },
            set: { on in
                store.matchAppIcon = on
                // Einschalten holt das Icon sofort nach, Ausschalten stellt
                // das Standard-Icon wieder her — sonst bliebe ein oranges
                // Icon kleben, obwohl die Kopplung aus ist.
                Task { await AppIcons.apply(on ? store.palette : .default) }
            })
    }

    // MARK: – GitHub-Zeile
    //
    // Getrennt nach Zustand: nicht verbunden ist eine EINLADUNG (Akzent,
    // Chevron, Untertitel) — kein Statuszeilen-Grau, das man übersieht.
    // Verbunden ist reiner Status.

    private var connectSyncRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accentFill(palette),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Mit GitHub verbinden"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accentText(palette))
                Text(String(localized: "Code bestätigen — kein Token nötig"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func connectedSyncRow(_ login: String) -> some View {
        HStack {
            Label(String(localized: "GitHub-Sync"), systemImage: "checkmark.icloud")
            Spacer()
            Text(login)
                .font(.callout)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
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
                Text(String(localized: "hAiity hat keinen Server. Deine Daten liegen ausschließlich auf diesem Gerät — und, nur wenn du es einrichtest, in einem privaten Repo deines eigenen GitHub-Accounts. Keine Analyse, kein Tracking, keine Konten."))
                    .font(.subheadline)
            }
        }
        .navigationTitle(String(localized: "Über"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
