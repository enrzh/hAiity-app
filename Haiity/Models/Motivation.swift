import Foundation

/// Die tägliche Motivationsnachricht — ein Satz zur eingestellten Uhrzeit.
///
/// **Warum zwei Töpfe statt einer Liste.** Ein einziger Riesen-Array müsste
/// für jede Kombination aus Anrede und Aussage einen eigenen übersetzten
/// Text tragen: 12 × 24 wären 288 Sätze in 16 Sprachen. Getrennt sind es
/// 12 + 12 + 24 = 48 Texte, die dieselben 288 Kombinationen ergeben. Die
/// Anrede lebt doppelt (`openersNamed` mit `%@`, `openersPlain` ohne),
/// damit die Fassung mit Namen in jeder Sprache eigenständig klingen darf
/// — im Japanischen hängt die Anrede hinten, im Arabischen steht ein
/// Vokativ davor; ein nachträglich angeklebter Name wäre in beiden falsch.
///
/// **Warum verschiedene Salze — und warum die Lawine dazugehört.** Beide
/// Indizes kommen aus DEMSELBEN Tagesschlüssel. Ohne Salz wären sie
/// identisch, und mit bloß addiertem Salz liefen sie im Gleichschritt
/// (Index + k). Byteweise nachgehashtes Salz reicht aber auch noch nicht:
/// FNV-1a mischt seine UNTEREN Bits kaum. Die letzten k Bits des
/// Ergebnisses hängen nur von den letzten k Bits des Zwischenstands ab —
/// die Runde `(h ^ byte) &* prime` ist auf `2^k` eine Bijektion. Genau
/// diese unteren Bits nimmt aber `% 12` und `% 24`. Gemessen hieß das:
/// `Zeile % 8` legte `Anrede % 4` eindeutig fest, und von 288 möglichen
/// Paaren blieben 72 übrig. Deshalb läuft am Ende eine Lawinenstufe
/// (fmix64 aus MurmurHash3), die jedes obere Bit in die unteren zieht.
/// Danach: 281 verschiedene Paare in drei Jahren — der rechnerische
/// Erwartungswert für 1095 Ziehungen aus 288 Fächern.
///
/// **Warum lokal und nicht vom Server.** Wie `Celebration`: die App
/// verspricht Zero-Server, also entsteht die Personalisierung aus
/// Vorlagen auf dem Gerät. Der Name kommt aus `PersonalName.effective`
/// und verlässt das Gerät nie.
///
/// **Tonfall.** Ruhig, warm, konkret, gelegentlich trocken. Die Sätze
/// sprechen die Sprache der App (Quadrate, Zellen, Reihen, Raster,
/// Serien, dranbleiben) und nicht die eines Kalenderspruchs: kein leeres
/// Anfeuern, kein Hustle, keine Schuld, keine erfundene Dringlichkeit.
enum Motivation {

    // MARK: - Auswahl

    /// Salz der Anrede — die Ziffern sind die ASCII-Bytes von „opener".
    /// Ein Zahlenwert mit Bedeutung ist beim Nachlesen ehrlicher als eine
    /// zufällige Konstante, und er darf sich NIE ändern: ein anderes Salz
    /// verschiebt den ganzen Vorrat und die Nachricht von heute wäre
    /// plötzlich eine andere.
    static let openerSalt: UInt64 = 0x6f70656e6572

    /// Salz der Zeile — ASCII-Bytes von „line". Siehe `openerSalt`.
    static let lineSalt: UInt64 = 0x6c696e65

    /// FNV-1a über den Tagesschlüssel, mit Salz. Wie in `Celebration`:
    /// stabil über Prozesse und App-Starts hinweg — Swifts `hashValue` ist
    /// absichtlich je Lauf anders und taugt für einen Vorrat nicht, der
    /// den ganzen Tag denselben Satz zeigen soll.
    static func index(for dayKey: String, salt: UInt64, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in dayKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        // Das Salz läuft byteweise durch dieselbe Mühle, statt bloß auf
        // den Index addiert zu werden — sonst wären die beiden Folgen
        // gegeneinander verschoben, aber nicht unabhängig.
        var rest = salt
        for _ in 0 ..< 8 {
            hash ^= (rest & 0xff)
            hash = hash &* 0x100000001b3
            rest >>= 8
        }
        return Int(avalanche(hash) % UInt64(count))
    }

    /// fmix64 aus MurmurHash3: die Endmischung, die FNV-1a fehlt.
    ///
    /// FNV lässt seine unteren Bits fast unberührt (siehe oben), und
    /// genau die liest der Rest-Operator. Jede Zeile hier zieht obere
    /// Bits nach unten: verschieben, xor, mit einer ungeraden Konstanten
    /// multiplizieren. Ungerade heißt umkehrbar — es geht keine
    /// Information verloren, sie wird nur verteilt. Deterministisch und
    /// prozessübergreifend stabil bleibt es dadurch.
    static func avalanche(_ value: UInt64) -> UInt64 {
        var hash = value
        hash ^= hash >> 33
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash = hash &* 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        return hash
    }

    /// Titel (Anrede) und Text (Zeile) der Nachricht des Tages.
    /// `name` = nil oder leer ⇒ die neutrale Fassung der Anrede.
    static func message(name: String?, today: String) -> (title: String, body: String) {
        // Über die kleinere der beiden Anrede-Listen indizieren: die Listen
        // sind gleich lang (Vertrag im Test), aber ein Griff ins Leere darf
        // auch dann nicht passieren, wenn jemand eine Zeile vergisst.
        let openerCount = min(openersNamed.count, openersPlain.count)
        let opener = index(for: today, salt: openerSalt, count: openerCount)
        let line = index(for: today, salt: lineSalt, count: lines.count)

        let title: String
        if let name, !name.isEmpty {
            title = String(format: openersNamed[opener], name)
        } else {
            title = openersPlain[opener]
        }
        return (title, lines[line])
    }

    // MARK: - Vorrat: Anrede

    // Beide Listen laufen synchron: Index i ist DIESELBE Anrede, einmal mit
    // Namen und einmal ohne. Die Stücke sind bewusst klein gehalten — der
    // Release-Typprüfer braucht für ein einziges großes Array-Literal aus
    // `String(localized:)`-Aufrufen unangenehm lange.

    static let openersNamed: [String] = openersNamedA + openersNamedB

    static let openersPlain: [String] = openersPlainA + openersPlainB

    private static let openersNamedA: [String] = [
        String(localized: "Hallo %@"),
        String(localized: "Kurz für dich, %@"),
        String(localized: "Notiz an %@"),
        String(localized: "%@, ein Gedanke für heute"),
        String(localized: "Zwischenstopp, %@"),
        String(localized: "%@, das Raster meldet sich"),
    ]

    private static let openersNamedB: [String] = [
        String(localized: "%@, kurz innehalten"),
        String(localized: "Ein Satz für %@"),
        String(localized: "Schön, dass du da bist, %@"),
        String(localized: "%@, ein neuer Tag im Raster"),
        String(localized: "Kleine Erinnerung, %@"),
        String(localized: "%@, ohne Eile"),
    ]

    private static let openersPlainA: [String] = [
        String(localized: "Hallo"),
        String(localized: "Kurz für dich"),
        String(localized: "Eine Notiz"),
        String(localized: "Ein Gedanke für heute"),
        String(localized: "Zwischenstopp"),
        String(localized: "Das Raster meldet sich"),
    ]

    private static let openersPlainB: [String] = [
        String(localized: "Kurz innehalten"),
        String(localized: "Ein Satz für dich"),
        String(localized: "Schön, dass du da bist"),
        String(localized: "Ein neuer Tag im Raster"),
        String(localized: "Kleine Erinnerung"),
        String(localized: "Ohne Eile"),
    ]

    // MARK: - Vorrat: Zeilen

    static let lines: [String] = linesA + linesB + linesC + linesD

    private static let linesA: [String] = [
        String(localized: "Ein Quadrat heute ist mehr als ein Vorsatz für nächste Woche."),
        String(localized: "Die Reihe wächst langsam. Langsam ist auch eine Richtung."),
        String(localized: "Nicht jede Zelle muss voll sein. Die Reihe bleibt deine."),
        String(localized: "Zwei Minuten zählen im Raster genauso wie zwei Stunden."),
        String(localized: "Lücken sind kein Urteil. Sie sind nur Lücken."),
        String(localized: "Nach einer Lücke zählt das nächste Quadrat."),
    ]

    private static let linesB: [String] = [
        String(localized: "Serien reißen. Danach geht es an derselben Stelle weiter."),
        String(localized: "Ein einzelner Tag beweist nichts. Dafür gibt es die Reihe."),
        String(localized: "Du musst heute nichts nachholen. Heute reicht heute."),
        String(localized: "Das Raster merkt sich, was du getan hast."),
        String(localized: "Anfangen dauert oft kürzer als darüber nachzudenken."),
        String(localized: "Eine halbe Sache ist mehr als eine leere Zelle."),
    ]

    private static let linesC: [String] = [
        String(localized: "Du entscheidest heute nur über die Zelle von heute."),
        String(localized: "Wer dranbleibt, sammelt Quadrate. Wer wartet, sammelt Pläne."),
        String(localized: "Es muss nicht gut werden. Es muss stattfinden."),
        String(localized: "Schwung und Sturheit zählen im Raster gleich."),
        String(localized: "Drei Tage sehen unscheinbar aus und tragen trotzdem."),
        String(localized: "Fang mit dem Kleinsten an, das noch zählt."),
    ]

    private static let linesD: [String] = [
        String(localized: "Das Raster fragt nicht nach Motivation. Es fragt nach heute."),
        String(localized: "Aus Wiederholung wird Routine. Fang heute wieder an."),
        String(localized: "Perfekte Wochen sind selten. Brauchbare gibt es oft."),
        String(localized: "Wenn heute wenig geht, wird heute trotzdem eingetragen."),
        String(localized: "Ein Quadrat ist schnell gefüllt. Die Entscheidung zählt."),
        String(localized: "Am Ende bleibt die Reihe, nicht der einzelne Dienstag."),
    ]
}
