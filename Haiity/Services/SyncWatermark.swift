import Foundation

/// Shared ownership metadata for native items written by hAiity.
///
/// The visible product name is useful when a user opens an event or reminder.
/// The item identity is encoded with Unicode tag scalars, so it remains in the
/// note without adding an intrusive UUID to the native app's UI.
enum SyncWatermark {
    enum Kind: String, CaseIterable, Hashable, Sendable {
        case habitCalendar
        case reminderCalendar
        case nativeReminder

        var hintTitle: String {
            switch self {
            case .habitCalendar: return String(localized: "Habit im Kalender")
            case .reminderCalendar: return String(localized: "Reminder im Kalender")
            case .nativeReminder: return String(localized: "Reminder in Erinnerungen")
            }
        }
    }

    struct Ownership: Equatable, Sendable {
        let kind: Kind
        let id: UUID
    }

    static let readablePrefix = "hAiity"
    private static let boundary = "\u{2063}"
    private static let tagBase: UInt32 = 0xE0000

    static func note(for id: UUID, kind: Kind) -> String {
        let payload = "\(kind.rawValue)|\(id.uuidString)"
        return "\(readablePrefix)\n\(boundary)\(encode(payload))\(boundary)"
    }

    /// The visible prefix is shared; item kind and UUID stay inside the
    /// invisible marker written to each native item.
    static var copyText: String { readablePrefix }

    static func copyText(for kind: Kind) -> String {
        _ = kind
        return copyText
    }

    static func containsMarker(_ note: String) -> Bool {
        ownership(in: note) != nil
    }

    /// Recovers the identity that survives an app reinstall. Native IDs are
    /// device-local; this payload is deliberately independent of them.
    static func ownership(in note: String) -> Ownership? {
        guard note.contains(readablePrefix) else { return nil }

        for segment in note.components(separatedBy: boundary) {
            guard !segment.isEmpty,
                  segment.unicodeScalars.allSatisfy({ isEncodedScalar($0) }),
                  let decoded = decode(segment) else {
                continue
            }
            let parts = decoded.split(separator: "|", maxSplits: 1)
            guard parts.count == 2,
                  let kind = Kind(rawValue: String(parts[0])),
                  let id = UUID(uuidString: String(parts[1])) else {
                continue
            }
            return Ownership(kind: kind, id: id)
        }
        return nil
    }

    private static func encode(_ value: String) -> String {
        value.unicodeScalars.compactMap { scalar in
            UnicodeScalar(tagBase + scalar.value).map(String.init)
        }.joined()
    }

    private static func decode(_ value: String) -> String? {
        String(String.UnicodeScalarView(value.unicodeScalars.compactMap { scalar in
            guard isEncodedScalar(scalar) else { return nil }
            return UnicodeScalar(scalar.value - tagBase)
        }))
    }

    private static func isEncodedScalar(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= tagBase && scalar.value <= 0xE007F
    }
}
