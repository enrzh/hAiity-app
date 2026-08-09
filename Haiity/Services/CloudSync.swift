import CloudKit
import Foundation
import Observation

/// Sync über iCloud (CloudKit, PRIVATE Datenbank des Nutzers). Es gibt keinen
/// hAiity-Server und kein Konto: die Daten liegen weiterhin lokal in
/// `data.json` im App-Group-Container — iCloud ist der SPIEGEL davon, ein
/// einziger Datensatz in der privaten Datenbank der Apple-ID.
///
/// Nichts davon muss eingerichtet werden. Ist das Gerät bei iCloud angemeldet,
/// läuft es; ist es das nicht, funktioniert die App vollständig weiter und die
/// Statuszeile sagt genau das.

// MARK: – Seam

/// Die ZWEI CloudKit-Operationen, die hAiity überhaupt benutzt. Als Protokoll,
/// damit Tests gegen einen Fake laufen und kein Test echtes CloudKit anfasst —
/// derselbe Schnitt, den vorher `HTTPTransport`/`TokenVault` hatten.
protocol CloudRecordStore: Sendable {
    /// Wirft `CKError.unknownItem`, wenn es den Datensatz noch nicht gibt —
    /// genau wie `CKDatabase.record(for:)`, damit der Fake nicht freundlicher
    /// ist als die Wirklichkeit.
    func record(for id: CKRecord.ID) async throws -> CKRecord
    func save(_ record: CKRecord) async throws -> CKRecord
}

/// Die private Datenbank des iCloud-Containers.
struct PrivateCloudDatabase: CloudRecordStore {
    let containerID: String

    init(containerID: String = CloudSync.containerID) {
        self.containerID = containerID
    }

    /// BEWUSST erst im Aufruf gebaut, nie im Initialisierer: `CKContainer` in
    /// einem Prozess OHNE iCloud-Entitlement (jeder unsignierte Test-Host)
    /// wirft eine ObjC-Exception, die Swift nicht fangen kann. So entsteht der
    /// Container nur dort, wo wirklich synchronisiert wird — in der App, und
    /// dort auch nur bei angemeldeter Apple-ID.
    private var database: CKDatabase {
        CKContainer(identifier: containerID).privateCloudDatabase
    }

    func record(for id: CKRecord.ID) async throws -> CKRecord {
        try await database.record(for: id)
    }

    func save(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }
}

// MARK: – Fehler

enum CloudSyncError: LocalizedError, Equatable {
    /// Keine Apple-ID auf dem Gerät (oder iCloud Drive aus).
    case notSignedIn
    /// Vorübergehend: offline, Dienst überlastet, Rate-Limit. Kein Datenverlust,
    /// der nächste Versuch räumt es auf.
    case unavailable(String)
    /// In iCloud liegt etwas, das dieser Build nicht lesen kann (neuere
    /// Datenversion oder beschädigt). Wird GEMELDET statt überschrieben —
    /// dieselbe Regel wie beim Lesen von data.json.
    case unreadableRemote
    /// Nach `limit` Versuchen war der Server immer noch neuer.
    case conflictUnresolved(Int)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Nicht bei iCloud angemeldet — die Daten bleiben auf diesem Gerät.")
        case .unavailable(let m):
            return String(localized: "iCloud gerade nicht erreichbar (\(m)) — wird später nachgeholt.")
        case .unreadableRemote:
            return String(localized: "Die Daten in iCloud stammen aus einer neueren Version und werden nicht überschrieben.")
        case .conflictUnresolved(let n):
            return String(localized: "iCloud-Konflikt nach \(n) Versuchen nicht aufgelöst.")
        case .failed(let m):
            return String(localized: "iCloud-Fehler: \(m)")
        }
    }

    /// Ist das ein „gleich nochmal“-Fehler oder ein echtes Problem? Die
    /// Statuszeile unterscheidet danach — offline ist kein Fehler, sondern ein
    /// Zustand.
    var isTemporary: Bool {
        switch self {
        case .unavailable: return true
        default: return false
        }
    }

    /// CloudKit-Fehler auf die vier Fälle abbilden, die die Oberfläche
    /// tatsächlich unterscheiden kann.
    static func map(_ error: Error) -> CloudSyncError {
        if let already = error as? CloudSyncError { return already }
        guard let ck = error as? CKError else {
            return .unavailable((error as NSError).localizedDescription)
        }
        switch ck.code {
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .operationCancelled:
            return .unavailable(ck.localizedDescription)
        case .quotaExceeded:
            return .failed(String(localized: "iCloud-Speicher voll."))
        default:
            return .failed(ck.localizedDescription)
        }
    }
}

// MARK: – Sync

/// Ein Datensatz, ein Ort, ein Merge.
///
/// **Form.** Datensatztyp `HabitData`, feste Kennung `habit-data` in der
/// Standardzone der PRIVATEN Datenbank. Die Nutzlast ist EXAKT dieselbe
/// JSON-Datei, die auch auf der Platte liegt (`HabitStore.exportJSON()`), als
/// `CKAsset` — nicht als `Data`-Feld.
///
/// **Warum Asset.** Ein CKRecord darf ohne Assets 1 MB groß sein. Gerechnet:
/// ein Log-Eintrag im hübsch formatierten JSON kostet gut 25 Byte, ein Nutzer
/// mit 20 Habits über fünf Jahre kommt damit auf ~36 500 Einträge ≈ 900 kB —
/// also genau in die Größenordnung der Grenze, und darüber würde CloudKit
/// jeden Schreibvorgang ablehnen. Ein Asset hat diese Grenze nicht. Die
/// Alternative (klein: Data-Feld, groß: Asset) hätte ZWEI Pfade, von denen
/// der seltene der ungetestete wäre — genau der, der beim langjährigen Nutzer
/// zuschlägt. Deshalb: immer Asset.
///
/// **Konflikt.** Genau EIN Merge existiert in dieser App:
/// `HabitStore.merge(remote:)`. Bei `serverRecordChanged` nimmt `push` den
/// Serverdatensatz aus dem Fehler, dekodiert ihn, reicht ihn dem Aufrufer zum
/// Mergen und schreibt das Ergebnis auf den SERVER-Datensatz zurück (der trägt
/// das aktuelle Änderungs-Tag). Begrenzt auf `retryLimit` Runden, danach wird
/// der Fehler gemeldet statt endlos zu drehen.
///
/// **Kein Abonnement.** Bewusst KEINE `CKDatabaseSubscription` mit stillem
/// Push: das kostet die Berechtigung `aps-environment`, den Hintergrundmodus
/// „Remote notifications“ und einen AppDelegate — und brächte nur den Fall
/// „das andere Gerät hakt etwas ab, WÄHREND diese App offen im Vordergrund
/// liegt“. Ein Habit-Tracker wird ein paar Mal am Tag geöffnet; der Abgleich
/// beim Aktivwerden deckt das ab. Lieber gar kein Abonnement als eines, das
/// halb verdrahtet ist.
actor CloudSync {
    static let containerID = "iCloud.com.aiity.haiity"
    static let recordType = "HabitData"
    static let recordName = "habit-data"
    static let payloadKey = "payload"
    static let updatedAtKey = "updatedAt"
    static let schemaKey = "schema"
    /// Wie oft bei `serverRecordChanged` gemergt und neu geschrieben wird.
    static let retryLimit = 3

    static var recordID: CKRecord.ID { CKRecord.ID(recordName: recordName) }

    private let database: CloudRecordStore
    /// Zuletzt gesehener Serverdatensatz — gebraucht wird davon nur das
    /// Änderungs-Tag, damit ein Schreibvorgang nicht blind den fremden Stand
    /// überschreibt. Die Nutzlast darin wird nie wieder gelesen.
    private var known: CKRecord?

    init(database: CloudRecordStore = PrivateCloudDatabase()) {
        self.database = database
    }

    /// Holt den Stand aus iCloud. `nil` = es gibt dort noch nichts (erstes
    /// Gerät). Unlesbares wirft — siehe `CloudSyncError.unreadableRemote`.
    func pull() async throws -> HabitData? {
        do {
            let record = try await database.record(for: Self.recordID)
            known = record
            return try Self.decode(record)
        } catch let error as CKError where error.code == .unknownItem {
            known = nil
            return nil
        } catch {
            throw CloudSyncError.map(error)
        }
    }

    /// Schreibt die Nutzlast. Bei `serverRecordChanged`: Serverstand nehmen,
    /// `mergeAndRetry` (= `HabitStore.merge`) laufen lassen, das Ergebnis
    /// erneut schreiben — bis zu `retryLimit` Runden.
    func push(_ payload: Data, mergeAndRetry: @Sendable (HabitData?) async -> Data) async throws {
        var body = payload
        for attempt in 1...Self.retryLimit {
            do {
                let record = try prepared(body)
                known = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let server = error.serverRecord else {
                    throw CloudSyncError.failed(error.localizedDescription)
                }
                known = server
                guard attempt < Self.retryLimit else { break }
                // Ein unlesbarer Serverstand darf NICHT als „nichts da“ in den
                // Merge laufen — sonst überschreibt ein alter Build die Daten
                // eines neueren. Lieber ehrlich abbrechen.
                let remote = try Self.decode(server)
                body = await mergeAndRetry(remote)
            } catch {
                throw CloudSyncError.map(error)
            }
        }
        throw CloudSyncError.conflictUnresolved(Self.retryLimit)
    }

    /// Der zu schreibende Datensatz: entweder der bekannte Serverdatensatz
    /// (mit gültigem Änderungs-Tag) oder ein frischer.
    private func prepared(_ payload: Data) throws -> CKRecord {
        let record = known ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID)
        let stamp: Double = Date().timeIntervalSince1970
        let schema: Int = HabitData.currentVersion
        record[Self.payloadKey] = try Self.asset(for: payload)
        record[Self.updatedAtKey] = stamp
        record[Self.schemaKey] = schema
        return record
    }

    /// Nutzlast als Asset. Die temporäre Datei muss den Schreibvorgang
    /// überleben (CloudKit liest sie beim Hochladen), deshalb liegt sie in
    /// einem eigenen Ordner und wird beim nächsten Lauf mit aufgeräumt.
    private static func asset(for payload: Data) throws -> CKAsset {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haiity-cloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Alte Nutzlasten früherer Schreibvorgänge entsorgen — sie sind hoch-
        // geladen oder verloren, in beiden Fällen wertlos.
        if let old = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in old { try? FileManager.default.removeItem(at: url) }
        }
        let url = dir.appendingPathComponent("\(UUID().uuidString).json")
        do { try payload.write(to: url, options: .atomic) }
        catch { throw CloudSyncError.failed(error.localizedDescription) }
        return CKAsset(fileURL: url)
    }

    /// Datensatz -> `HabitData`. Leerer Datensatz (kein Asset) = noch nichts
    /// geschrieben -> nil. Vorhandene, aber unlesbare Nutzlast -> Fehler.
    static func decode(_ record: CKRecord) throws -> HabitData? {
        guard let asset = record[payloadKey] as? CKAsset, let url = asset.fileURL else { return nil }
        guard let raw = try? Data(contentsOf: url) else { throw CloudSyncError.unreadableRemote }
        guard let data = try? JSONDecoder().decode(HabitData.self, from: raw) else {
            throw CloudSyncError.unreadableRemote
        }
        return data
    }
}

// MARK: – Entprellung

/// Sammelt schnelle Folgeänderungen zu EINEM Schreibvorgang zusammen: jedes
/// `schedule` verwirft den noch wartenden Lauf. Fünf Häkchen hintereinander
/// sind damit ein Upload, nicht fünf.
///
/// Ersetzt das frühere `schedulePush` in `ContentView` — als eigener Typ, weil
/// eine View nicht testbar ist und genau diese Zusammenfassung der Punkt ist.
actor PushDebouncer {
    private var pending: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration = .seconds(1.5)) {
        self.delay = delay
    }

    func schedule(_ work: @escaping @Sendable () async -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            // `Task.sleep` bricht bei Cancellation ab — der verworfene Lauf
            // kommt also gar nicht erst bis zur Arbeit.
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await work()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    /// Wartet, bis der aktuell wartende Lauf durch ist (Tests; und beim
    /// Beenden, damit ein Häkchen kurz vor dem Schließen noch hochgeht).
    func drain() async {
        await pending?.value
    }
}

// MARK: – Status

/// Was die App über iCloud SAGEN darf. Vier Zustände, alle ehrlich:
/// angemeldet und läuft, nicht angemeldet, vorübergehend nicht erreichbar,
/// echter Fehler mit Meldung.
enum CloudState: Equatable {
    /// iCloud steht bereit; `Date` = letzter erfolgreicher Abgleich.
    case active(Date?)
    case signedOut
    /// Offline / iCloud gerade nicht erreichbar — mit Grund.
    case waiting(String)
    case failed(String)

    var title: String {
        switch self {
        case .active: return String(localized: "iCloud aktiv")
        case .signedOut: return String(localized: "Nur auf diesem Gerät")
        case .waiting: return String(localized: "Warten auf iCloud")
        case .failed: return String(localized: "iCloud-Problem")
        }
    }

    var detail: String {
        switch self {
        case .active(let date):
            guard let date else {
                return String(localized: "Deine Habits spiegeln sich über deine Apple-ID. Kein Konto, keine Anmeldung in der App.")
            }
            let time = date.formatted(date: .omitted, time: .shortened)
            return String(localized: "Zuletzt abgeglichen um \(time). Kein Konto, keine Anmeldung in der App.")
        case .signedOut:
            return String(localized: "Kein iCloud-Konto auf diesem Gerät. Die App funktioniert vollständig, deine Daten bleiben hier — melde dich in den iOS-Einstellungen bei iCloud an, dann spiegelt hAiity sie.")
        case .waiting(let reason):
            return String(localized: "\(reason) Deine Daten sind auf diesem Gerät gespeichert und gehen nicht verloren.")
        case .failed(let message):
            return String(localized: "\(message) Deine Daten sind auf diesem Gerät gespeichert und gehen nicht verloren.")
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "checkmark.icloud"
        case .signedOut: return "icloud.slash"
        case .waiting: return "arrow.triangle.2.circlepath.icloud"
        case .failed: return "exclamationmark.icloud"
        }
    }
}

/// Hält den Zustand aktuell — auch dann, wenn sich AM GERÄT etwas ändert
/// (Abmelden, Anmelden), ohne dass die App etwas synchronisiert hätte.
@MainActor
@Observable
final class CloudSyncStatus {
    private(set) var state: CloudState

    /// Anmeldeprüfung als Seam. Produktion liest `ubiquityIdentityToken`;
    /// Tests reichen einfach einen Wert herein.
    ///
    /// BEWUSST NICHT `CKContainer.accountStatus`: das wirft in jedem Prozess
    /// ohne iCloud-Entitlement (also in jedem unsignierten Test-Host) eine
    /// ObjC-Exception, die Swift nicht fangen kann. Der Token ist überall
    /// gefahrlos lesbar und beantwortet dieselbe Frage.
    @ObservationIgnored private let accountCheck: @Sendable () -> Bool
    /// Die Beobachter liegen in einer eigenen Klasse, damit sie beim Abbau
    /// aufgeräumt werden, ohne dass `deinit` auf MainActor-isolierte
    /// Eigenschaften zugreifen muss.
    @ObservationIgnored private let observers = ObserverBag()
    @ObservationIgnored private var lastSuccess: Date?

    init(accountCheck: @escaping @Sendable () -> Bool = { FileManager.default.ubiquityIdentityToken != nil },
         observeAccountChanges: Bool = true) {
        self.accountCheck = accountCheck
        self.state = accountCheck() ? .active(nil) : .signedOut
        if observeAccountChanges { observe() }
    }

    var isSignedIn: Bool { accountCheck() }

    /// Beide Signale: Foundations Token-Wechsel (das, was hier gelesen wird)
    /// und CloudKits Kontowechsel. Eines von beiden reicht, doppelt schadet
    /// nicht — die Prüfung ist ein Feldzugriff.
    private func observe() {
        for name in [Notification.Name.NSUbiquityIdentityDidChange, .CKAccountChanged] {
            observers.add(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    /// Kontostand neu bestimmen. Ein bestehender ECHTER Fehler bleibt stehen,
    /// solange das Konto da ist — er ist eine Aussage über den letzten
    /// Schreibvorgang, nicht über die Anmeldung.
    func refresh() {
        guard accountCheck() else { state = .signedOut; return }
        if case .signedOut = state { state = .active(lastSuccess) }
    }

    func noteSuccess(at date: Date = .now) {
        lastSuccess = date
        state = accountCheck() ? .active(date) : .signedOut
    }

    func noteFailure(_ error: Error) {
        guard accountCheck() else { state = .signedOut; return }
        let mapped = CloudSyncError.map(error)
        if case .notSignedIn = mapped { state = .signedOut; return }
        let message = mapped.errorDescription ?? String(localized: "Unbekannter iCloud-Fehler.")
        state = mapped.isTemporary ? .waiting(message) : .failed(message)
    }
}

/// Nimmt Beobachter-Handles auf und meldet sie beim Abbau wieder ab. Eigene
/// Klasse, weil `deinit` einer MainActor-isolierten Klasse deren Eigenschaften
/// nicht anfassen darf.
private final class ObserverBag {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) { tokens.append(token) }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
