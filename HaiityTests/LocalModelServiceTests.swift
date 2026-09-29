import XCTest
@testable import Haiity

/// The download manager's parts that can be wrong without a network.
///
/// Everything here runs against a temporary directory and no network: the disk
/// scan, the URL construction, and the rule that an incomplete model must not
/// look complete. Those are the three places a bug costs somebody a gigabyte of
/// downloaded weights or a model that fails at generation time with no
/// explanation.
@MainActor
final class LocalModelServiceTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-models-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "local-model-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeService() -> LocalModelService {
        LocalModelService(root: root, session: .shared, defaults: defaults)
    }

    /// Writes every file the catalogue names for a model, so the scan has
    /// something real to find.
    @discardableResult
    private func writeModel(_ model: LocalModelDescriptor, bytes: Int = 8) -> URL {
        let directory = root.appendingPathComponent(model.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in model.files {
            let data = Data(repeating: 0, count: bytes)
            try? data.write(to: directory.appendingPathComponent(file))
        }
        return directory
    }

    // MARK: - What counts as "on disk"

    /// A complete model is found, and its real byte count is reported rather
    /// than the figure the repository claims — those differ, and only one of them
    /// is what the phone is actually carrying.
    func testAScannedModelIsReadyAndItsBytesAreReal() {
        let model = LocalModelCatalogue.all[0]
        writeModel(model, bytes: 10)

        let service = makeService()
        XCTAssertTrue(service.registry.state(for: model.id).isReady)
        // Nine files at ten bytes each.
        XCTAssertEqual(service.totalBytesOnDisk, Int64(model.files.count * 10),
                       "the reported size must be what is on the phone, not the catalogue's claim")
    }

    /// THE important one. A download interrupted at 90% leaves a directory. If
    /// that directory counted as a model, the app would offer to read a sentence
    /// with weights that are not there, and fail later with nothing to show for it.
    func testAnIncompleteModelIsNotReady() {
        let model = LocalModelCatalogue.all[0]
        let directory = root.appendingPathComponent(model.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Every file except one.
        for file in model.files.dropLast() {
            try? Data(repeating: 0, count: 8).write(to: directory.appendingPathComponent(file))
        }

        let service = makeService()
        XCTAssertFalse(service.registry.state(for: model.id).isReady,
                       "a model missing a file must not be offered")
        XCTAssertEqual(service.totalBytesOnDisk, 0,
                       "and it must not be counted as occupying storage either")
    }

    /// An empty directory with the right name is still not a model.
    func testAnEmptyDirectoryIsNotAModel() {
        let model = LocalModelCatalogue.all[0]
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent(model.id), withIntermediateDirectories: true)
        let service = makeService()
        XCTAssertFalse(service.registry.state(for: model.id).isReady)
    }

    /// A staging directory from a cancelled run is not a model either, and it
    /// must not show up in the catalogue's terms.
    func testStagingDirectoriesAreNotMistakenForModels() {
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent(".staging-qwen25-0.5b"), withIntermediateDirectories: true)
        let service = makeService()
        XCTAssertTrue(service.registry.readyModelIDs.isEmpty)
        XCTAssertEqual(service.totalBytesOnDisk, 0)
    }

    /// A directory belonging to a model that is no longer offered is not counted
    /// either, or a removed model would keep claiming space forever.
    func testUnknownDirectoriesAreIgnored() {
        try? FileManager.default.createDirectory(
            at: root.appendingPathComponent("some-other-tool"), withIntermediateDirectories: true)
        let service = makeService()
        XCTAssertEqual(service.totalBytesOnDisk, 0)
        XCTAssertTrue(service.registry.readyModelIDs.isEmpty)
    }

    /// Nothing on disk yet is a first run, not an error.
    func testAFreshInstallSeesNothing() {
        let service = makeService()
        XCTAssertTrue(service.registry.readyModelIDs.isEmpty)
        XCTAssertEqual(service.totalBytesOnDisk, 0)
    }

    // MARK: - URLs

    /// The CDN's resolve path, not the API and not a redirector.
    func testFileURLsPointAtTheResolveEndpoint() throws {
        let url = try XCTUnwrap(LocalModelService.fileURL(
            repository: "mlx-community/Qwen2.5-0.5B-Instruct-4bit", file: "config.json"))
        XCTAssertEqual(url.absoluteString,
                       "https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit/resolve/main/config.json")
        XCTAssertEqual(url.host, "huggingface.co")
        // `main`, not a branch or a commit: a resume has to agree with the
        // original request, and a moving ref would silently produce a model made
        // of two different revisions.
        XCTAssertTrue(url.absoluteString.contains("/resolve/main/"))
    }

    /// A file name with characters that need escaping must not be pasted in raw.
    func testFileURLsEscapeTheirComponents() throws {
        let url = try XCTUnwrap(LocalModelService.fileURL(repository: "a/b", file: "a b+c.json"))
        XCTAssertFalse(url.absoluteString.contains(" "), "an unescaped space makes an invalid URL")
        XCTAssertTrue(url.absoluteString.contains("%20"))
    }

    // MARK: - The choice

    /// A fresh install reads the smallest model, because the first thing a new
    /// user does is read one sentence.
    func testTheDefaultSelectionIsTheSmallestModel() {
        let service = makeService()
        XCTAssertEqual(service.selectedModelID, LocalModelCatalogue.default.id)
    }

    func testTheSelectionRoundTrips() {
        let service = makeService()
        service.selectedModelID = "gemma2-2b"
        XCTAssertEqual(service.selectedModelID, "gemma2-2b")
        XCTAssertEqual(makeService().selectedModelID, "gemma2-2b",
                       "the choice has to survive a relaunch")
    }

    /// A stored id from a build that offered a model we no longer do must not
    /// strand the app on a name it cannot resolve.
    func testAStaleSelectionFallsBackToTheDefault() {
        defaults.set("a-model-we-removed", forKey: "localModel.selectedModelID")
        XCTAssertEqual(makeService().selectedModelID, LocalModelCatalogue.default.id)
    }

    func testAnUnknownSelectionIsRefused() {
        let service = makeService()
        service.selectedModelID = "gemma2-2b"
        service.selectedModelID = "not-a-model"
        XCTAssertEqual(service.selectedModelID, "gemma2-2b",
                       "an unknown id must not be written")
    }

    /// Selection and availability are different questions. Somebody who picked the
    /// 2 GB model on another device, or who has not downloaded it yet, must still
    /// get a model that can actually run — and a processing model is the fallback
    /// because it is the one the app is shaped around.
    func testTheUsableModelFallsBackWhenTheChosenOneIsNotOnDisk() {
        let service = makeService()
        service.selectedModelID = "gemma2-2b"          // 1.5 GB, nothing downloaded
        XCTAssertEqual(service.selectedModel.id, "gemma2-2b", "the choice is remembered")
        XCTAssertEqual(service.usableModel.id, LocalModelCatalogue.default.id,
                       "but reading has to use something that is actually here")
    }

    /// With a small model on disk and a big one chosen, the small one reads. This
    /// is the case the fallback exists for, and it was written backwards first:
    /// the guard fired only when the CHOICE was a processing model, so choosing
    /// the multilingual one returned a model whose weights were not present.
    func testTheUsableModelIsAPresentProcessingModelWhenTheChoiceIsAbsent() {
        let service = makeService()
        service.selectedModelID = "gemma2-2b"          // not on disk
        writeModel(LocalModelCatalogue.default)        // the small one is
        service.refresh()
        XCTAssertEqual(service.usableModel.id, LocalModelCatalogue.default.id,
                       "a present small model beats a choice that is not here")
    }

    /// With nothing downloaded at all there is nothing to use, and the answer is
    /// the model the app will offer to fetch.
    func testTheUsableModelWithNothingDownloadedIsTheOneWeWouldFetch() {
        let service = makeService()
        service.selectedModelID = "phi35-mini"
        XCTAssertEqual(service.usableModel.id, LocalModelCatalogue.default.id)
    }

    /// Once the big model IS there, it is used. The fallback must not get stuck.
    func testTheUsableModelIsTheChosenOneOnceItIsOnDisk() {
        let service = makeService()
        service.selectedModelID = "gemma2-2b"
        writeModel(LocalModelCatalogue.descriptor(for: "gemma2-2b")!)
        service.refresh()
        XCTAssertEqual(service.usableModel.id, "gemma2-2b")
    }

    /// A download that finished while the app was in the background is on disk
    /// before the registry has heard of it. Coming back to the foreground is
    /// when that gets noticed, and this is the case that used to be invisible.
    func testRefreshPicksUpWeightsThatArrivedInTheBackground() {
        let service = makeService()
        XCTAssertFalse(service.registry.state(for: "gemma2-2b").isReady)
        writeModel(LocalModelCatalogue.descriptor(for: "gemma2-2b")!)
        service.refresh()
        XCTAssertTrue(service.registry.state(for: "gemma2-2b").isReady,
                      "a model that arrived while we were away is usable when we come back")
    }

    // MARK: - Deleting

    /// Deleting has to actually free the space, not just stop offering the model.
    func testDeletingFreesTheSpaceAndForgetsTheModel() {
        let model = LocalModelCatalogue.all[0]
        writeModel(model, bytes: 10)
        let service = makeService()
        XCTAssertTrue(service.registry.state(for: model.id).isReady)

        service.delete(model)

        XCTAssertEqual(service.totalBytesOnDisk, 0, "a deleted model still occupying space is the bug")
        XCTAssertFalse(service.registry.state(for: model.id).isReady)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.directory(for: model).path))
    }

    /// Deleting the model you picked moves the choice back, rather than leaving
    /// you on a model that is gone.
    func testDeletingTheChosenModelResetsTheChoice() {
        let model = LocalModelCatalogue.all[0]
        writeModel(model)
        let service = makeService()
        service.selectedModelID = model.id
        service.delete(model)
        XCTAssertEqual(service.selectedModelID, LocalModelCatalogue.default.id)
    }
}
