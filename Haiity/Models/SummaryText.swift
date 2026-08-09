import Foundation

/// Der TEXT der beiden Zusammenfassungen — rein, ohne Store und ohne
/// Benachrichtigungssystem, damit „3 von 5 erledigt · offen: Laufen,
/// Meditation" im Test entsteht und nicht erst auf dem Sperrbildschirm.
///
/// Zwei Entscheidungen stecken darin:
///
///  * **Nichts zu sagen heißt nichts sagen.** Steht an einem Tag gar kein
///    Termin an (Wochenende, ausgesetzte Regel, gar keine Habits), gibt es
///    keinen Satz — und damit keine Benachrichtigung. Eine Meldung „0 von 0"
///    ist die unangenehmste Sorte Erinnerung.
///  * **Die Liste bricht ab.** Wer zwölf offene Habits hat, braucht keine
///    zwölf Namen auf dem Sperrbildschirm; nach `maxNames` folgt „und N
///    weitere". Ohne die Grenze schneidet iOS mitten im Wort ab, und zwar an
///    einer Stelle, die niemand gewählt hat.
enum SummaryText {

    /// So viele Namen stehen ausgeschrieben da, bevor gezählt wird.
    static let maxNames = 3

    /// Namen als Aufzählung, ab `maxNames + 2` mit Rest-Zähler:
    /// „Laufen, Meditation und Lesen" -> „Laufen, Meditation, Lesen und 3
    /// weitere".
    ///
    /// Der genau EINE Name zu viel wird noch ausgeschrieben: „und 1 weiteres"
    /// ist länger als der Name selbst und sagt weniger.
    static func nameList(_ names: [String], max limit: Int = maxNames,
                         locale: Locale = .current) -> String {
        guard !names.isEmpty else { return "" }
        guard names.count > limit + 1, limit >= 1 else { return join(names, locale: locale) }
        // Der Rest ist hier immer mindestens ZWEI (bei genau einem zu viel
        // steht der Name selbst da) — deshalb gibt es keine Einzahl-Form.
        let rest = names.count - limit
        var shown = Array(names.prefix(limit))
        shown.append(String(localized: "\(rest) weitere"))
        return join(shown, locale: locale)
    }

    private static func join(_ names: [String], locale: Locale) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: names) ?? names.joined(separator: ", ")
    }

    /// Der Satz der Tageszusammenfassung. nil, wenn heute gar nichts fällig
    /// war.
    static func daily(_ status: SummaryStatus, locale: Locale = .current) -> String? {
        guard status.total > 0 else { return nil }
        guard !status.missing.isEmpty else {
            return String(localized: "Alles erledigt — \(status.done) von \(status.total).")
        }
        let names = nameList(status.missing, locale: locale)
        return String(localized: "\(status.done) von \(status.total) erledigt · offen: \(names)")
    }

    /// Der Satz der Wochenzusammenfassung. nil, wenn diese Woche gar kein
    /// Termin fällig war.
    static func weekly(_ status: SummaryStatus, locale: Locale = .current) -> String? {
        guard status.total > 0 else { return nil }
        guard !status.missing.isEmpty else {
            return String(localized: "Volle Woche — \(status.done) von \(status.total) Terminen.")
        }
        let names = nameList(status.missing, locale: locale)
        return String(localized: "\(status.done) von \(status.total) Terminen · offen: \(names)")
    }
}
