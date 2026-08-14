import MessageUI
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
    @State private var showsMail = false
    /// Rückfrage vor „nicht mehr fragen" — nur, wenn dabei etwas verloren
    /// ginge (siehe `muteSection`).
    @State private var asksBeforeMuting = false

    /// Das Sichtfenster auf den Diagnosetext wächst mit der Schriftgröße mit.
    /// Fest in Punkten zeigte es bei den Barrierefreiheits-Graden noch zwei
    /// Zeilen — ausgerechnet denen, die grosse Schrift brauchen, bliebe von
    /// „sieh selbst, was mitgeht" ein Schlüsselloch.
    @ScaledMetric(relativeTo: .footnote) private var diagnosticsHeight: CGFloat = 220

    /// Genau der Text, der verschickt wird — eine Quelle für Anzeige und Mail.
    private var diagnostics: String { facts.map(DiagnosticsReport.text) ?? "" }

    private var isCollected: Bool { facts != nil }

    private var subject: String {
        FeedbackMail.subject(version: AppBuildInfo.version, build: AppBuildInfo.build)
    }

    /// Nicht `body` — der Name gehört in einer Ansicht dem Bildschirm.
    private var mailBody: String {
        FeedbackMail.body(description: text, diagnostics: diagnostics)
    }

    var body: some View {
        NavigationStack {
            List {
                descriptionSection
                diagnosticsSection
                sendSection
                muteSection
            }
            .navigationTitle(String(localized: "Fehler melden"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Abbrechen")) { dismiss() }
                        .accessibilityIdentifier("feedback-close")
                }
            }
        }
        .task { facts = await DiagnosticsCollector.local(store: store, cloudStatus: cloudStatus) }
        // Das Mail-Fenster ist eine eigene Präsentation ÜBER diesem Blatt —
        // ein Blatt aus einem Blatt heraus ist erlaubt, ein zweites NEBEN
        // demselben Blatt nicht.
        .sheet(isPresented: $showsMail) {
            MailComposer(subject: subject, body: mailBody) { sent in
                showsMail = false
                // Nur nach dem Abschicken zufahren: wer im Mail-Fenster
                // abbricht, will meist zurück in seinen Text.
                guard sent else { return }
                Theme.Haptics.success()
                dismiss()
            }
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
            } label: {
                Label(String(localized: "Diese technischen Angaben werden mitgeschickt"),
                      systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("feedback-diagnostics")
        }
    }

    // MARK: – (3) Senden

    private var sendSection: some View {
        Section {
            Button {
                send()
            } label: {
                Label(String(localized: "Senden"), systemImage: "paperplane")
            }
            .foregroundStyle(.primary)
            // Vor dem Sammeln gäbe es nur die Beschreibung — eine Meldung
            // ohne Version und Gerät ist eine Frage ohne Zeitpunkt.
            .disabled(!isCollected)
            .accessibilityIdentifier("feedback-send")
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

    // MARK: – Der Weg nach draußen

    /// Erst das Mail-Fenster, sonst das Teilen-Blatt — aber NIE nichts.
    ///
    /// **Warum es überhaupt einen zweiten Weg gibt.** `canSendMail()` ist auf
    /// jedem Gerät ohne eingerichtetes Mail-Konto `false`, und das ist keine
    /// Ausnahme: viele Menschen lesen ihre Mail nur in einer anderen App.
    /// Täte der Knopf dann nichts, sähe das Blatt kaputt aus — ausgerechnet
    /// das Blatt, mit dem man Kaputtes meldet. Das Teilen-Blatt nimmt
    /// denselben Text und lässt ihn in jede App, die Text annimmt.
    private func send() {
        guard MFMailComposeViewController.canSendMail() else {
            share()
            return
        }
        showsMail = true
    }

    /// Der Rückfallweg über das System-Teilen-Blatt.
    ///
    /// Die Adresse steht als erste Zeile im Text: Wer den Bericht in eine
    /// Mail-App schiebt, hat sonst zwar den Inhalt, aber keinen Empfänger.
    private func share() {
        let text = "\(FeedbackMail.recipient)\n\(subject)\n\n\(mailBody)"
        // Über den OBERSTEN Controller — das ist dieses Blatt selbst. Von der
        // Wurzel aus präsentiert, käme das Teilen-Blatt hinter dem Melde-Blatt
        // zu liegen und wäre nicht zu sehen (siehe `ModalPresentation`).
        guard let top = ModalPresentation.topViewController else { return }
        top.present(UIActivityViewController(activityItems: [text],
                                             applicationActivities: nil),
                    animated: true)
    }
}

// MARK: – Das Mail-Fenster

/// `MFMailComposeViewController` in SwiftUI.
///
/// **Warum Apples Fenster und keine eigene `mailto:`-URL.** Der Rumpf trägt
/// den ganzen Diagnosetext; als URL sind das schnell zwei Kilobyte, und
/// einzelne Mail-Programme kürzen lange `mailto:`-Rümpfe stillschweigend —
/// beim Empfänger käme ein halber Bericht an. Das Fenster nimmt Empfänger,
/// Betreff und Text als Werte entgegen, zeigt sie dem Absender und schickt
/// über sein eigenes Konto: nichts verlässt das Gerät, ohne dass er es
/// gesehen und selbst auf Senden getippt hat.
private struct MailComposer: UIViewControllerRepresentable {
    let subject: String
    let body: String
    /// `true` = wirklich abgeschickt. Abbrechen, Sichern und ein Fehler beim
    /// Verschicken sind ausdrücklich KEIN Erfolg — sonst schlösse sich das
    /// Blatt samt getipptem Text über einer Meldung, die nie ankam.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    /// Bewusst leer: Betreff und Rumpf stehen beim Öffnen fest. Sie später
    /// nachzuschieben überschriebe, was der Absender im Fenster getippt hat.
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish(result == .sent)
        }
    }
}
