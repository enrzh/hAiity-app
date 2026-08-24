import StoreKit
import SwiftUI

/// Woher das Kaufblatt gerufen wurde.
///
/// Der Kontext ändert NUR die Kopfzeile, nie das Angebot: wer wegen der
/// vierten Habit hier landet, soll den Satz lesen, der zu seinem Tipp gehört —
/// eine allgemeine Werbeseite lässt ihn raten, warum sie überhaupt aufging.
///
/// `Identifiable`, weil das Blatt als `.sheet(item:)` präsentiert wird: so
/// hält der Aufrufer EINEN optionalen Zustand statt Flagge plus Kontext, die
/// auseinanderlaufen können.
enum PaywallContext: String, Identifiable, CaseIterable {
    case habits
    case palette
    case icon
    case calendar
    case stats
    case settings

    var id: String { rawValue }

    /// Ein Satz, der die Frage des Nutzers aufnimmt statt sie zu ignorieren.
    var headline: String {
        switch self {
        case .habits:
            return String(localized: "Mehr als drei Habits? Das ist Pro.")
        case .palette:
            return String(localized: "Eigene Farben? Das ist Pro.")
        case .icon:
            // Nicht „freie Farbe": iOS kann nur mitgelieferte Icons setzen,
            // und die 18 sind ohne Pro antippbar. Bezahlt wird das Farbrad
            // als Eingabe, nicht ein Icon, das es sonst nicht gäbe.
            return String(localized: "Das App-Icon per Farbrad setzen? Das ist Pro.")
        case .calendar:
            return String(localized: "Habits im Kalender? Das ist Pro.")
        case .stats:
            return String(localized: "Die ganze Statistik? Das ist Pro.")
        case .settings:
            return String(localized: "Alles freischalten — mit einem einzigen Kauf.")
        }
    }
}

/// Das Kaufblatt für hAiity Pro.
///
/// **Formensprache wie der Einrichtungs-Bildschirm**: oben das Markenmotiv im
/// gestaffelten Auftritt, darunter Karten mit Symbolkachel — eine Kaufseite,
/// die aussieht wie ein fremder Werbebanner, wirkt wie ein fremder
/// Werbebanner.
///
/// **Der Preis kommt aus dem Store, nie aus dem Quelltext.** Ein hart
/// geschriebener Betrag ist in jeder anderen Währung und nach jeder
/// Preisanpassung eine Lüge; solange `Product` fehlt, sagt der Knopf das
/// ehrlich und bleibt aus.
///
/// **Keine dunklen Muster.** Schließen geht ab dem ersten Frame (X oben
/// links), es gibt keinen Countdown, keinen durchgestrichenen Fantasiepreis
/// und keine zweite, kleinere Absage. Fehlschläge sind kurz und ohne Drama —
/// ein abgebrochener Kauf ist kein Fehler, sondern eine Entscheidung.
struct PaywallView: View {
    let context: PaywallContext
    let store: HabitStore
    /// Wird EINMAL gerufen, wenn der Kauf wirklich vorliegt (gekauft oder
    /// wiederhergestellt) — und zwar bevor das Blatt zufährt. Der Aufrufer
    /// nimmt damit die Handlung wieder auf, wegen der es aufging: bezahlen
    /// und dann vor derselben Wand stehen ist der Moment, in dem ein Kauf
    /// sich wie ein Fehler anfühlt.
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var loadingPrice = true
    @State private var busy: Busy?
    @State private var note: Note?
    @State private var proStatus = ProStatus.shared

    /// Beim Öffnen aus den Einstellungen kann der Kauf schon vorliegen —
    /// dann wäre ein Kaufknopf schlicht falsch. Kein gespiegelter Zustand:
    /// `Pro.isUnlocked` ist beobachtbar, und genau hier zählt das — ein Kauf
    /// auf einem anderen Gerät kann bestätigt werden, WÄHREND dieses Blatt
    /// offen steht.
    private var unlocked: Bool { proStatus.unlocked || Pro.isUnlocked }

    private enum Busy {
        case buying
        case restoring
    }

    /// Die vier Sätze, die nach einem Tipp stehen bleiben dürfen. Bewusst als
    /// Zustand und nicht als Alarm: ein Systemdialog für einen Abbruch, den
    /// der Nutzer selbst ausgelöst hat, ist eine Zurechtweisung.
    private enum Note {
        case cancelled
        case failed
        case nothingToRestore
        case storeUnreachable
    }

    private var accent: Color { Theme.accentText(store.paletteStyle) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.gutter) {
                    MotifGrid(pattern: MotifGrid.brand,
                              palette: store.paletteStyle, cellSize: 16)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    header
                    featureList
                }
                .padding(Theme.Metrics.gutter)
            }
            .background(AppearanceBackground(preferences: store.appearancePreferences))
            .safeAreaInset(edge: .bottom) { footer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Schließen"))
                    .accessibilityIdentifier("paywall-close")
                }
            }
        }
        .task { await load() }
    }

    // MARK: – Kopf

    /// Der Markenname bleibt unübersetzt (`verbatim`) — er steht in keinem
    /// Katalog und darf in keiner Sprache anders heißen.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "hAiity Pro")
                .font(.largeTitle.bold())
            Text(context.headline)
                .font(.headline)
                .foregroundStyle(accent)
            Text(String(localized: "Einmal kaufen. Kein Abo, kein Konto, kein Server."))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: – Was dazukommt

    private struct Feature: Identifiable {
        /// Das Symbol ist innerhalb der Liste eindeutig und spart eine
        /// zweite, bedeutungslose Kennung.
        var id: String { symbol }
        let symbol: String
        let title: String
        let text: String
    }

    /// Schrittweise gebaut, nicht als ein großes Literal: der Typprüfer des
    /// Release-Xcode bricht bei Sammlungen aus mehrzeiligen Konstruktoren ab.
    private func features() -> [Feature] {
        var list: [Feature] = []
        list.append(Feature(
            symbol: "infinity",
            title: String(localized: "Unbegrenzte Habits"),
            text: String(localized: "Leg so viele an, wie dein Tag hergibt — ohne Pro sind es drei aktive.")))
        list.append(Feature(
            symbol: "paintpalette.fill",
            title: String(localized: "Eigene Farben"),
            text: String(localized: "Misch dir eigene Paletten aus einer Grundfarbe, für die App und für einzelne Habits.")))
        // Ehrlich gehalten: die 18 Icons sind FREI antippbar, Pro ist der
        // Weg über das Farbrad. Eine Zeile, die „freie Icon-Farbe" verspricht,
        // verkauft etwas, das iOS gar nicht kann (nur mitgelieferte Icons)
        // und das der Frei-Zustand über die Kacheln längst hat.
        list.append(Feature(
            symbol: "app.badge.checkmark",
            title: String(localized: "Icon per Farbrad"),
            text: String(localized: "Stell die Farbe am Rad ein — hAiity setzt das nächstliegende seiner 18 mitgelieferten Icons. Ohne Pro wählst du direkt aus den 18 Kacheln.")))
        list.append(Feature(
            symbol: "calendar.badge.plus",
            title: String(localized: "Kalender-Spiegel"),
            text: String(localized: "Trägt die Termine deiner Habits in einen eigenen hAiity-Kalender ein.")))
        list.append(Feature(
            symbol: "chart.bar.xaxis",
            title: String(localized: "Volle Statistik"),
            text: String(localized: "Jede Auswertung im Detail statt nur der Kacheln der Übersicht.")))
        return list
    }

    private var featureList: some View {
        VStack(spacing: Theme.Metrics.gap) {
            ForEach(features()) { feature in
                featureCard(feature)
            }
        }
    }

    private func featureCard(_ feature: Feature) -> some View {
        card {
            HStack(alignment: .top, spacing: Theme.Metrics.gap) {
                iconTile(feature.symbol)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(.subheadline.weight(.semibold))
                    Text(feature.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(Theme.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface()
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(accent)
            .frame(width: 36, height: 36)
            .background(Theme.accent(store.paletteStyle).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: – Fuß

    private var footer: some View {
        VStack(spacing: 10) {
            if let note {
                noteLine(note)
            }
            if unlocked {
                unlockedRow
            } else {
                purchaseButton
                restoreButton
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// Der Knopf trägt den Betrag, den der Store nennt — und solange keiner
    /// da ist, sagt er das, statt eine Zahl zu erfinden.
    private var purchaseButton: some View {
        Button {
            buy()
        } label: {
            purchaseLabel
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentFill(store.paletteStyle))
        .disabled(busy != nil || product == nil)
        .accessibilityIdentifier("paywall-purchase")
    }

    @ViewBuilder
    private var purchaseLabel: some View {
        if busy == .buying {
            ProgressView()
        } else if let product {
            Text(String(localized: "Für \(product.displayPrice) kaufen"))
        } else if loadingPrice {
            Text(String(localized: "Preis wird geladen"))
        } else {
            Text(String(localized: "Preis nicht verfügbar"))
        }
    }

    private var restoreButton: some View {
        Button {
            restore()
        } label: {
            Group {
                if busy == .restoring {
                    ProgressView()
                } else {
                    Text(String(localized: "Käufe wiederherstellen"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22)
        }
        .disabled(busy != nil)
        .accessibilityIdentifier("paywall-restore")
    }

    /// Schon gekauft (aus den Einstellungen geöffnet, oder gerade
    /// wiederhergestellt): kein Kaufknopf, keine zweite Gelegenheit,
    /// dasselbe noch einmal zu bezahlen.
    private var unlockedRow: some View {
        VStack(spacing: 10) {
            Label(String(localized: "Freigeschaltet. Danke."),
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            Button {
                // Auch dieser Weg nimmt die unterbrochene Handlung wieder
                // auf: wer hier steht, ist freigeschaltet — entweder schon
                // vorher oder gerade eben (bestätigte Kaufanfrage).
                onUnlocked()
                dismiss()
            } label: {
                Text(String(localized: "Fertig"))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentFill(store.paletteStyle))
            .accessibilityIdentifier("paywall-done")
        }
    }

    private func noteLine(_ note: Note) -> some View {
        Label(text(for: note), systemImage: symbol(for: note))
            .font(.footnote)
            .foregroundStyle(isWarning(note) ? AnyShapeStyle(Color.orange)
                                             : AnyShapeStyle(Color.secondary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("paywall-note")
    }

    private func text(for note: Note) -> String {
        switch note {
        case .cancelled:
            return String(localized: "Kein Kauf abgeschlossen, nichts berechnet.")
        case .failed:
            return String(localized: "Der Kauf ist nicht durchgegangen. Es wurde nichts berechnet — du kannst es gleich noch einmal versuchen.")
        case .nothingToRestore:
            return String(localized: "Auf diesem Konto liegt kein früherer Kauf von hAiity Pro.")
        case .storeUnreachable:
            return String(localized: "Der App Store hat gerade nicht geantwortet. Prüf deine Verbindung und versuch es noch einmal.")
        }
    }

    private func symbol(for note: Note) -> String {
        switch note {
        case .cancelled, .nothingToRestore:
            return "info.circle"
        case .failed, .storeUnreachable:
            return "exclamationmark.triangle.fill"
        }
    }

    private func isWarning(_ note: Note) -> Bool {
        switch note {
        case .failed, .storeUnreachable:
            return true
        case .cancelled, .nothingToRestore:
            return false
        }
    }

    // MARK: – Handlungen

    private func load() async {
        let loaded = await Pro.product()
        await MainActor.run {
            product = loaded
            loadingPrice = false
            // Nur melden, wenn der fehlende Preis überhaupt stört.
            if loaded == nil, !unlocked {
                note = .storeUnreachable
            }
        }
    }

    private func buy() {
        guard busy == nil else { return }
        busy = .buying
        note = nil
        Task {
            do {
                let bought = try await Pro.purchase()
                await MainActor.run {
                    busy = nil
                    guard bought else {
                        note = .cancelled
                        return
                    }
                    Theme.Haptics.success()
                    onUnlocked()
                    dismiss()
                }
            } catch {
                // Die Unterscheidung fällt im Hauptakteur, damit der Zugriff
                // auf den Fehlertyp aus `Pro` nirgends daneben landet.
                await MainActor.run {
                    busy = nil
                    if let purchase = error as? Pro.PurchaseError,
                       case .productUnavailable = purchase {
                        note = .storeUnreachable
                    } else {
                        note = .failed
                    }
                }
            }
        }
    }

    /// „Auf diesem Konto liegt kein Kauf" ist eine Tatsachenbehauptung über
    /// die Kaufhistorie — die darf nur stehen, wenn der Store wirklich
    /// geantwortet hat. Ein verschluckter Netzfehler liest sich sonst wie
    /// „du hast nie gekauft" und schickt jemanden in den Zweitkauf oder in
    /// die Support-Mail.
    private func restore() {
        guard busy == nil else { return }
        busy = .restoring
        note = nil
        Task {
            do {
                try await Pro.restore()
            } catch {
                await MainActor.run { restoreFailed(error) }
                return
            }
            await MainActor.run {
                busy = nil
                guard unlocked else {
                    note = .nothingToRestore
                    return
                }
                Theme.Haptics.success()
                onUnlocked()
                dismiss()
            }
        }
    }

    @MainActor
    private func restoreFailed(_ error: Error) {
        busy = nil
        // Der Abbruch am Passwort-Dialog ist eine Entscheidung, kein Fehler:
        // dafür braucht es keinen Satz. Alles andere heißt „nicht geprüft".
        if let storeKit = error as? StoreKitError, case .userCancelled = storeKit {
            note = nil
        } else {
            note = .storeUnreachable
        }
    }
}
