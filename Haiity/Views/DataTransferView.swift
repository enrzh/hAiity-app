import SwiftUI
import UniformTypeIdentifiers

struct DataTransferView: View {
    let store: HabitStore

    var body: some View {
        SettingsPage(title: String(localized: "Import & Export")) {
            DataTransferSection(store: store)
        }
    }
}

/// The public settings page and diagnostics share the same transfer boundary.
struct DataTransferSection: View {
    let store: HabitStore
    var onImported: () -> Void = {}
    @State private var showImporter = false
    @State private var importMessage: String?

    private enum ImportError: LocalizedError {
        case trackedHabitLimit

        var errorDescription: String? {
            String(localized: "Dieser Import würde das kostenlose Limit von drei aktiven Habits überschreiten. Mit hAiity Pro kannst du ihn vollständig zusammenführen.")
        }
    }

    var body: some View {
        AppSettingsGroup(title: String(localized: "Import & Export"),
                         symbol: "arrow.up.arrow.down",
                         footer: String(localized: "Ein Import führt deine Einträge zusammen. Bestehende Daten werden nicht durch die Datei ersetzt.")) {
            VStack(alignment: .leading, spacing: Theme.Metrics.gap + 4) {
                if let data = store.exportJSON() {
                    ShareLink(item: HabitExport(data: data),
                              preview: SharePreview(String(localized: "hAiity-Export"))) {
                        Label(String(localized: "Exportieren"), systemImage: "square.and.arrow.up")
                            .frame(minHeight: Theme.Metrics.hit)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("export-data")
                }
                Button {
                    showImporter = true
                } label: {
                    Label(String(localized: "Importieren"), systemImage: "square.and.arrow.down")
                        .frame(minHeight: Theme.Metrics.hit)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("import-data")

                if let importMessage {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("data-transfer-message")
                }
            }
            .padding(.vertical, Theme.Metrics.gap / 2)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
    }

    static func importJSON(_ raw: Data, into store: HabitStore, unlocked: Bool) throws {
        let incoming = try JSONDecoder().decode(HabitData.self, from: raw)
        guard ProGate.mayImport(incoming: incoming, into: store.data, unlocked: unlocked) else {
            throw ImportError.trackedHabitLimit
        }
        try store.importJSON(raw)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try Self.importJSON(Data(contentsOf: url), into: store, unlocked: Pro.isUnlocked)
                importMessage = String(localized: "Import zusammengeführt.")
                onImported()
            } catch {
                importMessage = String(localized: "Import fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
}
