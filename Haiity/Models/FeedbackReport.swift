import Foundation

/// Der Schalter hinter „Schütteln zum Melden".
///
/// **Warum ein eigener, geteilter Schlüssel.** Der Zustand wird an ZWEI Orten
/// umgelegt — im Melde-Blatt („Beim Schütteln nicht mehr fragen") und in
/// „Mehr" — und beide meinen dieselbe Sache. Zwei Ablagen wären zwei
/// Wahrheiten: der Schalter in den Einstellungen stünde auf „ein", während das
/// Blatt sich abgeschaltet hat.
///
/// **Warum die App-Group und nicht `UserDefaults.standard`.** Anders als die
/// Freischaltung der Entwicklerseite ist das hier eine Entscheidung des
/// Menschen über die App, keine Aussage über diesen einen Prozess — sie liegt
/// im selben Topf wie Anrede und Kalender-Zustand.
enum ShakeToReport {
    static let enabledKey = "shakeToReport"

    /// Der Schalter wurde umgelegt — an welchem der beiden Orte, ist egal.
    ///
    /// **Warum eine Ablage allein nicht reicht.** Beide Orte teilen sich zwar
    /// den Schlüssel, aber nicht den BLICK darauf: `UserDefaults` ist stumm,
    /// und die Zeile in „Mehr" spiegelt den Wert (sonst spränge der Schalter
    /// beim Umlegen optisch zurück). Schaltet das Melde-Blatt ab, während
    /// „Mehr" darunter liegen bleibt, zeigte der Spiegel weiter „ein" — zwei
    /// Wahrheiten aus einer Ablage. Diese Mitteilung ist der Auffrischbefehl
    /// dazu; `onAppear` allein feuert beim Zufahren eines Blattes nicht.
    static let didChange = Notification.Name("haiityShakeToReportChanged")

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedStorage.appGroup) ?? .standard
    }

    /// Standard EIN — ab Werk darf ein Fehler gemeldet werden können.
    ///
    /// **Die Falle steht in der Frage.** `bool(forKey:)` macht aus „noch nie
    /// gesetzt" ein `false`, und ein nie berührter Schalter stünde damit auf
    /// „aus": die Meldefunktion wäre für jeden neuen Nutzer unsichtbar
    /// abgeschaltet. Deshalb wird zuerst gefragt, ob überhaupt etwas abgelegt
    /// ist, und nur dann der abgelegte Wert genommen.
    static var isEnabled: Bool {
        get {
            guard let stored = defaults.object(forKey: enabledKey) as? Bool else { return true }
            return stored
        }
        set {
            defaults.set(newValue, forKey: enabledKey)
            // Erst ablegen, dann rufen: Wer die Mitteilung hört, liest den
            // Wert — und soll den neuen finden, nicht den alten.
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// Betreff, Rumpf und Notfall-Adresse einer Fehlermeldung — als reine Werte,
/// ohne Mail-Fenster, ohne Ansicht.
///
/// **Warum getrennt vom Blatt.** Was verschickt wird, ist die eine Sache, die
/// ein Test ohne Gerät, ohne Mail-Konto und ohne Simulator festnageln kann:
/// derselbe Stand ergibt denselben Text. Das Fenster darüber (Mail-Fenster
/// oder Teilen-Blatt) ist austauschbar.
///
/// **Warum Betreff und Rumpf NICHT übersetzt werden.** Sie werden nicht
/// gelesen, wo sie entstehen, sondern wo sie ankommen — im Postfach der
/// Entwicklung. Ein auf Urdu betitelter Fehlerbericht beantwortet dort keine
/// Frage mehr. Übersetzt wird das BLATT, das der Mensch sieht, nicht der
/// Auszug, den er verschickt (dieselbe Regel wie beim Diagnosetext).
///
/// **Datenschutz.** Beide Teile des Rumpfs sind gedeckt: der Diagnosetext
/// kommt aus `DiagnosticsReport.text(_:)` und kann bauartbedingt keinen Namen
/// tragen, und die Beschreibung tippt der Mensch selbst — sie ist seine
/// Entscheidung, nicht unsere Sammlung.
enum FeedbackMail {
    /// Plus-Adressierung: dieselbe Mailbox, aber Meldungen aus hAiity lassen
    /// sich beim Empfänger ohne eigenes Konto aussortieren.
    static let recipient = "getaiityapp+hAiity@gmail.com"

    /// „hAiity 1.0.0 (44) — Fehlermeldung" — Marke, Version, Build.
    ///
    /// Die Zahlen stehen im Betreff, weil eine Meldung ohne Build eine Frage
    /// ohne Zeitpunkt ist; sie stehen zusätzlich im Diagnosetext, aber die
    /// Betreffzeile ist das Einzige, was eine Liste von Meldungen zeigt.
    static func subject(version: String, build: String) -> String {
        "hAiity \(version) (\(build)) — Fehlermeldung"
    }

    /// Beschreibung, Leerzeile, Diagnose — in dieser Reihenfolge.
    ///
    /// Der Mensch zuerst: was er erlebt hat, steht oben und nicht unter
    /// zwanzig Zeilen Technik. Ist die Beschreibung leer, entfällt sie samt
    /// Leerzeile — eine Mail, die mit zwei leeren Zeilen beginnt, sieht aus
    /// wie ein Fehler beim Verschicken.
    static func body(description: String, diagnostics: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return diagnostics }
        return "\(trimmed)\n\n\(diagnostics)"
    }

    // Hier stand ein `mailtoURL(subject:body:)` samt Prozent-Kodierung — ein
    // dritter Weg nach draussen, den kein Knopf je aufrief. Verschickt wird
    // über das Mail-Fenster, und ohne Mail-Konto über das Teilen-Blatt (siehe
    // `FeedbackSheet`); eine `mailto:`-URL kam dabei bewusst nie in Frage,
    // weil einzelne Mail-Programme lange Rümpfe stillschweigend kürzen. Zwei
    // Tests haben diesen Weg abgesichert und damit eine Prüf-Sicherheit
    // vorgetäuscht, die für den WIRKLICHEN Rückfallweg nicht galt.
}
