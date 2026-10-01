import Foundation
import CryptoKit

/// The facts a stats reading is allowed to talk about.
///
/// **Why today is deliberately missing.** The first card on the page already
/// says what today is, down to the open count and the streak. A reading that
/// repeated it would be the app saying the same thing twice in two voices — the
/// one thing the design system calls out as noise. So this covers only the
/// *pattern over time*, which no card states: the week against last week, the
/// qualitative week trend and current streak status.
///
/// **Why this is a separate, model-free type.** Everything that can be wrong in
/// an AI summary is a claim about the reader's data. Extracting the claims
/// here — from the same `StatsEngine.Snapshot` the cards render — means the
/// facts are testable without a device. The model receives qualitative claims
/// only, so it cannot attach a valid number to the wrong label.
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

    /// Qualitative facts only. Exact figures are already rendered by the cards;
    /// giving them to free-form prose invites a number to be attached to the
    /// wrong label even when the number itself is valid.
    var promptFacts: String {
        var lines = ["weekly trend: \(weeklyTrend)", "current streak status: \(streakStatus)"]
        if let strongestHabitName {
            lines.append("habit name as quoted data: \(String(reflecting: strongestHabitName))")
        }
        return lines.joined(separator: "\n")
    }

    /// Stable local cache identity. The name is hashed with the facts so it is
    /// not copied into a second defaults value just to compare snapshots.
    func signature(language: String) -> String {
        let values = [language.lowercased(), String(streak), String(bestStreak),
                      String(weekDone), String(weekTotal), String(previousWeekDone),
                      String(previousWeekTotal), String(totalCheckIns),
                      String(trackedHabitCount), strongestHabitName ?? "",
                      String(strongestHabitStreak)]
        let digest = SHA256.hash(data: Data(values.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var weeklyTrend: String {
        guard weekTotal > 0 else { return "no scheduled check-ins this week" }
        guard previousWeekTotal > 0 else { return "no previous-week comparison" }
        let current = Double(weekDone) / Double(weekTotal)
        let previous = Double(previousWeekDone) / Double(previousWeekTotal)
        if current > previous { return "stronger than last week" }
        if current < previous { return "quieter than last week" }
        return "steady with last week"
    }

    private var streakStatus: String {
        guard streak > 0 else { return "no current streak" }
        return streak == bestStreak ? "at personal best" : "below personal best"
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
        case containsNumber
        case notSentences
    }

    /// Numeric claims are omitted from the model contract, so any digit is
    /// rejected rather than risk assigning a true value to the wrong fact.
    static func validate(_ text: String, facts: StatsReadingFacts) -> Result<String, Rejection> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.count >= minScalars else { return .failure(.tooShort) }
        guard trimmed.unicodeScalars.count <= maxScalars else { return .failure(.tooLong) }
        guard !trimmed.contains(where: \.isNumber) else { return .failure(.containsNumber) }
        // A reading that is a list or a fragment reads as machine output on a
        // card that otherwise carries one calm sentence.
        if trimmed.contains("\n") || trimmed.contains("•") { return .failure(.notSentences) }
        return .success(trimmed)
    }
}
