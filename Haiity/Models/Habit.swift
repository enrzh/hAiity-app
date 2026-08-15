import Foundation

/// Was ein Tag bei diesem Habit überhaupt bedeuten kann.
///
///  * `checkbox` — der Tag ist erledigt oder nicht.
///  * `quantity` — der Tag trägt einen Zählstand und zählt ab
///    `recurrence.target`.
///  * `yesNo` — der Tag wird BEANTWORTET: „Kein Zucker?" — Ja ist Erfolg,
///    Nein ist Misserfolg, und **unbeantwortet ist etwas Drittes**. Genau
///    diese Dreiteilung ist der Grund für die eigene Art: ein Zähler kann
///    „nein" nicht von „noch nichts" unterscheiden.
///
/// Nur `yesNo` steht als Marker in der Datei; `checkbox` und `quantity`
/// fallen wie bisher aus `recurrence.target`. Siehe `Habit.CodingKeys`.
enum HabitKind: String, Codable, CaseIterable, Sendable {
    case checkbox, quantity, yesNo

    var displayName: String {
        switch self {
        case .checkbox: return String(localized: "Abhaken")
        case .quantity: return String(localized: "Menge")
        case .yesNo:    return String(localized: "Ja/Nein")
        }
    }
}

enum HabitItemType: String, Codable, CaseIterable, Sendable {
    case habit
    case reminder
}

/// Ein Habit ist ein Jahr aus Quadraten. `log` hält Check-ins als lokale
/// Tagesschlüssel ("2026-08-09") — nie UTC, sonst rutscht ein
/// Abend-Check-in auf morgen. Log-Werte sind Zähler: 1 für Checkbox-Habits,
/// beliebige Zählstände für Mengen-Habits (ein Tag zählt ab
/// `recurrence.target`) — und für Ja/Nein-Habits zwei RESERVIERTE Codes weit
/// oberhalb jedes menschlichen Zählers (siehe `Habit.Answer`).
struct Habit: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var itemType: HabitItemType
    var createdAt: String
    /// Uhrzeit einer eigenen, konkreten Erinnerung in Minuten seit
    /// Mitternacht. Das bestehende Feld bleibt unverändert codiert, damit
    /// ältere Dateien und Geräte den Wert weiterhin verlustfrei tragen.
    var reminderMinutes: Int?
    /// Gemeinsame Termin- und Erinnerungszeit in Minuten seit Mitternacht;
    /// nil = ohne Uhrzeit und ohne habit-spezifische Erinnerung.
    var timeMinutes: Int?
    /// Individuelle Teilnahme am Kalender-Spiegel. Der Standard ist an,
    /// damit bestehende Habits und Erinnerungen ihr Verhalten behalten.
    var calendarSyncEnabled: Bool
    var log: [String: Int]
    /// Geplante Dauer einer Session in Minuten; nil = ohne Dauer
    /// („limitless" — eine Session zählt dann nur hoch). Rein additiv und
    /// tolerant dekodiert, KEIN Versionssprung: ein ausgelieferter Build
    /// überliest den Schlüssel und lässt ihn beim Speichern weg — die
    /// Einstellung reist über den Merge (neuerer `updatedAt` gewinnt,
    /// siehe `HabitStore.merge`) wieder ein.
    var durationMinutes: Int?
    /// Tatsächliche Session-Minuten je Tag — dieselben Tagesschlüssel wie
    /// `log`, dieselbe Müllabfuhr beim Lesen. Ein Tag trägt das MAXIMUM
    /// aller Sessions (Merge-Regel wie beim Log: das Größere gewinnt, nie
    /// wird gelöscht). Grundlage für „geplant vs. tatsächlich" in Stats.
    var minutes: [String: Int]
    /// Tagesschlüssel der Archivierung; nil = aktiv. Archivierte Habits
    /// behalten ihre Historie, verschwinden aber aus Liste und Summary.
    var archivedAt: String?
    /// Wiederholungsregel samt Mengenziel. Fehlt das Feld im JSON, lädt es
    /// als „täglich" — v1-Dateien bleiben unverändert lesbar; ein Alt-Ziel
    /// (`{"cadence":…}`) wird beim Lesen migriert (siehe `Recurrence`).
    ///
    /// **Das Mengenziel steckt hier drin, die Art daneben** — also müssen die
    /// beiden zusammengehalten werden. Wer die Regel setzt, setzt damit
    /// (auch) die Art: ein nachträglich angehängtes `target` macht aus einem
    /// Checkbox- ein Mengen-Habit, ein entferntes wieder zurück. Ohne diese
    /// eine Zeile gäbe es zwei Wahrheiten über dieselbe Frage, und die
    /// Rechnung entschiede je nachdem, welche sie zuerst liest.
    var recurrence: Recurrence {
        didSet {
            kind = Habit.resolvedKind(marker: kind.rawValue, log: log,
                                      target: recurrence.target)
        }
    }
    /// Eigene Rasterfarbe; nil = die App-Palette (Standardfall). Bewusst
    /// eine SEPARATE Einstellung von der globalen Palette: wer alles blau
    /// will, stellt es einmal um; wer EIN Habit hervorheben will, färbt nur
    /// dieses. Zeigt entweder auf eine eingebaute Familie oder auf eine
    /// eigene Farbe des Nutzers.
    var palette: PaletteRef?
    /// nil = globale Wischaktion verwenden. Ein gesetzter Wert ersetzt beide
    /// Seiten, damit "keine Aktion" eine bewusste lokale Entscheidung ist.
    var swipeActions: SwipeActionsOverride?
    /// Die Art des Habits. **Der einzige Wert, der hier etwas entscheidet,
    /// ist `.yesNo`** — `.checkbox` und `.quantity` fallen wie bisher aus
    /// `recurrence.target` und werden beim Anlegen wie beim Lesen
    /// normalisiert (siehe `Habit.resolvedKind`). Bei `.yesNo` ist ein
    /// gespeichertes Mengenziel bedeutungslos: die Art gewinnt.
    var kind: HabitKind

    var isReminder: Bool { itemType == .reminder }
    var isTrackedHabit: Bool { itemType == .habit }

    init(name: String,
         emoji: String = "",
         itemType: HabitItemType = .habit,
         reminderMinutes: Int? = nil,
         timeMinutes: Int? = nil,
         recurrence: Recurrence = .daily,
         kind: HabitKind = .checkbox,
         durationMinutes: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.itemType = itemType
        self.createdAt = DayKey.today()
        self.reminderMinutes = reminderMinutes
        self.timeMinutes = Habit.sanitizedMinutes(timeMinutes)
        self.calendarSyncEnabled = true
        self.log = [:]
        self.durationMinutes = Habit.sanitizedDuration(durationMinutes)
        self.minutes = [:]
        self.archivedAt = nil
        self.recurrence = recurrence
        self.palette = nil
        self.swipeActions = nil
        self.kind = Habit.resolvedKind(marker: kind.rawValue, log: [:],
                                       target: recurrence.target)
    }

    /// Bequemer Weg für Alt-Ziele: legt das Habit mit der MIGRIERTEN Regel
    /// an — genau der Pfad, den auch eine ausgelieferte Datei nimmt.
    init(name: String, emoji: String = "", reminderMinutes: Int? = nil, legacy: LegacyGoal) {
        self.init(name: name, emoji: emoji, reminderMinutes: reminderMinutes,
                  recurrence: .from(legacy: legacy))
    }
}

extension Habit {
    /// Minuten seit Mitternacht oder nichts. EINE Stelle für die Grenze,
    /// damit ein importiertes „1500" nicht als 25:00 Uhr in der Oberfläche
    /// landet.
    static func sanitizedMinutes(_ value: Int?) -> Int? {
        value.flatMap { (0..<24 * 60).contains($0) ? $0 : nil }
    }

    /// Geplante Session-Dauer: mindestens 1 Minute, höchstens ein Tag.
    /// Dieselbe Idee wie `sanitizedMinutes` — ein importiertes „0" oder
    /// „100000" wird zu „ohne Dauer" statt zu einer absurden Vorgabe.
    static func sanitizedDuration(_ value: Int?) -> Int? {
        value.flatMap { (1...24 * 60).contains($0) ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, itemType, createdAt, reminderMinutes, timeMinutes, calendarSyncEnabled, log, archivedAt, goal, palette, swipeActions
        // Session-Dauer (geplant) und tatsächliche Minuten je Tag. Rein
        // additiv — ein ausgelieferter Build überliest beide Schlüssel.
        case durationMinutes, minutes
        // Der Marker der Habit-Art. Rein additiv und NUR für „Ja/Nein" da —
        // siehe `kind` und die lange Begründung an `Answer`.
        case kind
    }

    /// Die WIRKSAME Art aus dem, was auf der Platte steht.
    ///
    /// **Die Reihenfolge ist die ganze Pointe.** Ein ausgelieferter Build
    /// (1…7) kennt den Schlüssel `kind` nicht: er überliest ihn beim Lesen
    /// UND lässt ihn beim Schreiben weg — nach einer Runde durch so ein
    /// Gerät ist der Marker WEG. Die Antworten selbst überleben das (sie
    /// stehen im `log`, das als Ganzes durchgereicht wird), also wird die
    /// Art aus IHNEN zurückgewonnen: steht irgendwo eine Antwort, ist es ein
    /// Ja/Nein-Habit. Der Marker ist damit nur noch für den einen Fall
    /// nötig, in dem es noch keine Antwort gibt — ein frisch angelegtes
    /// Ja/Nein-Habit.
    static func resolvedKind(marker: String?, log: [String: Int], target: Int?) -> HabitKind {
        if log.values.contains(where: Answer.isAnswer) { return .yesNo }
        if marker.flatMap(HabitKind.init(rawValue:)) == .yesNo { return .yesNo }
        return target != nil ? .quantity : .checkbox
    }

    /// Tolerantes Dekodieren: v1-Dateien (ohne goal/archivedAt) laden
    /// unverändert — keine Migration auf der Platte nötig.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        itemType = (try? c.decode(HabitItemType.self, forKey: .itemType)) ?? .habit
        createdAt = try c.decode(String.self, forKey: .createdAt)
        // Weiter tolerant gelesen, obwohl nichts mehr damit geplant wird —
        // eine Datei mit `reminderMinutes` muss vollständig durchlaufen
        // (siehe die Anmerkung am Feld).
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        // Fehlt der Schlüssel (jede Datei vor der Habit-Uhrzeit) oder steht
        // dort Unsinn: keine Uhrzeit statt eines Fehlers.
        timeMinutes = Habit.sanitizedMinutes(try c.decodeIfPresent(Int.self, forKey: .timeMinutes))
        calendarSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .calendarSyncEnabled) ?? true
        // Müllabfuhr an der Grenze: was formal kein Tag ist oder keinen
        // positiven Zähler hat, kommt gar nicht erst in den Speicher.
        // Bewusst NUR strukturell — ein Schlüssel von morgen (Gerät in einer
        // Zeitzone voraus) oder aus 1900 bleibt erhalten und wird erst in
        // der Rechen-Schicht ignoriert, statt hier Daten zu verlieren.
        let rawLog = try c.decodeIfPresent([String: Int].self, forKey: .log) ?? [:]
        log = rawLog.filter { $0.value >= 1 && DayKey.isValid($0.key) }
        // Session-Felder: fehlend (jede Datei vor den Sessions) oder kaputt
        // -> Standard statt Fehler. Die Minuten-Karte durchläuft dieselbe
        // Müllabfuhr wie der Log.
        durationMinutes = Habit.sanitizedDuration(try? c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? nil)
        let rawMinutes = ((try? c.decodeIfPresent([String: Int].self, forKey: .minutes)) ?? nil) ?? [:]
        minutes = rawMinutes.filter { $0.value >= 1 && DayKey.isValid($0.key) }
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt)
        // EIN Schlüssel für beide Formate: `Recurrence` erkennt am fehlenden
        // `freq`, dass dort ein Alt-Ziel steht, und migriert es. Ein kaputtes
        // Ziel darf das Habit nicht kosten — dann eben täglich.
        recurrence = ((try? c.decodeIfPresent(Recurrence.self, forKey: .goal)) ?? nil) ?? .daily
        // Unbekannte Paletten (Datei aus einer neueren Version) lesen als
        // "keine Übersteuerung" — nie als Fehler, sonst verliert ein
        // älterer Build beim nächsten Speichern das ganze Habit.
        palette = (try c.decodeIfPresent(String.self, forKey: .palette))
            .flatMap(PaletteRef.init(rawValue:))
        swipeActions = try c.decodeIfPresent(SwipeActionsOverride.self, forKey: .swipeActions)
        // ZULETZT, weil die Antworten im Log darüber mitentscheiden — ein
        // von einem älteren Build weggeschriebener Marker heilt sich daran.
        kind = Habit.resolvedKind(marker: try c.decodeIfPresent(String.self, forKey: .kind),
                                  log: log,
                                  target: recurrence.target)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(emoji, forKey: .emoji)
        if itemType != .habit { try c.encode(itemType, forKey: .itemType) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(reminderMinutes, forKey: .reminderMinutes)
        try c.encodeIfPresent(timeMinutes, forKey: .timeMinutes)
        if !calendarSyncEnabled { try c.encode(false, forKey: .calendarSyncEnabled) }
        try c.encode(log, forKey: .log)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
        // Der Standard bleibt implizit — Dateien sehen für einfache Habits
        // exakt aus wie v1 (plus Versionsnummer). Alles andere schreibt die
        // neue Regel UND, wo möglich, ihren Alt-Spiegel unter denselben
        // Schlüssel `goal` — ein ausgelieferter Build liest die Datei damit
        // unverändert weiter (kein Versionssprung, der ihn aussperrt).
        if recurrence != .daily { try c.encode(recurrence, forKey: .goal) }
        // Standards bleiben implizit: ohne Dauer und ohne Sessions sieht die
        // Datei Byte für Byte aus wie vorher.
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        if !minutes.isEmpty { try c.encode(minutes, forKey: .minutes) }
        try c.encodeIfPresent(palette?.rawValue, forKey: .palette)
        try c.encodeIfPresent(swipeActions, forKey: .swipeActions)
        // Wie überall: der Standard bleibt implizit. Geschrieben wird der
        // Marker nur für die eine Art, die man ihm nicht ansieht — Checkbox
        // und Menge fallen weiter aus `goal.target`, und eine Datei ohne
        // Ja/Nein-Habits sieht Byte für Byte aus wie vorher.
        if kind == .yesNo { try c.encode(kind.rawValue, forKey: .kind) }
    }
}

/// Optionale lokale Belegung beider Wischseiten. Fehlt der Wert, bleibt die
/// globale Konfiguration wirksam; ungueltige gespeicherte Werte fallen auf
/// die jeweilige globale Seite zurueck.
struct SwipeActionsOverride: Codable, Equatable, Sendable {
    var leading: SwipeActionChoice?
    var trailing: SwipeActionChoice?

    init(leading: SwipeActionChoice?, trailing: SwipeActionChoice?) {
        self.leading = leading
        self.trailing = trailing
    }

    private enum CodingKeys: String, CodingKey { case leading, trailing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leading = (try c.decodeIfPresent(String.self, forKey: .leading))
            .flatMap(SwipeActionChoice.init(rawValue:))
        trailing = (try c.decodeIfPresent(String.self, forKey: .trailing))
            .flatMap(SwipeActionChoice.init(rawValue:))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(leading?.rawValue, forKey: .leading)
        try c.encodeIfPresent(trailing?.rawValue, forKey: .trailing)
    }
}

// MARK: – Ja/Nein: die beiden Antworten

extension Habit {
    /// **Wie eine Antwort in eine Zahl passt — und warum ausgerechnet so.**
    ///
    /// Auf dem Telefon des Nutzers liegen die Builds 1…7, und sie
    /// synchronisieren DIESELBE iCloud-Datei. Was ein solcher Build nicht
    /// kennt, überliest er beim Dekodieren — und lässt es beim nächsten
    /// Speichern WEG. Daraus folgt hart, wo eine Antwort stehen darf:
    ///
    ///  * **Nicht als neues Feld an `Habit`.** `Habit.encode` schreibt nur
    ///    seine eigenen `CodingKeys`; ein Start plus ein Tipp auf dem alten
    ///    Build löschte jedes „Nein" aus der Datei und schöbe das nach
    ///    iCloud. Unumkehrbar.
    ///  * **Nicht als eigener Log-Schlüssel** („2026-08-09#no"): `Habit`
    ///    filtert beim Lesen gegen `DayKey.isValid` — der Schlüssel fiele
    ///    sofort heraus.
    ///  * **Nicht als negativer Wert**: derselbe Filter verlangt `>= 1`.
    ///
    /// Bleibt genau eine Stelle, die ein alter Build unverändert
    /// durchreicht: ein POSITIVER Int unter einem GÜLTIGEN Tagesschlüssel.
    /// Deshalb liegen die beiden Antworten in einem reservierten Band weit
    /// oberhalb jedes menschlichen Zählers. Ein ausgelieferter Build liest
    /// sie als „irgendein Wert ≥ 1", also als erledigten Tag — kosmetisch
    /// falsch, aber verlustfrei, und mit dem nächsten Start unter dieser
    /// Version wieder richtig.
    ///
    /// `yes > no` ist Absicht: der Merge nimmt pro Tag das MAXIMUM, ein
    /// Zusammenlauf zweier Geräte kann eine Antwort also nie verschwinden
    /// lassen und nie von Ja auf Nein drehen (siehe `HabitStore.merge`).
    enum Answer {
        /// Ausdrücklich verneint.
        static let no = 901_000
        /// Ausdrücklich bejaht.
        static let yes = 902_000

        /// Höchster Wert, den ein ECHTER Zähler je annehmen darf. Der Deckel
        /// steht in `HabitStore.increment`; ohne ihn wäre das reservierte
        /// Band eine Behauptung statt einer Zusage.
        static let maxCount = 900_000

        /// Gehört der Wert ins reservierte Band? (Nicht dasselbe wie „ist
        /// eine bekannte Antwort" — das Band ist breiter als die zwei Codes,
        /// damit eine spätere Antwort keinen Zähler überfährt.)
        static func isReserved(_ value: Int) -> Bool { value > maxCount }

        /// Genau eine der beiden bekannten Antworten.
        static func isAnswer(_ value: Int) -> Bool { value == yes || value == no }

        /// Die Stufe, mit der eine verneinte Zelle gezeichnet wird. Bewusst
        /// EIN reservierter Wert neben den fünf Rampenstufen 0…4 — damit
        /// erbt jeder Verbraucher von `Theme.level` (Liste, Vorschau,
        /// Teilen-Karte, alle Widgets) die Farbe ohne eigenes Zutun.
        static let declinedLevel = -1
    }

    /// Ist der Tag mit JA beantwortet?
    ///
    /// Tolerant nach oben: bei einem Ja/Nein-Habit gilt JEDER positive Wert
    /// außer der Verneinung als Ja. Das ist kein Schlendrian, sondern der
    /// Rückweg von einem ausgelieferten Build — der zeigt so ein Habit als
    /// Checkbox und schreibt beim Abhaken eine 1. Diese 1 als
    /// „unbeantwortet" zu lesen, hieße, den Tipp des Nutzers zu verschlucken.
    func isAffirmed(_ key: String) -> Bool {
        let value = log[key] ?? 0
        return value >= 1 && value != Answer.no
    }

    /// Ist der Tag ausdrücklich mit NEIN beantwortet? Nur Ja/Nein-Habits
    /// können das — bei allen anderen ist der Wert ein Zähler.
    func isDeclined(_ key: String) -> Bool {
        kind == .yesNo && log[key] == Answer.no
    }

    /// Überhaupt beantwortet (Ja ODER Nein)? Bei allen anderen Arten immer
    /// `false`: dort gibt es keinen Zustand „beantwortet, aber nicht erfüllt".
    func isAnswered(_ key: String) -> Bool {
        kind == .yesNo && (log[key] ?? 0) >= 1
    }

    /// Wie oft mit NEIN beantwortet — die Zahl, die es bei Checkbox und
    /// Menge schlicht nicht gibt. Über dieselbe Müllabfuhr wie alles andere.
    func declinedCount(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        guard kind == .yesNo else { return 0 }
        return validDays(today: today, calendar: calendar).filter { isDeclined($0) }.count
    }

    /// Der Log, umgeschrieben für eine ANDERE Art.
    ///
    /// Gebraucht wird das nur in einer Richtung: WEG von Ja/Nein. Die
    /// Selbstheilung beim Lesen (siehe `resolvedKind`) sieht die
    /// Antwort-Codes und macht daraus wieder ein Ja/Nein-Habit — eine
    /// Umstellung im Editor bliebe sonst bis zum nächsten Start bestehen und
    /// wäre danach weg. Also müssen die Daten mitkommen:
    ///
    ///  * Ja -> 1 (ein erledigter Tag, und genau so sah er auch aus)
    ///  * Nein -> KEIN Eintrag. Es gibt in einer Checkbox-Welt keinen
    ///    verneinten Tag; jeder andere Wert wäre eine Erfindung. Das ist der
    ///    einzige Datenverlust der ganzen Habit-Art, und er steht am Ende
    ///    einer ausdrücklichen Entscheidung des Nutzers.
    static func migratedLog(_ log: [String: Int], to kind: HabitKind) -> [String: Int] {
        guard kind != .yesNo else { return log }
        return log.compactMapValues { value in
            if value == Answer.no { return nil }
            return value == Answer.yes ? 1 : value
        }
    }
}

/// Lokale Tagesschlüssel und Datums-Arithmetik. Alles läuft über
/// `Calendar.current` in der lokalen Zeitzone — DST-sicher, weil nur mit
/// ganzen Kalendertagen gerechnet wird, nie mit 24-Stunden-Intervallen.
enum DayKey {
    /// Wie weit ein importierter Tag zurückliegen darf, bevor er als Müll
    /// gilt. Bewusst als Tages-SPANNE und nicht als Jahreszahl: in einem
    /// nicht-gregorianischen Nutzerkalender (Hidschri, äthiopisch) wäre
    /// jede feste Jahresgrenze falsch.
    static let plausibleSpanDays = 366 * 30

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func today(calendar: Calendar = .current) -> String {
        key(for: Date(), calendar: calendar)
    }

    /// STRIKT: nur exakt `JJJJ-MM-TT` aus ASCII-Ziffern, und nur, wenn der
    /// Kalender daraus genau denselben Schlüssel zurückrechnet. Ohne den
    /// Rückweg würde `Calendar.date(from:)` Unmögliches stillschweigend
    /// überrollen — "2026-13-45" wäre plötzlich der 14.02.2027 und ein
    /// kaputter Import würde echte Daten erfinden.
    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        guard let parts = components(key) else { return nil }
        var c = DateComponents()
        c.year = parts.year; c.month = parts.month; c.day = parts.day
        guard let date = calendar.date(from: c),
              Self.key(for: date, calendar: calendar) == key else { return nil }
        return date
    }

    /// Ist der Schlüssel überhaupt ein echtes Datum? ("quatsch",
    /// "2026-13-45", "2026-02-30", "" → nein.)
    static func isValid(_ key: String, calendar: Calendar = .current) -> Bool {
        date(from: key, calendar: calendar) != nil
    }

    /// Echtes Datum UND nicht in der Zukunft UND nicht absurd weit zurück.
    /// Genau das, was als Check-in zählen darf.
    static func isPlausible(_ key: String,
                            today: String = DayKey.today(),
                            calendar: Calendar = .current) -> Bool {
        guard let date = date(from: key, calendar: calendar), key <= today else { return false }
        guard let floor = plausibleFloor(today: today, calendar: calendar) else { return true }
        return date >= floor
    }

    /// Frühester noch plausibler Tag — einmal berechnen, dann in Schleifen
    /// wiederverwenden.
    static func plausibleFloor(today: String = DayKey.today(), calendar: Calendar = .current) -> Date? {
        guard let todayDate = date(from: today, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: -plausibleSpanDays, to: todayDate)
    }

    static func shifted(_ key: String, by days: Int, calendar: Calendar = .current) -> String? {
        guard let d = date(from: key, calendar: calendar),
              let s = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return Self.key(for: s, calendar: calendar)
    }

    /// "2026-08-09" -> (2026, 8, 9); nil bei allem, was formal kein
    /// Tagesschlüssel ist (Länge, Trennzeichen, ASCII-Ziffern).
    static func components(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return (y, m, d)
    }
}

extension Habit {
    /// „Steht an diesem Tag etwas Positives?"
    ///
    /// Für Checkbox und Menge unverändert „es gibt einen Eintrag" (bei
    /// Mengen also NICHT dasselbe wie erfüllt — dafür gibt es
    /// `GoalEngine.dayCounts`). Für Ja/Nein wäre genau diese alte Fassung
    /// eine Falle: eine Verneinung ist ein Wert ≥ 1 und würde als erledigt
    /// gelesen. Deshalb entscheidet dort die ANTWORT.
    func isDone(_ key: String) -> Bool {
        if kind == .yesNo { return isAffirmed(key) }
        return (log[key] ?? 0) >= 1
    }

    /// Log-Schlüssel, mit denen überhaupt gerechnet werden darf: echtes
    /// Datum, Wert ≥ 1, nicht in der Zukunft, nicht Jahrzehnte zurück.
    /// EINE Stelle für die ganze Müllabfuhr — Serien, Statistik und
    /// Gesamtzahlen hängen alle hier dran, damit eine importierte oder
    /// synchronisierte Datei mit "quatsch", "2026-13-45", "1900-01-01"
    /// oder Werten ≤ 0 nichts verfälschen kann.
    func validDays(today: String = DayKey.today(), calendar: Calendar = .current) -> [String] {
        let floor = DayKey.plausibleFloor(today: today, calendar: calendar)
        return log.compactMap { key, value in
            guard value >= 1, key <= today,
                  let date = DayKey.date(from: key, calendar: calendar) else { return nil }
            if let floor, date < floor { return nil }
            return key
        }
    }

    /// Zählende Tage (Ziel-Semantik) über die gesamte plausible Historie —
    /// das ist die Zahl, die "Gesamt" und "Tage insgesamt" meinen. Nicht
    /// `log.count`: das zählt auch Müll und unerfüllte Mengen-Tage mit.
    func checkInCount(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        validDays(today: today, calendar: calendar).filter {
            GoalEngine.dayCounts(habit: self, day: $0, calendar: calendar)
        }.count
    }

    /// Aktuelle Serie — dünner Durchgriff auf die GoalEngine, damit
    /// bestehende Views unverändert weiterlaufen.
    func streak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        GoalEngine.streak(habit: self, today: today, calendar: calendar)
    }

    /// Längste Serie über die gesamte Historie — dünner Durchgriff auf die
    /// GoalEngine, exakt wie `streak`. Die Ziel-Semantik (Mengenziel,
    /// Termine, flexible Perioden) liegt dort, damit "Best" dieselbe Einheit
    /// misst wie die laufende Serie.
    func bestStreak(today: String = DayKey.today(), calendar: Calendar = .current) -> Int {
        GoalEngine.bestStreak(habit: self, today: today, calendar: calendar)
    }

    /// Zellintensität 1…4 — dünner Durchgriff auf die GoalEngine.
    func intensity(_ key: String, calendar: Calendar = .current) -> Int {
        GoalEngine.intensity(habit: self, key: key, calendar: calendar)
    }
}
