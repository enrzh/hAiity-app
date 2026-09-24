import Foundation

/// A motivational line the on-device model wrote, pinned to the day it belongs
/// to.
///
/// **Why the day is part of the value.** The same sentence has to appear on the
/// lock screen, in the Live Activity, and in the settings preview. Those are
/// three readers, and two of them run outside the foreground app. Generating on
/// demand would let them disagree, so the line is written once and read by all.
struct GeneratedMotivation: Codable, Equatable, Sendable {
    var dayKey: String
    var line: String
}

/// Persists today's generated line plus a rolling window of what came before.
///
/// The history is not a log. It is the negative examples handed to the model so
/// it does not paraphrase yesterday, and the set the validator checks an echo
/// against. It doubles as the scheduler's cache, which is why the window is
/// kept rather than only today.
enum MotivationGeneratedStore {

    /// Two planning windows' worth of days. `Reminders` plans seven days ahead
    /// and re-plans on every settings change, so anything shorter would send
    /// the model back for days it had already written — slow, wasteful, and it
    /// would push the same day's line into the negative examples again and
    /// again. The retained lines double as those examples, so there is only
    /// ever one list to keep correct.
    static let windowLimit = 14

    private static let key = "motivation.generated.v1"

    /// Oldest first. An array rather than a dictionary because order is what
    /// makes eviction and the negative-example window obvious.
    private struct Payload: Codable {
        var days: [GeneratedMotivation]
        init(days: [GeneratedMotivation] = []) { self.days = days }
    }

    private static func payload(in defaults: UserDefaults) -> Payload {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload() }
        return decoded
    }

    private static func save(_ payload: Payload, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    /// The line already written for this day, if any.
    static func line(for dayKey: String, in defaults: UserDefaults) -> String? {
        payload(in: defaults).days.last { $0.dayKey == dayKey }?.line
    }

    /// Every retained line, oldest first. These are the negative examples: what
    /// the model must not repeat or paraphrase.
    static func recentLines(in defaults: UserDefaults) -> [String] {
        payload(in: defaults).days.map(\.line)
    }

    /// Stores a freshly written line for a day.
    ///
    /// Rewriting a day replaces its entry rather than adding a second one, so a
    /// superseded sentence stops counting as something the person has seen.
    static func record(_ line: String, for dayKey: String, in defaults: UserDefaults) {
        var payload = payload(in: defaults)
        if let index = payload.days.firstIndex(where: { $0.dayKey == dayKey }) {
            payload.days[index].line = line
        } else {
            payload.days.append(GeneratedMotivation(dayKey: dayKey, line: line))
        }
        if payload.days.count > windowLimit {
            payload.days.removeFirst(payload.days.count - windowLimit)
        }
        save(payload, in: defaults)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }

    /// Delete the retired feed's cached quotes, once.
    ///
    /// The network source is gone, so its 200 cached entries are dead weight in
    /// the user's defaults and a leftover reminder that this app once pulled
    /// text off a server. Guarded by its own flag so this runs on the first
    /// launch after the change and never again.
    static func discardRetiredFeedOnce(in defaults: UserDefaults) {
        let flag = "motivation.retiredFeedCleared"
        guard defaults.object(forKey: flag) == nil else { return }
        defaults.removeObject(forKey: "motivationFeed.entries")
        defaults.removeObject(forKey: "motivationFeed.receivedAt")
        defaults.set(true, forKey: flag)
    }
}

/// Reading and writing the day's line — deliberately two different things.
///
/// **Why writing is never automatic.** Running the model makes the device warm.
/// The scheduler used to write a whole seven-day window on every settings
/// change, which meant a model call per day, per reschedule, with nobody
/// asking. So writing is only ever reached from a deliberate tap; everything
/// else — the notification scheduler, the Live Activity, the preview — reads
/// the cache and is satisfied by the built-in pool when it is empty.
enum MotivationDaily {

    /// Writes one line, or `nil` when it could not.
    ///
    /// Injected rather than referenced so the decision logic is testable, and
    /// optional rather than throwing so the caller never has to name an
    /// iOS 26-only error type from a closure that also runs on iOS 17.
    typealias Writer = (_ language: String, _ recent: [String]) async -> String?

    /// The production writer: the one place the iOS 26 model is actually
    /// called. A second copy of this adapter is how the scheduler and the
    /// settings screen would quietly start disagreeing about availability.
    static let onDeviceWriter: Writer = { language, recent in
        guard #available(iOS 26.0, *), OnDeviceModel.isAvailable else { return nil }
        do {
            return try await MotivationWriter.line(language: language, recent: recent)
        } catch {
            NSLog("MotivationDaily: on-device write failed: %@", String(describing: error))
            return nil
        }
    }

    /// The line already written for a day, if any.
    ///
    /// A pure read: no availability check, no model, no write. Safe to call from
    /// a scheduler that runs on a background queue or inside the widget
    /// extension, where doing real work would be the bug.
    static func cachedLine(for dayKey: String, in defaults: UserDefaults) -> String? {
        MotivationGeneratedStore.discardRetiredFeedOnce(in: defaults)
        return MotivationGeneratedStore.line(for: dayKey, in: defaults)
    }

    /// Write a line for a day because the person asked for one.
    ///
    /// - Returns: the new line, the line already cached for that day, or `nil`
    ///   when it could not be written. Returning the cached line on a repeat tap
    ///   is deliberate: a second tap should not quietly buy a second model call
    ///   and a warmer device for the same sentence.
    static func writeLine(for dayKey: String,
                          language: String,
                          defaults: UserDefaults,
                          available: Bool = OnDeviceModel.isAvailable,
                          write: Writer) async -> String? {
        MotivationGeneratedStore.discardRetiredFeedOnce(in: defaults)
        if let existing = MotivationGeneratedStore.line(for: dayKey, in: defaults) {
            return existing
        }
        guard available else { return nil }
        guard let line = await write(language, MotivationGeneratedStore.recentLines(in: defaults)),
              !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        MotivationGeneratedStore.record(line, for: dayKey, in: defaults)
        return line
    }

    /// The one call the settings screen makes, so the tap handler does not have
    /// to choose between the two paths and get it wrong.
    static func rerollOrWriteLine(for dayKey: String,
                                   language: String,
                                   reroll: Bool,
                                   defaults: UserDefaults,
                                   write: Writer = MotivationDaily.onDeviceWriter) async -> String? {
        reroll ? await rerollLine(for: dayKey, language: language, defaults: defaults, write: write)
               : await writeLine(for: dayKey, language: language, defaults: defaults, write: write)
    }

    /// Replace the line for a day, even if one is already there.
    ///
    /// Separate from `writeLine` because a re-roll is a second, explicit request
    /// for heat — the caller has to mean it, and the superseded line leaves the
    /// "already shown" set so the next write cannot echo it.
    static func rerollLine(for dayKey: String,
                           language: String,
                           defaults: UserDefaults,
                           available: Bool = OnDeviceModel.isAvailable,
                           write: Writer) async -> String? {
        MotivationGeneratedStore.discardRetiredFeedOnce(in: defaults)
        guard available else { return nil }
        guard let line = await write(language, MotivationGeneratedStore.recentLines(in: defaults)),
              !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        MotivationGeneratedStore.record(line, for: dayKey, in: defaults)
        return line
    }
}
