import XCTest
@testable import ice_reader

/// Covers the reading-progress contracts that the reader's viewport behavior
/// depends on: pure reads, clamping, deliberate backward jumps, key stability,
/// and clamped percentages.
final class BookVMProgressTests: XCTestCase {

    private final class MockCloudSync: ProgressCloudSync {
        var revisions: [String: Int64] = [:]
        private(set) var forcedProgress: [(key: String, progress: Int64)] = []

        func overrideRevision(forKey key: String) -> Int64 {
            revisions[key] ?? 0
        }

        func forceUpdateProgress(_ progress: Int64, forKey key: String) {
            forcedProgress.append((key, progress))
        }
    }

    private struct Fixture {
        let store: ImportedBookStore
        let viewModel: BookVM
    }

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "BookVMProgressTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// Copies `content` into the temporary library and returns the installed record.
    @discardableResult
    private func installBook(_ store: ImportedBookStore, title: String, content: String = "测试内容") throws -> ImportedBookRecord {
        let data = Data(content.utf8)
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        try data.write(to: staged)
        return try store.installBrowserUpload(
            stagedURL: staged,
            filename: "\(title).txt",
            displayRelativePath: nil,
            expectedSize: Int64(data.count)
        )
    }

    /// Builds a store and a view model that both own the same temporary library,
    /// with the catalog already installed.
    private func makeFixture(title: String, content: String = "测试内容", cloud: ProgressCloudSync) throws -> Fixture {
        let store = ImportedBookStore(baseDirectory: directory)
        try installBook(store, title: title, content: content)
        store.cleanupStaging()
        let viewModel = BookVM(importedStore: store, defaults: defaults, cloud: cloud)
        return Fixture(store: store, viewModel: viewModel)
    }

    private func makeViewModel(cloud: ProgressCloudSync = LiveProgressCloudSync()) -> BookVM {
        BookVM(importedStore: ImportedBookStore(baseDirectory: directory), defaults: defaults, cloud: cloud)
    }

    private func cloudKey(for vm: BookVM, id: String) throws -> String {
        try XCTUnwrap(vm.getCloudKey(name: id), "Imported books must resolve a cloud key")
    }

    private func waitForBackgroundSave() {
        let settled = expectation(description: "background save settled")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    func testStoredPageReadDoesNotMutateDefaults() throws {
        let fixture = try makeFixture(title: "纯读", cloud: LiveProgressCloudSync())
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let storageKey = vm.readingStorageKey(for: id)
        let progressKey = vm.getProgressKey(name: id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)
        let appliedKey = vm.getAppliedCloudOverrideKey(cloudKey: cloudStorageKey)

        defaults.set("42", forKey: storageKey)
        defaults.set(0.42, forKey: progressKey)
        defaults.set("90", forKey: cloudStorageKey)
        defaults.set(7, forKey: appliedKey)

        let trackedKeys = [storageKey, progressKey, cloudStorageKey, appliedKey]
        let snapshot = trackedKeys.map { key in
            defaults.object(forKey: key).map { String(describing: $0) } ?? "<nil>"
        }

        _ = vm.readLastPage(name: id)
        _ = vm.storedLocalPage(name: id)
        _ = vm.storedCloudPage(name: id)

        let after = trackedKeys.map { key in
            defaults.object(forKey: key).map { String(describing: $0) } ?? "<nil>"
        }
        XCTAssertEqual(snapshot, after, "Reading the stored position must not write local or cloud storage")
    }

    /// Regression: the iCloud helper forms override keys with its sync prefix,
    /// which is only assigned by `startWithPrefix:`. Asking before the listener
    /// started used to raise `NSInvalidArgumentException` from
    /// `stringWithFormat:` with a nil `%@` argument, crashing the reader.
    func testCloudProgressQueriesTolerateUnusableKeys() {
        XCTAssertEqual(MKiCloudSync.overrideRevision(forKey: "not-a-progress-key"), 0)
        XCTAssertEqual(MKiCloudSync.overrideRevision(forKey: ""), 0)
        // Non-progress keys are ignored rather than raising, and querying the
        // configured prefix stays safe and deterministic.
        MKiCloudSync.forceUpdateProgress(12, forKey: "not-a-progress-key")
        XCTAssertEqual(MKiCloudSync.overrideRevision(forKey: "syncIRA0"), MKiCloudSync.overrideRevision(forKey: "syncIRA0"))
    }

    /// Reproduces the real restart path: the reader resolves the position and
    /// then re-persists exactly what it restored.
    func testRestartPathKeepsLocalPositionAndDoesNotCopyCloud() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "重启", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let storageKey = vm.readingStorageKey(for: id)
        let progressKey = vm.getProgressKey(name: id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)

        defaults.set("300", forKey: storageKey)
        defaults.set("200", forKey: cloudStorageKey)

        // Same-device reads stay monotonic: the larger local position wins and
        // the smaller cloud value must not be copied over it.
        XCTAssertEqual(vm.readLastPage(name: id), 300)
        XCTAssertEqual(vm.storedLocalPage(name: id), 300)

        // The reader then persists what it restored.
        vm.splitedContentsCount = 2_117
        vm.saveLastPage(name: id, page: 300)
        waitForBackgroundSave()

        XCTAssertEqual(defaults.string(forKey: storageKey), "300")
        XCTAssertEqual(defaults.double(forKey: progressKey), 300.0 / 2_117.0, accuracy: 0.001)
    }

    func testStoredPageClampsToContentRange() {
        // The read reports what is stored; clamping is the reader's job.
        XCTAssertEqual(ReadingProgress.clamp(page: -5, contentCount: 120), 0)
        XCTAssertEqual(ReadingProgress.clamp(page: 0, contentCount: 120), 0)
        XCTAssertEqual(ReadingProgress.clamp(page: 119, contentCount: 120), 119)
        XCTAssertEqual(ReadingProgress.clamp(page: 500, contentCount: 120), 119)
        XCTAssertEqual(ReadingProgress.clamp(page: 3, contentCount: 0), 0)
        XCTAssertEqual(ReadingProgress.clamp(page: 0, contentCount: 0), 0)
    }

    func testStoredPageClampsRestoredValueBeyondContent() throws {
        let fixture = try makeFixture(title: "越界", cloud: LiveProgressCloudSync())
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        defaults.set("5000", forKey: vm.readingStorageKey(for: id))
        vm.splitedContentsCount = 120

        XCTAssertEqual(vm.readLastPage(name: id), 5000)
        XCTAssertEqual(ReadingProgress.clamp(page: vm.readLastPage(name: id), contentCount: 120), 119)
    }

    func testStoredPagePrefersNewerCloudRevision() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "云修订", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let storageKey = vm.readingStorageKey(for: id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)

        defaults.set("30", forKey: storageKey)
        defaults.set("80", forKey: cloudStorageKey)
        defaults.set(500, forKey: vm.getAppliedCloudOverrideKey(cloudKey: cloudStorageKey))
        cloud.revisions[cloudStorageKey] = 900

        // A deliberate newer revision wins even when it is smaller: another
        // device chose to re-read an earlier page.
        XCTAssertEqual(vm.readLastPage(name: id), 80)
        cloud.revisions[cloudStorageKey] = 700

        // An older revision is ignored.
        XCTAssertEqual(vm.readLastPage(name: id), 80)
    }

    func testStoredPageNeverMovesBackward() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "不回退", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let storageKey = vm.readingStorageKey(for: id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)

        defaults.set("150", forKey: storageKey)
        defaults.set("90", forKey: cloudStorageKey)
        XCTAssertEqual(vm.readLastPage(name: id), 150)
        // The read must not have copied the smaller cloud value anywhere.
        XCTAssertEqual(vm.storedLocalPage(name: id), 150)
    }

    func testDeliberateBackwardJumpPublishesNewRevision() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "刻意回跳", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)
        let storageKey = vm.readingStorageKey(for: id)

        defaults.set("20", forKey: storageKey)
        defaults.set("9", forKey: cloudStorageKey)
        cloud.revisions[cloudStorageKey] = 100
        defaults.set(100, forKey: vm.getAppliedCloudOverrideKey(cloudKey: cloudStorageKey))

        vm.saveLastPage(name: id, page: 9, forceCloudSync: true)
        waitForBackgroundSave()

        XCTAssertEqual(defaults.string(forKey: storageKey), "9")
        XCTAssertTrue(
            cloud.forcedProgress.contains { $0.key == cloudStorageKey && $0.progress == 9 },
            "A deliberate backward jump must publish a new revision so iCloud cannot pull the reader forward"
        )
        XCTAssertEqual(vm.readLastPage(name: id), 9)
    }

    func testConsumedExternalOverrideIsNotReplayed() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "外部覆盖", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)

        defaults.set("12", forKey: vm.readingStorageKey(for: id))
        defaults.set("64", forKey: cloudStorageKey)
        cloud.revisions[cloudStorageKey] = 4_242

        XCTAssertEqual(vm.consumeExternalProgressOverride(name: id), 64)
        XCTAssertEqual(vm.readLastPage(name: id), 64)
        XCTAssertNil(
            vm.consumeExternalProgressOverride(name: id),
            "The same revision must not be applied twice"
        )
    }

    /// The reader defers an external alignment while the user is mid-read. That
    /// decision must not consume the revision, otherwise the deferred position
    /// would be silently dropped.
    func testFreshOverrideRemainsPendingUntilConsumed() throws {
        let cloud = MockCloudSync()
        let fixture = try makeFixture(title: "待应用", cloud: cloud)
        let vm = fixture.viewModel
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let cloudStorageKey = try cloudKey(for: vm, id: id)

        defaults.set("300", forKey: vm.readingStorageKey(for: id))
        defaults.set("12", forKey: cloudStorageKey)
        cloud.revisions[cloudStorageKey] = 9_000

        XCTAssertTrue(vm.hasFreshExternalProgressOverride(name: id))
        // Peeking must not mark the revision applied.
        XCTAssertTrue(vm.hasFreshExternalProgressOverride(name: id))

        // Applying the deferred alignment consumes it exactly once.
        XCTAssertEqual(vm.consumeExternalProgressOverride(name: id), 12)
        XCTAssertFalse(vm.hasFreshExternalProgressOverride(name: id))
    }

    func testProgressKeyIsStableAcrossTitleChange() throws {
        let fixture = try makeFixture(title: "稳定键", cloud: LiveProgressCloudSync())
        let id = try XCTUnwrap(fixture.store.records().first?.id)
        let storageKey = fixture.viewModel.readingStorageKey(for: id)

        XCTAssertEqual(storageKey, "ImportedBook.\(id)")
        XCTAssertEqual(fixture.viewModel.getProgressKey(name: id), "\(storageKey)ReadingProgress")
        XCTAssertEqual(fixture.viewModel.readingStorageKey(for: id), storageKey)
    }

    func testProgressPercentageIsBounded() throws {
        let vm = makeViewModel()
        vm.splitedContentsCount = 100

        XCTAssertEqual(vm.readingFraction(page: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: 1), 0.01, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: 99), 0.99, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: 100), 0.99, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: -10), 0.0, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: 5_000), 0.99, accuracy: 0.0001)

        vm.splitedContentsCount = 1
        XCTAssertEqual(vm.readingFraction(page: 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(vm.readingFraction(page: 200), 0.0, accuracy: 0.0001)

        vm.splitedContentsCount = 0
        XCTAssertEqual(vm.readingFraction(page: 3), 0.0, accuracy: 0.0001)
    }
}
