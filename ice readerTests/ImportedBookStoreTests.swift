import XCTest
@testable import ice_reader

final class ImportedBookStoreTests: XCTestCase {
    func testLegacyCatalogDecodesWithoutChangingIdentity() throws {
        let root = temporaryDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: root.appendingPathComponent("stable.txt"))
        let json = """
        [{"id":"stable-id","title":"旧书","fileExtension":"txt","relativePath":"stable.txt","serverID":"old-server","serverBookID":"old-book","contentHash":"hash","size":6,"importedAt":"2024-01-01T00:00:00Z"}]
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("catalog.json"))
        let record = try XCTUnwrap(ImportedBookStore(baseDirectory: root).validRecords().first)
        XCTAssertEqual(record.id, "stable-id")
        XCTAssertEqual(record.source, .legacyLAN(serverID: "old-server", bookID: "old-book"))
    }

    func testBrowserUploadAndSameTitleReplacementPreserveIdentity() throws {
        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        let firstData = Data("第一版".utf8)
        let first = try store.installBrowserUpload(stagedURL: temporaryFile(firstData), filename: "中文小说.txt", displayRelativePath: "书库/中文小说.txt", expectedSize: Int64(firstData.count))
        let secondData = Data("第二版内容".utf8)
        let second = try store.installBrowserUpload(stagedURL: temporaryFile(secondData), filename: " 中文小说.TXT ", displayRelativePath: nil, expectedSize: Int64(secondData.count))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.records().count, 1)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: second)), secondData)
        XCTAssertEqual(second.source, .browserUpload(relativePath: nil))
    }

    func testStagingCleanupAndValidation() throws {
        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        let partial = try store.makeStagingURL()
        try Data("partial".utf8).write(to: partial)
        store.cleanupStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertNoThrow(try ImportedBookStore.validatedFilename("三体.markdown"))
        XCTAssertThrowsError(try ImportedBookStore.validatedFilename("../secret.txt"))
        XCTAssertThrowsError(try ImportedBookStore.validatedFilename("image.pdf"))
        XCTAssertThrowsError(try ImportedBookStore.validatedDisplayPath("目录/../秘密.txt"))
    }

    func testUTF8AndGB18030BytesRemainReadable() throws {
        XCTAssertEqual(try ImportedBookStore.decodeText(at: temporaryFile(Data("中文 UTF-8".utf8))), "中文 UTF-8")
        XCTAssertEqual(try ImportedBookStore.decodeText(at: temporaryFile(Data([0xB2, 0xE2, 0xCA, 0xD4]))), "测试")
    }

    func testIncompleteUploadDoesNotReplaceExistingBook() throws {
        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        let originalData = Data("完整内容".utf8)
        let original = try store.installBrowserUpload(stagedURL: temporaryFile(originalData), filename: "书.txt", displayRelativePath: nil, expectedSize: Int64(originalData.count))
        XCTAssertThrowsError(try store.installBrowserUpload(stagedURL: temporaryFile(Data("短".utf8)), filename: "书.txt", displayRelativePath: nil, expectedSize: 100))
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: original)), originalData)
    }

    func testBookViewModelDeletesImportedBookAndClearsLastReadState() throws {
        let previousLastRead = UserDefaults.standard.object(forKey: "LastReadBookName")
        defer {
            if let previousLastRead {
                UserDefaults.standard.set(previousLastRead, forKey: "LastReadBookName")
            } else {
                UserDefaults.standard.removeObject(forKey: "LastReadBookName")
            }
        }
        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        let data = Data("待删除内容".utf8)
        let record = try store.installBrowserUpload(
            stagedURL: temporaryFile(data),
            filename: "待删除小说.txt",
            displayRelativePath: nil,
            expectedSize: Int64(data.count)
        )
        let fileURL = store.fileURL(for: record)
        let viewModel = BookVM(importedStore: store)
        viewModel.LastReadBookName = record.id

        try viewModel.deleteImportedBook(id: record.id)

        XCTAssertTrue(store.records().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(viewModel.hasImportedBooks)
        XCTAssertEqual(viewModel.bookNames.map(\.name), ["样例占位"])
        XCTAssertEqual(viewModel.LastReadBookName, "")
    }

    func testImportedBooksWithSameNormalizedTitleUseSameCloudKeyAcrossStores() throws {
        let firstStore = ImportedBookStore(baseDirectory: temporaryDirectory())
        let secondStore = ImportedBookStore(baseDirectory: temporaryDirectory())
        let firstData = Data("设备一".utf8)
        let secondData = Data("设备二".utf8)
        let first = try firstStore.installBrowserUpload(
            stagedURL: temporaryFile(firstData),
            filename: "Ｃａｆé.txt",
            displayRelativePath: nil,
            expectedSize: Int64(firstData.count)
        )
        let second = try secondStore.installBrowserUpload(
            stagedURL: temporaryFile(secondData),
            filename: "cafe.md",
            displayRelativePath: nil,
            expectedSize: Int64(secondData.count)
        )
        let firstViewModel = BookVM(importedStore: firstStore)
        let secondViewModel = BookVM(importedStore: secondStore)

        let firstKey = try XCTUnwrap(firstViewModel.getCloudKey(name: first.id))
        let secondKey = try XCTUnwrap(secondViewModel.getCloudKey(name: second.id))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(firstKey, secondKey)
        XCTAssertTrue(firstKey.hasPrefix("syncImported."))
        XCTAssertLessThanOrEqual("syncOverride_\(firstKey)".utf8.count, 64)
    }

    func testDifferentImportedTitlesUseDifferentCloudKeys() {
        XCTAssertNotEqual(
            BookVM.importedCloudKey(for: "第一本书"),
            BookVM.importedCloudKey(for: "第二本书")
        )
    }

    func testCloudRestoredPageIsResolvedWithoutWritingLocalStorage() throws {
        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        let data = Data("云端阅读进度".utf8)
        let record = try store.installBrowserUpload(
            stagedURL: temporaryFile(data),
            filename: "云端恢复-\(UUID().uuidString).txt",
            displayRelativePath: nil,
            expectedSize: Int64(data.count)
        )
        let viewModel = BookVM(importedStore: store)
        CloudManager.shared.initCloudListener()
        viewModel.splitedContentsCount = 200
        let cloudKey = try XCTUnwrap(viewModel.getCloudKey(name: record.id))
        let storageKey = viewModel.readingStorageKey(for: record.id)
        let progressKey = viewModel.getProgressKey(name: record.id)
        let appliedOverrideKey = viewModel.getAppliedCloudOverrideKey(cloudKey: cloudKey)
        let cloudOverrideKey = "syncOverride_\(cloudKey)"
        let keys = [cloudKey, storageKey, progressKey, appliedOverrideKey, cloudOverrideKey]
        defer { keys.forEach(UserDefaults.standard.removeObject(forKey:)) }
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
        UserDefaults.standard.set("50", forKey: cloudKey)

        // Resolving the stored page is read-only: it must report the cloud value
        // without copying it into local storage or rewriting the percentage.
        XCTAssertEqual(viewModel.readLastPage(name: record.id), 50)
        XCTAssertNil(UserDefaults.standard.string(forKey: storageKey))
        XCTAssertEqual(UserDefaults.standard.double(forKey: progressKey), 0.0, accuracy: 0.001)

        // The explicit persistence path still records both the page and the
        // clamped percentage.
        viewModel.saveLastPage(name: record.id, page: 50)
        let persisted = expectation(description: "local progress persisted")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { persisted.fulfill() }
        wait(for: [persisted], timeout: 2)
        XCTAssertEqual(UserDefaults.standard.string(forKey: storageKey), "50")
        XCTAssertEqual(UserDefaults.standard.double(forKey: progressKey), 0.25, accuracy: 0.001)
    }

    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true) }
    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        try data.write(to: url)
        return url
    }
}
