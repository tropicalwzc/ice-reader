import XCTest
@testable import ice_reader

final class FilesBookImporterTests: XCTestCase {
    func testBatchContinuesAfterUnsupportedFileAndCleansStaging() async throws {
        let root = temporaryDirectory()
        let store = ImportedBookStore(baseDirectory: root)
        let validURL = try sourceFile(named: "三体.txt", data: Data("第一章".utf8))
        let unsupportedURL = try sourceFile(named: "封面.pdf", data: Data("PDF".utf8))

        let result = await FilesBookImportCoordinator(store: store).importFiles(at: [unsupportedURL, validURL])

        XCTAssertEqual(result.items.map(\.outcome), [.skipped, .imported])
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(store.validRecords().map(\.title), ["三体"])
        let stagedFiles = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Staging", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(stagedFiles.isEmpty)
    }

    func testFilesReplacementPreservesIdentityAndProgressKey() async throws {
        let root = temporaryDirectory()
        let store = ImportedBookStore(baseDirectory: root)
        let originalData = Data("旧内容".utf8)
        let original = try store.installStagedFile(
            stagedURL: temporaryFile(originalData),
            filename: "小说.txt",
            source: .browserUpload(relativePath: nil),
            expectedSize: Int64(originalData.count)
        )
        XCTAssertEqual(original.disposition, .created)
        let viewModel = await MainActor.run { BookVM(importedStore: store) }
        let progressKey = await MainActor.run { viewModel.getProgressKey(name: original.record.id) }
        let previousProgress = UserDefaults.standard.object(forKey: progressKey)
        defer {
            if let previousProgress {
                UserDefaults.standard.set(previousProgress, forKey: progressKey)
            } else {
                UserDefaults.standard.removeObject(forKey: progressKey)
            }
        }
        UserDefaults.standard.set(0.42, forKey: progressKey)

        let replacementData = Data("来自文件 App 的新内容".utf8)
        let replacementURL = try sourceFile(named: "小说.TXT", data: replacementData)
        let batch = await FilesBookImportCoordinator(store: store).importFiles(at: [replacementURL])
        let replaced = try XCTUnwrap(store.records().first)

        XCTAssertEqual(batch.items.map(\.outcome), [.replaced])
        XCTAssertEqual(replaced.id, original.record.id)
        XCTAssertEqual(replaced.source, .filesApp)
        XCTAssertEqual(try Data(contentsOf: store.fileURL(for: replaced)), replacementData)
        let retainedProgressKey = await MainActor.run { viewModel.getProgressKey(name: replaced.id) }
        let retainedProgress = await MainActor.run { viewModel.readLastProgressOf(name: replaced.id) }
        XCTAssertEqual(retainedProgressKey, progressKey)
        XCTAssertEqual(retainedProgress, 0.42, accuracy: 0.001)
    }

    func testFilesRecordSurvivesCatalogReloadWithoutOriginalURL() async throws {
        let root = temporaryDirectory()
        let sourceURL = try sourceFile(named: "离线阅读.md", data: Data("离线内容".utf8))
        let firstStore = ImportedBookStore(baseDirectory: root)
        let result = await FilesBookImportCoordinator(store: firstStore).importFiles(at: [sourceURL])
        XCTAssertEqual(result.importedCount, 1)
        try FileManager.default.removeItem(at: sourceURL)

        let reloadedStore = ImportedBookStore(baseDirectory: root)
        let record = try XCTUnwrap(reloadedStore.validRecords().first)
        XCTAssertEqual(record.source, .filesApp)
        XCTAssertEqual(try ImportedBookStore.decodeText(at: reloadedStore.fileURL(for: record)), "离线内容")
    }

    func testSupportedExtensionsAndMaximumSizeAreAuthoritative() throws {
        for fileExtension in ImportedBookStore.supportedExtensions {
            XCTAssertNoThrow(try ImportedBookStore.validatedFilename("小说.\(fileExtension)"))
        }
        XCTAssertThrowsError(try ImportedBookStore.validatedFilename("小说.epub"))

        let store = ImportedBookStore(baseDirectory: temporaryDirectory())
        XCTAssertThrowsError(
            try store.installStagedFile(
                stagedURL: temporaryFile(Data()),
                filename: "超大小说.txt",
                source: .filesApp,
                expectedSize: ImportedBookStore.maximumImportSize + 1
            )
        ) { error in
            XCTAssertEqual(error as? ImportedBookStoreError, .fileTooLarge)
        }
    }

    func testCurrentBrowserAndFilesSourceMetadataRoundTrips() throws {
        let records = [
            ImportedBookRecord(
                id: "browser",
                title: "浏览器",
                fileExtension: "txt",
                relativePath: "browser.txt",
                source: .browserUpload(relativePath: "目录/浏览器.txt"),
                contentHash: "a",
                size: 1,
                importedAt: Date(timeIntervalSince1970: 0)
            ),
            ImportedBookRecord(
                id: "files",
                title: "文件",
                fileExtension: "txt",
                relativePath: "files.txt",
                source: .filesApp,
                contentHash: "b",
                size: 1,
                importedAt: Date(timeIntervalSince1970: 0)
            )
        ]
        let encoded = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([ImportedBookRecord].self, from: encoded)
        XCTAssertEqual(decoded, records)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        try data.write(to: url)
        return url
    }

    private func sourceFile(named name: String, data: Data) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}
