import Foundation
import Metal
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Reads a sentence into a draft using a model on the device.
///
/// The interface exists so the app has ONE question — "what model reads a
/// sentence" — and three answers: Apple's Foundation Models, a downloaded local
/// model, and the deterministic parser alone. Only the middle one is this type.
///
/// Two properties matter more than the inference:
///
///  * **A model is loaded once and kept.** Loading a 0.5B from a 290 MB directory
///    takes seconds, and a person tapping "Satz lesen" expects a result, not a
///    progress bar. The container is held for the process's life and reloaded only
///    when the weights on disk change.
///  * **Nothing here decides whether the answer is any good.** That is
///    `DraftExtraction`'s job, and keeping the two apart is what makes the parser
///    testable without a model — which is the only reason the risk in this feature
///    is knowable at all.
@MainActor
@Observable
final class LocalModelSentenceReader {

    private let service: LocalModelService
    private var container: ModelContainer?
    private var loadedPath: String?

    enum Outcome: Equatable {
        case draft(CreateItemDraft)
        /// The model answered something unusable. Not an error to apologise for —
        /// the sheet already offers the deterministic reading, which is always
        /// available.
        case unreadable
        case failed(String)
    }

    init(service: LocalModelService) {
        self.service = service
    }

    var isLoaded: Bool { container != nil }

    /// Frees the model. Worth doing when the sheet closes: a 0.5B holds hundreds of
    /// megabytes of weight cache, and holding it between sheets makes the rest of
    /// the app feel heavier than it is.
    func release() {
        container = nil
        loadedPath = nil
    }

    /// Whether MLX can be asked to run at all.
    ///
    /// This is not a capability check in the usual sense. MLX creates its Metal
    /// device lazily and, if it cannot, calls `abort()` from C++ — a hard process
    /// kill that no Swift `try`/`catch` can intercept. The first end-to-end run
    /// proved it: tapping "Satz lesen" on a machine with no usable GPU took the
    /// app down instead of falling back to the deterministic reading.
    ///
    /// So the precondition is checked here, before MLX is called at all. Where
    /// Metal is unavailable the answer is the deterministic reading, which is
    /// always available and always works.
    static var canRunMLX: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    func read(_ sentence: String, locale: Locale = .current,
              calendar: Calendar = .current, now: Date = .now) async -> Outcome {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Task.isCancelled else { return .unreadable }
        let fallback = CreateItemDraft.fallback(from: trimmed, locale: locale, calendar: calendar, now: now)
        if fallback.validationMessage != nil { return .draft(fallback) }

        let model = service.usableModel
        let directory = service.directory(for: model)

        guard Self.canRunMLX else {
            return .failed(String(localized: "Auf diesem Gerät ist keine GPU für das Modell verfügbar."))
        }
        do {
            let loaded = try await load(of: model, at: directory)
            guard !Task.isCancelled else { return .unreadable }
            let parameters = GenerateParameters(
                // A small model needs a hard ceiling: asked for a JSON object it
                // will happily keep talking, and the extra prose is exactly what
                // the parser has to strip. This task has a known short answer.
                maxTokens: 160,
                // Greedy. This is extraction, not writing: the same sentence should
                // read the same way twice, and a habit scheduled for a time
                // somebody never said is worse than a flat-sounding one.
                temperature: 0.0)
            let input = try await loaded.prepare(input: UserInput(prompt: .chat([
                .init(role: .system, content: DraftExtraction.systemPrompt),
                .init(role: .user, content: DraftExtraction.userPrompt(for: trimmed, locale: locale,
                                                                     calendar: calendar, now: now)),
            ])))
            guard !Task.isCancelled else { return .unreadable }
            let stream = try await loaded.generate(input: input, parameters: parameters)
            var text = ""
            for await item in stream {
                guard !Task.isCancelled else { return .unreadable }
                if case .chunk(let piece) = item { text += piece }
            }
            guard !Task.isCancelled,
                  let outcome = DraftExtraction.parse(text, sentence: trimmed, locale: locale,
                                                      calendar: calendar, now: now) else {
                return .unreadable
            }
            return .draft(outcome.draft)
        } catch {
            guard !Task.isCancelled else { return .unreadable }
            // A model that cannot be loaded must not take the feature down with
            // it: the sheet falls back to the deterministic reading, which needs
            // no model at all.
            return .failed(Self.describe(error))
        }
    }

    // MARK: - Loading

    private func load(of model: LocalModelDescriptor,
                      at directory: URL) async throws -> ModelContainer {
        // Same weights, already in memory: reuse them. A second tap on "Satz lesen"
        // must not pay for loading again.
        if let container, loadedPath == directory.path { return container }
        release()

        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: directory, using: LocalTokenizerLoader())
        container = loaded
        loadedPath = directory.path
        return loaded
    }

    // MARK: - Diagnostics

    private static func describe(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("memory") { return String(localized: "Zu wenig Arbeitsspeicher für das Modell.") }
        if text.contains("missing") || text.contains("no such file") {
            return String(localized: "Die Modelldateien fehlen.")
        }
        return String(localized: "Das Modell konnte nicht geladen werden.")
    }
}

/// Adapts swift-transformers' tokenizer to the one MLX asks for.
///
/// The package offers this as a macro, `#huggingFaceTokenizerLoader()`. It is
/// hand-written here on purpose: a package macro has to be trusted before the
/// compiler will use it, and from a command line that means a validation flag in
/// the build and the release pipeline. The adaptation is a dozen forwarding
/// methods, and not having to ask for a build-wide exception to run a model is
/// worth more than the lines.
///
/// The chat template is the one method that is not a straight forward: MLX's
/// signature takes untyped dictionaries and the upstream one takes typed messages.
struct LocalTokenizerLoader: TokenizerLoader {

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }

    /// Named for MLX's protocol, not Tokenizers': both modules export a
    /// `Tokenizer` and the unqualified name is ambiguous once both are imported.
    private struct TokenizerBridge: MLXLMCommon.Tokenizer {
        let upstream: any Tokenizers.Tokenizer

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        /// A straight pass-through. Both protocols describe a chat entry as
        /// `[String: any Sendable]`, so there is nothing to convert — which is
        /// most of why this bridge is short enough to prefer over a macro.
        func applyChatTemplate(messages: [[String: any Sendable]],
                               tools: [[String: any Sendable]]?,
                               additionalContext: [String: any Sendable]?) throws -> [Int] {
            try upstream.applyChatTemplate(messages: messages, tools: tools,
                                           additionalContext: additionalContext)
        }
    }
}
