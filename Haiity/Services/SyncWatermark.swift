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

    struct Ownership: Equatable, Hashable, Sendable {
        let kind: Kind
        let id: UUID
    }

    struct NativeItemSelection: Equatable, Sendable {
        let retainedID: String?
        let duplicateIDs: Set<String>
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

    /// Keep a previously linked item when it still exists. Otherwise use a
    /// stable ordering so repeated reconciliation cannot create a new winner.
    static func selectCanonicalItem(
        candidates: [(id: String, sortKey: String)],
        preferredID: String?) -> NativeItemSelection {
        var unique: [String: String] = [:]
        for candidate in candidates where unique[candidate.id] == nil {
            unique[candidate.id] = candidate.sortKey
        }
        let ordered = unique.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
        }
        let retainedID = preferredID.flatMap { unique[$0] != nil ? $0 : nil }
            ?? ordered.first?.key
        let duplicateIDs = Set(unique.keys).subtracting(retainedID.map { [$0] } ?? [])
        return NativeItemSelection(retainedID: retainedID, duplicateIDs: duplicateIDs)
    }

    /// Recognizes current invisible ownership metadata and the exact legacy
    /// note written by builds before per-item markers existed. A bare product
    /// name is the only legacy form accepted; arbitrary notes that merely
    /// mention hAiity remain untouched.
    static func containsMarker(_ note: String) -> Bool {
        ownership(in: note) != nil
            || note.trimmingCharacters(in: .whitespacesAndNewlines) == readablePrefix
    }

    /// Recovers the identity that survives an app reinstall. Native IDs are
    /// device-local; this payload is deliberately independent of them.
    static func ownership(in note: String) -> Ownership? {
        let lines = note.components(separatedBy: "\n")
        for index in lines.indices where lines[index] == readablePrefix {
            guard lines.indices.contains(index + 1) else { continue }
            let markerLine = lines[index + 1]
            guard markerLine.hasPrefix(boundary), markerLine.hasSuffix(boundary) else {
                continue
            }
            let segment = String(markerLine.dropFirst(boundary.count).dropLast(boundary.count))
            guard !segment.isEmpty,
                  segment.unicodeScalars.allSatisfy({ isEncodedScalar($0) }),
                  let decoded = decode(segment) else { continue }
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
