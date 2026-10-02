import Foundation

/// What a downloadable model is FOR, which is not the same as how big it is.
///
/// The catalogue spans three genuinely different jobs, and a person choosing
/// between them is choosing a trade-off, not a quality ladder:
///
///  * `.processing` — one small model that only ever answers "turn this German
///    sentence into a name, a time and a repeat". It is the fastest and the
///    cheapest, and it is the one this app is actually shaped around.
///  * `.language` — a model tuned for one language, for somebody who writes in
///    one language and wants the parse to be right in it.
///  * `.multilingual` — a model for several declared languages. Larger,
///    slower, and the only choice that needs no decision.
enum LocalModelScope: Equatable, Hashable, Sendable {

    /// Dedicated to the extraction task itself.
    case processing
    /// Tuned for one language, identified by its code.
    case language(String)
    /// Offered for the model catalogue's declared language subset.
    case multilingual

    var isProcessing: Bool { self == .processing }
}

/// One downloadable model, described well enough to choose from.
///
/// Sizes are not guesses. Each figure was read off the Hugging Face repository
/// (`?blobs=true`), and `LocalModelCatalogueTests` fails if an entry's declared
/// size does not match the sum of the files it lists — a model that doubles in
/// size between versions must not quietly fill somebody's storage.
struct LocalModelDescriptor: Identifiable, Equatable, Hashable, Sendable {

    /// Stable across releases: it is the storage key and the preference value,
    /// so it must not carry a size or a version in its name.
    let id: String

    /// What it is called in the picker.
    let displayName: String

    /// One line on why somebody would pick this one over another.
    let summary: String

    let scope: LocalModelScope

    /// The Hugging Face repository the weights come from.
    let repository: String

    /// The files that have to be present for the model to load. Anything not
    /// listed here is documentation and is not fetched.
    let files: [String]

    /// Bytes, as reported by the repository.
    let byteCount: Int64

    /// The languages this model is offered for, in the app's own order.
    var languageCodes: [String] {
        switch scope {
        case .processing: LanguageCatalog.modelLanguages
        case .language(let code): [code]
        case .multilingual: LanguageCatalog.modelLanguages
        }
    }

    /// A model that is not downloadable is worse than one that is absent, so the
    /// catalogue keeps the choice to the smallest honest set.
    var isFreeTierEligible: Bool { scope == .processing }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// UI localizations and model language claims are separate contracts.
enum LanguageCatalog {

    static let supported = ["de", "en", "es", "fr", "pt", "it", "zh", "ja", "ru", "ar", "hi", "bn", "ur", "id", "tr", "vi", "ko"]
    static let modelLanguages = ["de", "en", "ru", "zh", "vi", "tr", "es", "fr", "it", "ja", "ko", "pt"]

    static func displayName(for code: String) -> String {
        Locale(identifier: Locale(identifier: code).identifier)
            .localizedString(forIdentifier: code) ?? code
    }
}

/// The models a person can choose from.
///
/// This is data, deliberately. It exists before any inference does, so the
/// choice can be designed, reviewed and tested while the runtime is still being
/// built — and so the picker has something real in it rather than a placeholder.
enum LocalModelCatalogue {

    /// Helper for an MLX community repository: the file set is the same shape
    /// for every instruct conversion, so it is written once.
    private static func mlxInstruct(_ id: String,
                                    _ name: String,
                                    _ summary: String,
                                    scope: LocalModelScope,
                                    repository: String,
                                    weightBytes: Int64,
                                    extraBytes: Int64) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: id,
            displayName: name,
            summary: summary,
            scope: scope,
            repository: repository,
            files: ["config.json", "model.safetensors", "model.safetensors.index.json",
                    "tokenizer.json", "tokenizer_config.json", "vocab.json",
                    "merges.txt", "added_tokens.json", "special_tokens_map.json"],
            byteCount: weightBytes + extraBytes)
    }

    /// Every model offered, smallest first. Smallest first because the sheet
    /// that lists them opens at the top, and the top should be the one that is
    /// quickest to download and quickest to run.
    static let all: [LocalModelDescriptor] = [
        mlxInstruct(
            "qwen25-0.5b",
            String(localized: "Qwen2.5 0.5B"),
            String(localized: "Klein und schnell. Für den Satz reicht er; bei ungewöhnlichen Formulierungen ratet er eher."),
            scope: .processing,
            repository: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            weightBytes: 278_100_000, extraBytes: 11_500_000),

        mlxInstruct(
            "qwen3-0.6b",
            String(localized: "Qwen3 0.6B"),
            String(localized: "Etwas klüger als der 0.5B, fast gleich groß. Gute Wahl, wenn du viele Gewohnheiten anlegst."),
            scope: .processing,
            repository: "mlx-community/Qwen3-0.6B-4bit",
            weightBytes: 339_000_000, extraBytes: 11_500_000),

        mlxInstruct(
            "qwen25-1.5b",
            String(localized: "Qwen2.5 1.5B"),
            String(localized: "Deutlich besser bei langen Sätzen und mehreren Angaben auf einmal. Viermal so groß wie der 0.5B."),
            scope: .language("de"),
            repository: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            weightBytes: 868_600_000, extraBytes: 11_600_000),

        mlxInstruct(
            "gemma2-2b",
            String(localized: "Gemma 2 2B"),
            String(localized: "Mehrsprachiges Modell mit höherem Speicherbedarf."),
            scope: .multilingual,
            repository: "mlx-community/gemma-2-2b-it-4bit",
            weightBytes: 1_481_000_000, extraBytes: 11_500_000),

        mlxInstruct(
            "phi35-mini",
            String(localized: "Phi 3.5 Mini"),
            String(localized: "Das größte Angebot. Am gründlichsten und am langsamsten, mit dem höchsten Speicherbedarf."),
            scope: .multilingual,
            repository: "mlx-community/Phi-3.5-mini-instruct-4bit",
            weightBytes: 2_140_000_000, extraBytes: 11_500_000),
    ]

    /// The model used until somebody picks another one. The smallest, because the
    /// first thing a new user does is read one sentence, and a 300 MB download
    /// for that is a bad first impression.
    static let `default`: LocalModelDescriptor = all[0]

    static func descriptor(for id: String) -> LocalModelDescriptor? {
        all.first { $0.id == id }
    }

    static var totalDownloadSize: Int64 {
        all.reduce(0) { $0 + $1.byteCount }
    }
}
