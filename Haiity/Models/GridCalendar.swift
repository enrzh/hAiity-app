import Foundation

/// Small FIFO cache. Callers own synchronization; replacing an entry does
/// not evict unrelated graphs or grow the insertion order.
struct BoundedGraphCache<Key: Hashable, Value> {
    let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = limit
    }

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let newValue, limit > 0 else { return }
            if values[key] == nil {
                if order.count >= limit {
                    values.removeValue(forKey: order.removeFirst())
                }
                order.append(key)
            }
            values[key] = newValue
        }
    }

    mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }
}

/// Serializes cold graph/statistics calculations and lets queued work be
/// discarded when the view that requested it disappears. A detached task does
/// not inherit cancellation, so a fast tab switch could otherwise leave every
/// abandoned graph competing with the newly visible page.
enum ContributionSnapshotScheduler {
    private static let queue = DispatchQueue(
        label: "com.aiity.haiity.snapshot-work",
        qos: .utility)

    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    static func perform<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value? {
        let state = CancellationState()
        if Task.isCancelled { state.cancel() }

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard !state.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let value = work()
                    continuation.resume(returning: state.isCancelled ? nil : value)
                }
            }
        }, onCancel: {
            state.cancel()
        })
    }
}

/// Eine Monatsmarke über dem Raster: ab welcher Spalte ein Monat beginnt.
/// `year` gehört dazu, damit Jahreswechsel eindeutig bleiben (Jan 2026 und
/// Jan 2027 sind verschiedene Marken, auch wenn das Label gleich aussieht).
struct MonthMark: Equatable, Hashable, Sendable {
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
    struct Snapshot: Equatable, Sendable {
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
        var streak: Int = 0
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

    struct HabitSnapshotKey: Hashable {
        let habitID: UUID
        let log: [String: Int]
        let recurrence: Recurrence
        let createdAt: String
        let kind: HabitKind
        let missedDays: [String]
        let weeks: Int
        let today: String
        let calendar: Calendar

        init(habit: Habit, weeks: Int, today: String, calendar: Calendar) {
            habitID = habit.id
            log = habit.log
            recurrence = habit.recurrence
            createdAt = habit.createdAt
            kind = habit.kind
            missedDays = habit.missedDays
            self.weeks = weeks
            self.today = today
            self.calendar = calendar
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(habitID)
            hasher.combine(log)
            hasher.combine(kind)
            hasher.combine(missedDays)
            hasher.combine(weeks)
            hasher.combine(today)
            hasher.combine(calendar)
            // Recurrence is Equatable, not Hashable. Synthesized equality
            // still compares the complete rule and creation date on a hit.
        }

        func canDisplaySnapshot(for request: Self) -> Bool {
            habitID == request.habitID && weeks == request.weeks
                && today == request.today && calendar == request.calendar
        }
    }

    private struct ExternalCacheKey: Hashable {
        let levels: [String: Int]
        let weeks: Int
        let today: String
        let calendar: Calendar
    }

    private static let lock = NSLock()
    private static var cache = BoundedGraphCache<HabitSnapshotKey, Snapshot>(limit: 32)
    private static var externalCache = BoundedGraphCache<ExternalCacheKey, Snapshot>(limit: 32)

    /// Fast path for views that are recreated by List/tab navigation. The
    /// cold path remains scheduled off the main actor; a known snapshot should
    /// not make a warm graph wait for that queue just to redisplay itself.
    static func cachedSnapshot(habit: Habit,
                               weeks: Int = 53,
                               today: String = DayKey.today(),
                               calendar: Calendar = .current) -> Snapshot? {
        let key = HabitSnapshotKey(habit: habit, weeks: weeks, today: today, calendar: calendar)
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    static func displaySnapshot(habit: Habit, today: String,
                                calendar: Calendar = .current) -> Snapshot {
        let weeks = weeksForDisplay(habit: habit, today: today, calendar: calendar)
        return snapshot(habit: habit, weeks: weeks, today: today, calendar: calendar)
    }

    static func cachedSnapshot(levelsByDay: [String: Int],
                               weeks: Int,
                               today: String,
                               calendar: Calendar = .current) -> Snapshot? {
        let key = ExternalCacheKey(levels: levelsByDay,
                                   weeks: weeks,
                                   today: today,
                                   calendar: calendar)
        lock.lock()
        defer { lock.unlock() }
        return externalCache[key]
    }

    static func snapshot(habit: Habit,
                         weeks: Int = 53,
                         today: String = DayKey.today(),
                         calendar: Calendar = .current) -> Snapshot {
        let key = HabitSnapshotKey(habit: habit, weeks: weeks, today: today, calendar: calendar)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let built = build(habit: habit, weeks: weeks, today: today, calendar: calendar)

        lock.lock()
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
        let key = ExternalCacheKey(levels: levelsByDay,
                                   weeks: weeks,
                                   today: today,
                                   calendar: calendar)
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
                        filledCount: filled,
                        streak: GoalEngine.streak(habit: habit, today: today, calendar: calendar))
    }
}
