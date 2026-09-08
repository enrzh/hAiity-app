import Foundation

/// Eine Monatsmarke über dem Raster: ab welcher Spalte ein Monat beginnt.
/// `year` gehört dazu, damit Jahreswechsel eindeutig bleiben (Jan 2026 und
/// Jan 2027 sind verschiedene Marken, auch wenn das Label gleich aussieht).
struct MonthMark: Equatable, Hashable {
    let column: Int
    let year: Int
    let month: Int
}

/// Reine Raster-Mathematik für das Contribution-Grid — ohne SwiftUI, ohne
/// Store, mit explizitem Calendar. Zwei Aufgaben:
///
///  1. **Korrektheit**: welche Tage stehen in welcher Spalte, welche liegen
///     in der Zukunft (nie tippbar), wo beginnt ein neuer Monat.
///  2. **Tempo**: das Skelett (371 Datumsadditionen) und die Zellstufen
///     (bis zu 7 Rückwärtsschritte pro Zelle) werden pro
///     (Habit, Log-Stand, Fenster, heute) **einmal** gerechnet und
///     gecacht — nicht bei jeder `body`-Auswertung des Scrollens.
enum GridCalendar {
    /// Zeilen pro Spalte: So … Sa (GitHub-Anordnung, unabhängig von
    /// `firstWeekday` — die Chronologie soll überall gleich aussehen).
    static let rows = 7

    /// Fertiges Raster für genau eine Kombination aus Habit und Fenster.
    struct Snapshot: Equatable {
        let weeks: Int
        let today: String
        /// [Spalte][Zeile]; nil = Zukunft (nach `today`).
        let keys: [[String?]]
        /// Parallel zu `keys`: Intensitätsstufe 0…4 (Zukunft = 0).
        let levels: [[Int]]
        /// ALLE Monatswechsel im Fenster, ungefiltert — der Kollisionsfilter
        /// hängt an der Zellbreite und läuft deshalb erst in der View.
        let marks: [MonthMark]
        /// Zählende Tage im sichtbaren Fenster (für die VoiceOver-Zusammenfassung).
        let filledCount: Int
    }

    // MARK: – Geometrie

    /// Startdatum (Zeile 0 = Sonntag) jeder Spalte, älteste zuerst. Die
    /// letzte Spalte ist die laufende Woche.
    static func columnStarts(weeks: Int, today: String, calendar: Calendar = .current) -> [Date] {
        guard weeks > 0 else { return [] }
        let base = DayKey.date(from: today, calendar: calendar)
            ?? calendar.startOfDay(for: Date())
        let dow = calendar.component(.weekday, from: base) - 1 // 0 = So
        guard let lastSat = calendar.date(byAdding: .day, value: 6 - dow, to: base) else { return [] }
        return (0..<weeks).compactMap {
            calendar.date(byAdding: .day, value: -(weeks * rows - 1) + $0 * rows, to: lastSat)
        }
    }

    /// Tagesschlüssel je Spalte; nil für alles nach `today`. Der Vergleich
    /// läuft über die nullgepolsterten Schlüssel selbst — kein
    /// Uhrzeit-Vergleich, damit ein Check-in um 23:59 nicht "in der Zukunft"
    /// landet.
    static func keys(weeks: Int, today: String, calendar: Calendar = .current) -> [[String?]] {
        columnStarts(weeks: weeks, today: today, calendar: calendar).map { start in
            (0..<rows).map { r -> String? in
                guard let d = calendar.date(byAdding: .day, value: r, to: start) else { return nil }
                let k = DayKey.key(for: d, calendar: calendar)
                return k <= today ? k : nil
            }
        }
    }

    /// Number of columns that carry meaningful history, with enough columns
    /// to fill the normal card viewport but without an artificial blank year
    /// before a recently created habit.
    static func weeksForDisplay(habit: Habit,
                                today: String,
                                minimumWeeks: Int = 24,
                                maximumWeeks: Int = 53,
                                calendar: Calendar = .current) -> Int {
        guard maximumWeeks > 0 else { return 0 }
        let minimum = min(maximumWeeks, max(1, minimumWeeks))
        guard let todayDate = DayKey.date(from: today, calendar: calendar) else {
            return minimum
        }

        var earliestKey = today
        if DayKey.isPlausible(habit.createdAt, today: today, calendar: calendar) {
            earliestKey = min(earliestKey, habit.createdAt)
        }
        if let firstLoggedDay = habit.validDays(today: today, calendar: calendar).min() {
            earliestKey = min(earliestKey, firstLoggedDay)
        }
        guard let earliestDate = DayKey.date(from: earliestKey, calendar: calendar) else {
            return minimum
        }

        let firstWeek = weekStart(for: earliestDate, calendar: calendar)
        let currentWeek = weekStart(for: todayDate, calendar: calendar)
        let days = calendar.dateComponents([.day], from: firstWeek, to: currentWeek).day ?? 0
        let naturalWeeks = max(1, days / rows + 1)
        return min(maximumWeeks, max(minimum, naturalWeeks))
    }

    /// Same window calculation for external contribution data. Keeping the
    /// date window here means GitHub and habits use the same seven-row grid
    /// instead of maintaining two subtly different calendars.
    static func weeksForDisplay(dates: [String],
                                today: String,
                                minimumWeeks: Int = 1,
                                maximumWeeks: Int = 53,
                                calendar: Calendar = .current) -> Int {
        guard maximumWeeks > 0 else { return 0 }
        let minimum = min(maximumWeeks, max(1, minimumWeeks))
        guard let todayDate = DayKey.date(from: today, calendar: calendar),
              let earliestDate = dates.compactMap({ DayKey.date(from: $0, calendar: calendar) }).min()
        else { return minimum }

        let firstWeek = weekStart(for: earliestDate, calendar: calendar)
        let currentWeek = weekStart(for: todayDate, calendar: calendar)
        let days = calendar.dateComponents([.day], from: firstWeek, to: currentWeek).day ?? 0
        let naturalWeeks = max(1, days / rows + 1)
        return min(maximumWeeks, max(minimum, naturalWeeks))
    }

    /// Whether a horizontal graph has content beyond its measured viewport.
    /// A small tolerance prevents fractional layout measurements from leaving
    /// a recent graph with a pointless one-pixel bounce.
    static func needsHorizontalScroll(contentWidth: CGFloat,
                                      viewportWidth: CGFloat) -> Bool {
        guard viewportWidth > 0 else { return true }
        return contentWidth > viewportWidth + 0.5
    }

    private static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.component(.weekday, from: date) - 1
        return calendar.date(byAdding: .day,
                            value: -day,
                            to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
    }

    // MARK: – Monatsmarken

    /// Jede Spalte, deren erster Tag in einem neuen Monat liegt. Die
    /// **erste** Spalte bekommt nur dann eine Marke, wenn sie wirklich am
    /// Monatsanfang steht (Tag ≤ 7) — sonst würde ein angeschnittener Monat
    /// am linken Rand fälschlich als Monatsanfang gelesen.
    static func rawMarks(weeks: Int, today: String, calendar: Calendar = .current) -> [MonthMark] {
        var out: [MonthMark] = []
        var previousMonth: Int?
        for (i, start) in columnStarts(weeks: weeks, today: today, calendar: calendar).enumerated() {
            let c = calendar.dateComponents([.year, .month, .day], from: start)
            guard let year = c.year, let month = c.month, let day = c.day else { continue }
            if let previous = previousMonth {
                if month != previous { out.append(MonthMark(column: i, year: year, month: month)) }
            } else if day <= 7 {
                out.append(MonthMark(column: i, year: year, month: month))
            }
            previousMonth = month
        }
        return out
    }

    /// Eine platzierte Monatsmarke: Marke plus linke Textkante in Punkten.
    struct PlacedMark: Equatable {
        let mark: MonthMark
        let x: CGFloat
    }

    /// Setzt die Monatslabels kollisionsfrei. Gerechnet wird mit der ECHTEN
    /// Textbreite (`width`), nicht mit einer Spaltenschätzung — "Aug." und
    /// "أغسطس" brauchen sehr unterschiedlich viel Platz, und mit großer
    /// Dynamic-Type-Stufe wird aus beidem das Doppelte.
    ///
    /// Zwei Regeln:
    ///  * **Rechter Rand**: ein Label, das über die Rasterbreite hinausragen
    ///    würde, wird nach links geschoben statt abgeschnitten (maximal um
    ///    seine eigene Breite — der aktuelle Monat ist die wichtigste Marke
    ///    und darf nicht einfach verschwinden).
    ///  * **Kollision**: passt eine Marke nach dem Schieben nicht mehr
    ///    hinter die vorige, fällt sie weg. Lieber weniger Labels als
    ///    übereinanderliegende.
    static func placeMarks(_ marks: [MonthMark],
                           pitch: CGFloat,
                           contentWidth: CGFloat,
                           spacing: CGFloat = 4,
                           width: (MonthMark) -> CGFloat) -> [PlacedMark] {
        var out: [PlacedMark] = []
        var lastRight = -CGFloat.greatestFiniteMagnitude
        for mark in marks {
            let w = width(mark)
            guard w > 0, w <= contentWidth else { continue }
            let x = max(0, min(CGFloat(mark.column) * pitch, contentWidth - w))
            guard x >= lastRight + spacing else { continue }
            out.append(PlacedMark(mark: mark, x: x))
            lastRight = x + w
        }
        return out
    }

    /// Lokalisierte Monatsabkürzung — `shortMonthSymbols` folgt der Locale
    /// des Kalenders (de: "Aug", en: "Aug", fr: "août", ar: "أغسطس").
    static func label(for mark: MonthMark, calendar: Calendar = .current) -> String {
        let symbols = calendar.shortMonthSymbols
        guard mark.month >= 1, mark.month <= symbols.count else { return "" }
        return symbols[mark.month - 1]
    }

    // MARK: – Tippbarkeit

    /// Zukunft ist nie tippbar, leere Slots auch nicht, und ein nicht
    /// interaktives Raster (Teilen-Karte, Vorschau) sowieso nicht.
    static func isTappable(key: String?, interactive: Bool, today: String) -> Bool {
        guard interactive, let key, DayKey.isValid(key) else { return false }
        return key <= today
    }

    /// Welcher Tagesschlüssel unter einem Punkt im Spalten-Koordinatenraum
    /// liegt (Ursprung: linke obere Ecke der ersten Zelle). Nur die ZELLE
    /// trifft, nicht die Lücke — exakt die Trefferfläche, die die Zellen
    /// vorher einzeln hatten, als jede ihren eigenen Erkenner trug.
    static func hitKey(location: CGPoint,
                       keys: [[String?]],
                       cell: CGFloat,
                       gap: CGFloat) -> String? {
        let pitch = cell + gap
        guard pitch > 0, cell > 0, location.x >= 0, location.y >= 0 else { return nil }
        let wi = Int(location.x / pitch)
        let r = Int(location.y / pitch)
        guard wi >= 0, wi < keys.count, r >= 0, r < rows else { return nil }
        // In der Lücke hinter bzw. unter der Zelle: kein Treffer.
        guard location.x - CGFloat(wi) * pitch <= cell,
              location.y - CGFloat(r) * pitch <= cell else { return nil }
        return keys[wi][r]
    }

    // MARK: – Snapshot mit Cache

    /// Anzahl der ECHTEN Neuberechnungen (Cache-Misses). Der Test belegt
    /// damit, dass Scrollen keine 371 Datumsadditionen pro Frame kostet.
    private(set) static var computeCount = 0

    private struct CacheKey: Hashable {
        let habit: UUID
        let logHash: Int
        let target: Int?
        /// Die ART gehört mit hinein: sie ändert die Zellstufen, ohne dass
        /// sich ein einziger Log-Wert ändert (aus einem Ja/Nein-Habit ein
        /// Checkbox-Habit zu machen färbt jede verneinte Zelle um).
        let kind: HabitKind
        let missedHash: Int
        let weeks: Int
        let today: String
        let firstWeekday: Int
    }

    private struct ExternalCacheKey: Hashable {
        let levelsHash: Int
        let count: Int
        let weeks: Int
        let today: String
        let firstWeekday: Int
    }

    private static let lock = NSLock()
    private static var cache: [CacheKey: Snapshot] = [:]
    private static var externalCache: [ExternalCacheKey: Snapshot] = [:]
    /// Deckel gegen unbegrenztes Wachsen (viele Habits × Tagewechsel):
    /// bei Überlauf wird komplett geleert statt LRU-Buchführung zu betreiben.
    private static let cacheLimit = 32

    static func snapshot(habit: Habit,
                         weeks: Int = 53,
                         today: String = DayKey.today(),
                         calendar: Calendar = .current) -> Snapshot {
        let key = CacheKey(habit: habit.id,
                           logHash: habit.log.hashValue,
                           target: habit.recurrence.target,
                           kind: habit.kind,
                           missedHash: habit.missedDays.hashValue,
                           weeks: weeks,
                           today: today,
                           firstWeekday: calendar.firstWeekday)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let built = build(habit: habit, weeks: weeks, today: today, calendar: calendar)

        lock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = built
        computeCount += 1
        lock.unlock()
        return built
    }

    /// Converts any date-keyed contribution source into the same snapshot
    /// consumed by the habit graph renderer. Missing past days are level 0;
    /// future cells remain nil and are drawn with the same dimming rule.
    static func snapshot(levelsByDay: [String: Int],
                         weeks: Int,
                         today: String,
                         calendar: Calendar = .current) -> Snapshot {
        let key = ExternalCacheKey(levelsHash: levelsByDay.hashValue,
                                   count: levelsByDay.count,
                                   weeks: weeks,
                                   today: today,
                                   firstWeekday: calendar.firstWeekday)
        lock.lock()
        if let hit = externalCache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let grid = keys(weeks: weeks, today: today, calendar: calendar)
        var filled = 0
        let levels = grid.map { column in
            column.map { key -> Int in
                guard let key else { return 0 }
                if levelsByDay[key] != nil { filled += 1 }
                return levelsByDay[key] ?? 0
            }
        }
        let snapshot = Snapshot(weeks: weeks,
                                today: today,
                                keys: grid,
                                levels: levels,
                                marks: rawMarks(weeks: weeks, today: today, calendar: calendar),
                                filledCount: filled)
        lock.lock()
        if externalCache.count >= cacheLimit { externalCache.removeAll(keepingCapacity: true) }
        externalCache[key] = snapshot
        lock.unlock()
        return snapshot
    }

    /// Nur für Tests: Cache und Zähler zurücksetzen.
    static func resetCache() {
        lock.lock()
        cache.removeAll()
        externalCache.removeAll()
        computeCount = 0
        lock.unlock()
    }

    private static func build(habit: Habit, weeks: Int, today: String, calendar: Calendar) -> Snapshot {
        let grid = keys(weeks: weeks, today: today, calendar: calendar)
        var filled = 0
        let levels = grid.map { column in
            column.map { key -> Int in
                guard let key else { return 0 }
                if GoalEngine.dayCounts(habit: habit, day: key, calendar: calendar) { filled += 1 }
                return GoalEngine.intensity(habit: habit, key: key, calendar: calendar)
            }
        }
        return Snapshot(weeks: weeks,
                        today: today,
                        keys: grid,
                        levels: levels,
                        marks: rawMarks(weeks: weeks, today: today, calendar: calendar),
                        filledCount: filled)
    }
}
