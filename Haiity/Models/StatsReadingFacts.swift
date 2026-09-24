import Foundation

/// The facts a stats reading is allowed to talk about.
///
/// **Why today is deliberately missing.** The first card on the page already
/// says what today is, down to the open count and the streak. A reading that
/// repeated it would be the app saying the same thing twice in two voices — the
/// one thing the design system calls out as noise. So this covers only the
/// *pattern over time*, which no card states: the week against last week, the
/// longest run, the habit carrying it, the accumulated total.
///
/// **Why this is a separate, model-free type.** Everything that can be wrong in
/// an AI summary is a claim about the reader's data. Extracting the claims
/// here — from the same `StatsEngine.Snapshot` the cards render — means the
/// numbers are testable without a device, and the writer receives a closed set
/// of values it is then checked against. The model chooses the wording; it
/// never chooses the facts.
struct StatsReadingFacts: Equatable, Sendable {

    var streak: Int
    var bestStreak: Int
    var weekDone: Int
    var weekTotal: Int
    var previousWeekDone: Int
    var previousWeekTotal: Int
    var totalCheckIns: Int
    var trackedHabitCount: Int
    /// The habit with the longest current run, if any habit is tracked.
    var strongestHabitName: String?
    var strongestHabitStreak: Int

    init(snapshot: StatsEngine.Snapshot) {
        streak = snapshot.streak
        bestStreak = snapshot.bestStreak
        weekDone = snapshot.week.done
        weekTotal = snapshot.week.total
        previousWeekDone = snapshot.previousWeek.done
        previousWeekTotal = snapshot.previousWeek.total
        totalCheckIns = snapshot.totalCheckIns
        trackedHabitCount = snapshot.perHabit.count
        strongestHabitName = snapshot.perHabit.max(by: { $0.current < $1.current })?.name
        strongestHabitStreak = snapshot.perHabit.max(by: { $0.current < $1.current })?.current ?? 0
    }

    /// The habit's name is data too, so it is deliberately NOT in `numbers`:
    /// a digit inside a habit name ("Morning 5 Pages") must not be mistaken for
    /// a statistic the reading invented.
    /// Every number the writer is allowed to say. Today's numbers are absent on
    /// purpose: quoting one is not an invention, but it is the card's fact
    /// repeating, and the validator is the cheapest place to stop that.
    var numbers: Set<Int> {
        [streak, bestStreak, weekDone, weekTotal,
         previousWeekDone, previousWeekTotal,
         totalCheckIns, trackedHabitCount, strongestHabitStreak]
    }

    /// One line per fact, as handed to the writer. Flat and labelled: the
    /// writer's job is easier when it cannot misread which value is which.
    var promptFacts: String {
        var lines = [
            "habits tracked: \(trackedHabitCount)",
            "current streak across all habits: \(streak) days",
            "longest streak ever: \(bestStreak) days",
            "done this week: \(weekDone) of \(weekTotal)",
            "done last week: \(previousWeekDone) of \(previousWeekTotal)",
            "total check-ins: \(totalCheckIns)",
        ]
        if let strongestHabitName {
            lines.append("longest current run: \(strongestHabitStreak) days, habit \"\(strongestHabitName)\"")
        }
        return lines.joined(separator: "\n")
    }

    /// A reading needs something to say. No habits and no history is not a
    /// finding, and asking the model to comment on it would only invite
    /// invention.
    var hasSomethingToSay: Bool {
        trackedHabitCount > 0 && (weekTotal > 0 || totalCheckIns > 0)
    }
}

/// What a reading may look like. Separate from the facts because the checks
/// below are about the *text*, and they are the only thing standing between a
/// language model and a confident, wrong number on someone's stats screen.
enum StatsReadingValidator {

    static let maxScalars = 220
    static let minScalars = 20

    enum Rejection: Swift.Error, Equatable {
        case tooShort
        case tooLong
        case inventsNumber(String)
        case notSentences
    }

    /// Integers as they appear in running text, including the forms a model
    /// reaches for when it is being chatty: `1,234` and `1.234` both mean
    /// 1234, and a leading sign is not a statistic.
    private static let digits = try! NSRegularExpression(pattern: "[\\d][\\d.,]*")

    static func numbers(in text: String) -> [Int] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return digits.matches(in: text, range: range).compactMap { match in
            guard let whole = Range(match.range, in: text) else { return nil }
            let cleaned = text[whole]
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
            return Int(cleaned)
        }
    }

    /// Rejects a reading that mentions a number the facts do not contain.
    ///
    /// This is the whole hallucination guard, and it is checkable: every digit
    /// run in the output has to already exist in the input. A model that says
    /// "you checked in 47 times" when the fact is 4 fails here and the card
    /// falls back to the chart instead of showing it.
    static func validate(_ text: String, facts: StatsReadingFacts) -> Result<String, Rejection> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.count >= minScalars else { return .failure(.tooShort) }
        guard trimmed.unicodeScalars.count <= maxScalars else { return .failure(.tooLong) }

        for number in numbers(in: trimmed) where !facts.numbers.contains(number) {
            return .failure(.inventsNumber(String(number)))
        }
        // A reading that is a list or a fragment reads as machine output on a
        // card that otherwise carries one calm sentence.
        if trimmed.contains("\n") || trimmed.contains("•") { return .failure(.notSentences) }
        return .success(trimmed)
    }
}
