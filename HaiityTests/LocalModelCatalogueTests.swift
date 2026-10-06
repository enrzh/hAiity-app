import XCTest
@testable import Haiity

/// The model catalogue and the state machine around downloading it.
///
/// The catalogue is data, which means it can be right or wrong in a way that
/// only shows up on a person's phone: a repository that 404s, a size that has
/// doubled since it was written down, a model offered for a language the app does
/// not ship. All three are cheap to catch here and expensive to hear about later.
final class LocalModelCatalogueTests: XCTestCase {

    // MARK: - The catalogue itself

    func testEveryModelIsAddressableAndUniquelyNamed() {
        let ids = LocalModelCatalogue.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two models share an id, so one shadows the other")
        for model in LocalModelCatalogue.all {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertFalse(model.displayName.isEmpty, "\(model.id) needs a name to show")
            XCTAssertFalse(model.summary.isEmpty,
                           "\(model.id) needs a line saying why to pick it")
        }
    }

    /// The id is the storage key and the preference value, so it has to survive a
    /// version bump.
    ///
    /// A model family name legitimately contains its parameter count — there is
    /// no way to say "Qwen 0.5B" without the 0.5B. What must not appear is the
    /// download SIZE, because that drifts with every re-quantisation and would
    /// strand every copy already on somebody's phone under an id that no longer
    /// matches the weights.
    func testIDsCarryNoByteCountOrReleaseSuffix() {
        for model in LocalModelCatalogue.all {
            let id = model.id.lowercased()
            XCTAssertFalse(id.contains("mb"), "\(model.id) carries a download size in its id")
            XCTAssertFalse(id.contains("gb"), "\(model.id) carries a download size in its id")
            XCTAssertFalse(id.contains("-v2"), "\(model.id) looks release-versioned")
            XCTAssertFalse(id.contains("instruct-"), "\(model.id) looks release-versioned")
        }
    }

    /// Two entries pointing at one repository would offer the same weights twice
    /// and, if both were downloaded, occupy storage twice.
    func testNoTwoModelsShareARepository() {
        let repositories = LocalModelCatalogue.all.map(\.repository)
        XCTAssertEqual(Set(repositories).count, repositories.count,
                       "two catalogue entries would download the same weights twice")
    }

    /// And a model that claims a language the app does not ship is offering
    /// something it will never be asked to do.
    func testNoModelClaimsALanguageTheAppDoesNotShip() {
        for model in LocalModelCatalogue.all {
            for code in model.languageCodes {
                XCTAssertTrue(LanguageCatalog.supported.contains(code),
                              "\(model.id) claims \(code), which the app does not ship")
            }
        }
    }

    /// A model without weights is not a model. This is the check that keeps a
    /// typo'd repository out of the picker.
    func testEveryModelDeclaresWeightsAndAConfig() {
        for model in LocalModelCatalogue.all {
            XCTAssertTrue(model.files.contains("model.safetensors"),
                          "\(model.id) lists no weights")
            XCTAssertTrue(model.files.contains("config.json"),
                          "\(model.id) has no architecture config, so it cannot be built")
            XCTAssertTrue(model.files.contains("tokenizer.json"),
                          "\(model.id) has no tokenizer, so it cannot read a sentence")
        }
    }

    /// Sizes were read off Hugging Face. If one drifts, the number in the picker
    /// is a lie about how much of somebody's storage a model will take, which is
    /// the one thing a person cannot check for themselves beforehand.
    ///
    /// The recorded figures live next to this test so a version bump is a
    /// deliberate edit rather than a silent drift.
    func testRecordedSizesMatchWhatTheRepositoriesReport() async throws {
        // Recorded 2026-09-29 from `huggingface.co/api/models/<repo>?blobs=true`.
        let recorded: [String: Int64] = [
            "mlx-community/Qwen2.5-0.5B-Instruct-4bit": 289_600_000,
            "mlx-community/Qwen3-0.6B-4bit": 350_500_000,
            "mlx-community/Qwen2.5-1.5B-Instruct-4bit": 880_200_000,
            "mlx-community/gemma-2-2b-it-4bit": 1_492_500_000,
            "mlx-community/Phi-3.5-mini-instruct-4bit": 2_151_500_000,
        ]

        for model in LocalModelCatalogue.all {
            let expected = try XCTUnwrap(recorded[model.repository],
                                         "\(model.id) has no recorded size to check against")
            // A megabyte of slack, because a repository can gain a README.
            XCTAssertLessThanOrEqual(abs(model.byteCount - expected), 1_100_000,
                                     "\(model.id) no longer matches its repository: declared "
                                     + "\(model.formattedSize), recorded \(expected)")
        }
    }

    func testUILanguagesMatchTheBuiltAppAndStringCatalog() throws {
        func normalized(_ code: String) -> String {
            Locale(identifier: code).language.languageCode?.identifier ?? code
        }
        let shipped = Set(Bundle.main.localizations.filter { $0 != "Base" }.map(normalized))
        XCTAssertEqual(Set(LanguageCatalog.supported), shipped)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Haiity/Localizable.xcstrings")
        let url = FileManager.default.fileExists(atPath: source.path) ? source
            : try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Localizable", withExtension: "txt"))
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        for key in ["Habits", "Statistik", "Mehr", "Suchen", "Sichern", "Abbrechen"] {
            let localized = try XCTUnwrap(strings[key]?["localizations"] as? [String: [String: Any]])
            XCTAssertEqual(Set(localized.keys.map(normalized)).union(["de"]), shipped, key)
            for (language, item) in localized {
                let unit = try XCTUnwrap(item["stringUnit"] as? [String: String])
                XCTAssertFalse(unit["value", default: ""].isEmpty, "\(key)/\(language)")
            }
        }
    }

    func testMultilingualModelsDeclareALanguageSubsetWithoutClaimingAllUILocales() {
        let multilingual = LocalModelCatalogue.all.filter { $0.scope == .multilingual }
        XCTAssertFalse(multilingual.isEmpty)
        for model in multilingual {
            XCTAssertGreaterThan(model.languageCodes.count, 1)
            XCTAssertTrue(Set(model.languageCodes).isSubset(of: Set(LanguageCatalog.supported)))
            XCTAssertFalse(model.languageCodes.contains("ar"), "undeclared support must not be inferred from UI translations")
        }
    }

    /// The default has to be the one that is quickest to fetch and run, or the
    /// first thing a new user does costs them a gigabyte.
    func testTheDefaultIsTheSmallestModel() {
        let smallest = LocalModelCatalogue.all.min { $0.byteCount < $1.byteCount }
        XCTAssertEqual(LocalModelCatalogue.default.id, smallest?.id,
                       "the default should be the smallest model in the catalogue")
    }

    func testTheCatalogueIsOrderedSmallestFirst() {
        let sizes = LocalModelCatalogue.all.map(\.byteCount)
        XCTAssertEqual(sizes, sizes.sorted(), "the picker opens at the top, so the top must be quickest")
    }

    func testDescriptorsResolveByID() {
        for model in LocalModelCatalogue.all {
            XCTAssertEqual(LocalModelCatalogue.descriptor(for: model.id)?.repository,
                           model.repository)
        }
        XCTAssertNil(LocalModelCatalogue.descriptor(for: "not-a-model"),
                     "an unknown id must resolve to nothing rather than to the first entry")
    }

    /// The weights are re-downloadable and a gigabyte of them in someone's iCloud
    /// quota is not acceptable, so the page has to say so. Asserted on the source
    /// because it lives in the group's footer, which carries no identifier.
    func testThePageSaysModelsStayOnTheDevice() throws {
        let more = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Haiity/Views/MoreLocalModel.swift"), encoding: .utf8)
        XCTAssertTrue(more.contains("nicht über iCloud übertragen"),
                      "the page must tell the person the weights are not synced")
        XCTAssertTrue(more.contains("local-model-group"),
                      "and the catalogue must be a titled settings group, like every other page")
        XCTAssertTrue(more.contains("AppSettingsGroup("),
                      "and it must be built from the shared component, not a hand-rolled panel")
        XCTAssertTrue(more.contains("AppSettingsRow("),
                      "with the shared row, so it follows the appearance setting like the rest")
    }

    // MARK: - The state machine

    /// An inventory with one model on disk, which is the precondition for a
    /// model being ready at all.
    private func inventory(present modelID: String, bytes: Int64) -> LocalModelInventory {
        var inv = LocalModelInventory()
        inv.record(modelID: modelID, directory: "/models/\(modelID)", byteCount: bytes)
        return inv
    }

    /// The rule that matters: readiness comes from disk, never from a flag.
    ///
    /// A model reported as ready but absent from the inventory fails later, at
    /// generation time, with no explanation — which is the exact failure this
    /// refuses to allow.
    func testAModelIsNotReadyUnlessItsFilesAreOnDisk() {
        var registry = LocalModelRegistry()
        registry.markDownloading("qwen25-0.5b", received: 10, total: 100)
        registry.markReady("qwen25-0.5b")

        XCTAssertFalse(registry.state(for: "qwen25-0.5b").isReady,
                       "a model with nothing on disk must not report itself ready")
        guard case .failed = registry.state(for: "qwen25-0.5b") else {
            return XCTFail("expected an explicit failure, got \(registry.state(for: "qwen25-0.5b"))")
        }
    }

    /// The other half: once the bytes ARE there, the same call says ready. The
    /// refusal above must be about the disk, not about being uncooperative.
    func testAModelWithItsFilesOnDiskIsReady() {
        var registry = LocalModelRegistry(
            inventory: inventory(present: "qwen25-0.5b", bytes: 289_600_000))
        XCTAssertTrue(registry.state(for: "qwen25-0.5b").isReady,
                      "a model whose weights are on disk is ready")
        XCTAssertEqual(registry.readyModelIDs, ["qwen25-0.5b"])
    }

    /// After a relaunch the states are empty, and readiness has to be rebuilt
    /// from what is actually on the phone.
    func testReadinessIsRebuiltFromDiskAfterARelaunch() {
        // No progress state survives a relaunch, so readiness has to come from
        // the inventory — which is why a fresh registry with an empty inventory
        // claims nothing, and the same registry with a populated one is correct.
        let empty = LocalModelRegistry()
        XCTAssertEqual(empty.state(for: "qwen25-0.5b"), .notDownloaded)
        XCTAssertTrue(empty.readyModelIDs.isEmpty)

        let rebuilt = LocalModelRegistry(
            inventory: inventory(present: "qwen25-0.5b", bytes: 289_600_000))
        XCTAssertEqual(rebuilt.state(for: "qwen25-0.5b"),
                       .ready(byteCount: 289_600_000))
    }

    /// Deleting a model has to give the storage back, not just stop offering it.
    func testRemovingAModelForgetsItsBytes() {
        var inv = inventory(present: "qwen25-0.5b", bytes: 289_600_000)
        XCTAssertEqual(inv.totalBytes, 289_600_000)
        inv.remove("qwen25-0.5b")
        XCTAssertEqual(inv.totalBytes, 0,
                       "a deleted model still occupying storage is the bug this catches")
        XCTAssertFalse(inv.isPresent("qwen25-0.5b"))

        var registry = LocalModelRegistry(inventory: inv)
        registry.markRemoved("qwen25-0.5b")
        XCTAssertEqual(registry.state(for: "qwen25-0.5b"), .notDownloaded)
    }

    /// Progress must never make a working model disappear. Somebody who starts a
    /// second download has not asked to lose the first one.
    func testProgressNeverUnreadiesAModelThatIsAlreadyThere() {
        var registry = LocalModelRegistry(
            inventory: inventory(present: "qwen25-0.5b", bytes: 289_600_000))
        registry.markDownloading("qwen25-0.5b", received: 1, total: 289_600_000)
        XCTAssertTrue(registry.state(for: "qwen25-0.5b").isReady,
                      "a working model stayed working while something else reported progress")
    }

    /// Same rule for failure: a model that is on disk and safe cannot be marked
    /// broken by a later attempt.
    func testAFailureCannotUnreadyAModelThatIsAlreadyThere() {
        var registry = LocalModelRegistry(
            inventory: inventory(present: "qwen25-0.5b", bytes: 289_600_000))
        registry.markFailed("qwen25-0.5b", reason: "Netz weg")
        XCTAssertTrue(registry.state(for: "qwen25-0.5b").isReady)
    }

    func testFractionIsNilUntilTheTotalIsKnown() {
        XCTAssertNil(LocalModelState.downloading(received: 0, total: 0).fraction,
                     "an unknown total must not render as 0%")
        XCTAssertEqual(LocalModelState.downloading(received: 50, total: 100).fraction, 0.5)
        XCTAssertEqual(LocalModelState.ready(byteCount: 10).fraction, 1)
        XCTAssertNil(LocalModelState.notDownloaded.fraction)
    }

    /// A server that lies about the length, or a resumed transfer, can report
    /// more than it said. A bar that goes past full is a visible fault.
    func testFractionNeverPassesOne() {
        XCTAssertEqual(LocalModelState.downloading(received: 200, total: 100).fraction, 1)
    }
}
