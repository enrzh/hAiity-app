import SafariServices
import SwiftUI
import UIKit

/// Das Melde-Blatt: ein Schütteln, eine Beschreibung, ab damit.
///
/// **Warum das Blatt den Anhang ZEIGT.** Es verschickt technische Angaben
/// über das Gerät. Niemand soll etwas losschicken, das er nicht vorher lesen
/// konnte — deshalb steht der Diagnosetext hier im Klartext, aufklappbar und
/// wortgleich mit dem, was gleich im Postfach landet. Ein „wir schicken ein
/// paar technische Daten mit" wäre eine Bitte um Vertrauen; der ausklappbare
/// Text ist der Beleg.
///
/// **Warum der Diagnosetext nicht übersetzt wird.** Er wird nicht gelesen, wo
/// er entsteht, sondern wo er ankommt (siehe `DiagnosticsReport`). Übersetzt
/// ist die SEITE, nicht ihr Auszug.
///
/// **Datenschutz.** Gesammelt wird ausschließlich, was `DiagnosticsFacts`
/// tragen kann — Zahlen, Zustände, technische Kennungen. Kein Habit-Name,
/// kein Zeichen, kein Alias, kein Log-Wert. Die Beschreibung tippt der Mensch
/// selbst: sie ist seine Entscheidung, nicht unsere Sammlung.
///
/// **Warum das Blatt den Preis NICHT abwartet.** `DiagnosticsCollector.price()`
/// fragt den App Store. Hier zählt, dass Angezeigtes und Verschicktes
/// dasselbe sind — käme der Preis Sekunden später nach, änderte sich der Text
/// unter den Augen des Lesenden. Und ohne Netz (die häufigste Lage bei einer
/// Fehlermeldung) wartete das Blatt bis in den Zeitablauf der URL-Sitzung.
struct FeedbackSheet: View {
    let store: HabitStore
    let cloudStatus: CloudSyncStatus

    @Environment(\.dismiss) private var dismiss

    /// Was der Mensch erlebt hat — das Einzige, was hier von ihm kommt.
    @State private var text = ""
    /// Der gesammelte Stand — `nil`, solange nichts gesammelt ist. Ein leerer
    /// `DiagnosticsFacts` sähe nicht leer aus, sondern behauptete glatte
    /// Nullen (siehe `DeveloperView`).
    @State private var facts: DiagnosticsFacts?
    /// Zugeklappt beginnen: die Beschreibung ist das Wichtige, die Technik
    /// der Beleg dahinter.
    @State private var showsDiagnostics = false
    @State private var showsGitHubIssues = false
    @State private var reportCopied = false
    /// Rückfrage vor „nicht mehr fragen" — nur, wenn dabei etwas verloren
    /// ginge (siehe `muteSection`).
    @State private var asksBeforeMuting = false

    /// Das Sichtfenster auf den Diagnosetext wächst mit der Schriftgröße mit.
    /// Fest in Punkten zeigte es bei den Barrierefreiheits-Graden noch zwei
    /// Zeilen — ausgerechnet denen, die grosse Schrift brauchen, bliebe von
    /// „sieh selbst, was mitgeht" ein Schlüsselloch.
    @ScaledMetric(relativeTo: .footnote) private var diagnosticsHeight: CGFloat = 220

    /// Genau der Text, den der Nutzer bei Bedarf in das GitHub-Issue kopiert.
    private var diagnostics: String { facts.map(DiagnosticsReport.text) ?? "" }

    private var isCollected: Bool { facts != nil }

    /// Nicht `body` — der Name gehört in einer Ansicht dem Bildschirm.
    private var reportText: String {
        FeedbackMail.body(description: text, diagnostics: diagnostics)
    }

    var body: some View {
        NavigationStack {
            List {
                descriptionSection.settingsListRow()
                diagnosticsSection.settingsListRow()
                sendSection.settingsListRow()
                muteSection.settingsListRow()
            }
            .settingsSurface()
            .appPageHeader(String(localized: "Fehler melden"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                        .accessibilityIdentifier("feedback-close")
                }
            }
        }
        .task { facts = await DiagnosticsCollector.local(store: store, cloudStatus: cloudStatus) }
        .sheet(isPresented: $showsGitHubIssues) {
            FeedbackBrowser(url: FeedbackIssue.issueURL)
                .ignoresSafeArea()
        }
    }

    // MARK: – (1) Was ist passiert

    /// **Einmal fragen reicht.** „Was ist passiert?" stand hier dreifach — als
    /// Überschrift, als Feldbeschriftung und als Platzhalter. Sichtbar las man
    /// denselben Satz zweimal untereinander, VoiceOver sprach ihn zweimal
    /// hintereinander. Geblieben ist die Beschriftung des Feldes: Sie ist in
    /// einer Liste ohnehin der Platzhalter und zugleich das, was VoiceOver
    /// beim Hineinspringen vorliest.
    private var descriptionSection: some View {
        Section {
            // Mehrzeilig und mitwachsend: ein Fehler ist selten ein Satz,
            // und ein einzeiliges Feld schneidet ihn optisch ab.
            TextField(String(localized: "Was ist passiert?"),
                      text: $text,
                      axis: .vertical)
                .lineLimit(4...10)
                .accessibilityIdentifier("feedback-description")
        }
    }

    // MARK: – (2) Der Anhang, offen einsehbar

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsDiagnostics) {
                // Fest im eigenen Rahmen scrollbar: der Bericht ist länger
                // als ein Bildschirm, und ausgeklappt schöbe er sonst Senden
                // und Beschreibung aus dem Blick.
                ScrollView {
                    Text(verbatim: isCollected ? diagnostics
                                               : String(localized: "Wird gesammelt …"))
                        .font(.footnote.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: diagnosticsHeight)
                .softScrollEdges()
            } label: {
                Label(String(localized: "Diese technischen Angaben werden mitgeschickt"),
                      systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("feedback-diagnostics")
        }
    }

    // MARK: – (3) GitHub

    private var sendSection: some View {
        Section {
            Button { showsGitHubIssues = true } label: {
                Label(String(localized: "Auf GitHub melden"),
                      systemImage: "exclamationmark.bubble")
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("feedback-send")

            Button { copyReport() } label: {
                Label(String(localized: reportCopied ? "Bericht kopiert." : "Bericht kopieren"),
                      systemImage: reportCopied ? "checkmark" : "doc.on.doc")
                    .symbolEffect(.bounce, value: reportCopied)
            }
            .disabled(!isCollected)
            .accessibilityIdentifier(reportCopied ? "feedback-copy-confirmation" : "feedback-copy")
        }
    }

    // MARK: – (4) Nicht mehr fragen

    /// Der zweite von zwei Orten für DENSELBEN Schalter (der andere steht in
    /// „Mehr"). Hier als Knopf statt als Umschalter: „Beim Schütteln nicht
    /// mehr fragen" ist in diesem Moment eine Entscheidung, keine Anzeige —
    /// ein Umschalter, dessen EIN-Stellung „nicht fragen" bedeutet, liest
    /// sich verkehrt herum.
    ///
    /// **Warum die Rückfrage nur manchmal kommt.** Der Knopf steht direkt
    /// unter „Senden" — genau dort, wohin der Daumen nach dem Tippen wandert.
    /// Ein Fehlgriff hätte sonst zwei Folgen auf einmal, und beide sind
    /// unumkehrbar: die getippte Beschreibung ist weg, und die Geste ist
    /// abgeschaltet. Steht noch nichts im Feld, gibt es nichts zu verlieren —
    /// dann wäre die Rückfrage nur eine Gebühr auf eine klare Absicht.
    private var muteSection: some View {
        Section {
            Button(String(localized: "Beim Schütteln nicht mehr fragen")) {
                guard hasDescription else {
                    mute()
                    return
                }
                asksBeforeMuting = true
            }
            .accessibilityIdentifier("feedback-disable-shake")
        }
        .confirmationDialog(String(localized: "Beschreibung verwerfen und nicht mehr fragen?"),
                            isPresented: $asksBeforeMuting,
                            titleVisibility: .visible) {
            Button(String(localized: "Verwerfen und nicht mehr fragen"), role: .destructive) {
                mute()
            }
            .accessibilityIdentifier("feedback-disable-shake-confirm")
            Button(String(localized: "Abbrechen"), role: .cancel) {}
        }
    }

    private var hasDescription: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Der EINE Schreibvorgang dieses Blatts auf den geteilten Schalter.
    private func mute() {
        ShakeToReport.isEnabled = false
        dismiss()
    }

    private func copyReport() {
        UIPasteboard.general.string = reportText
        reportCopied = true
        Theme.Haptics.success()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            reportCopied = false
        }
    }
}

private struct FeedbackBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
