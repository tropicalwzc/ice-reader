import Foundation
import UniformTypeIdentifiers

enum FilesBookImportOutcome: Equatable {
    case imported
    case replaced
    case skipped
    case failed
}

struct FilesBookImportItemResult: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let outcome: FilesBookImportOutcome
    let detail: String
}

struct FilesBookImportBatchResult: Equatable {
    let items: [FilesBookImportItemResult]

    var importedCount: Int { count(.imported) }
    var replacedCount: Int { count(.replaced) }
    var skippedCount: Int { count(.skipped) }
    var failedCount: Int { count(.failed) }
    var successfulCount: Int { importedCount + replacedCount }

    private func count(_ outcome: FilesBookImportOutcome) -> Int {
        items.filter { $0.outcome == outcome }.count
    }
}

struct FilesBookImportProgress: Equatable {
    let completedCount: Int
    let totalCount: Int
    let currentFilename: String?

    var fractionCompleted: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

private enum FilesBookImportError: LocalizedError {
    case notRegularFile
    case unavailableSize

    var errorDescription: String? {
        switch self {
        case .notRegularFile:
            return "请选择小说文件，不支持文件夹"
        case .unavailableSize:
            return "无法读取文件大小，请确认文件已可下载"
        }
    }
}

final class FilesBookImportCoordinator: @unchecked Sendable {
    static let supportedContentTypes: [UTType] = {
        let extensionTypes = ImportedBookStore.supportedExtensions.compactMap {
            UTType(filenameExtension: $0, conformingTo: .text)
        }
        let candidates = [UTType.plainText, .text, .html] + extensionTypes
        var identifiers = Set<String>()
        return candidates.filter { identifiers.insert($0.identifier).inserted }
    }()

    private let store: ImportedBookStore
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "ice-reader.files-import", qos: .userInitiated)

    init(store: ImportedBookStore = .shared, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func importFiles(
        at urls: [URL],
        progress: @escaping (FilesBookImportProgress) -> Void = { _ in }
    ) async -> FilesBookImportBatchResult {
        guard !urls.isEmpty else { return FilesBookImportBatchResult(items: []) }
        return await withCheckedContinuation { continuation in
            queue.async {
                var items: [FilesBookImportItemResult] = []
                for (index, url) in urls.enumerated() {
                    self.report(
                        FilesBookImportProgress(
                            completedCount: index,
                            totalCount: urls.count,
                            currentFilename: url.lastPathComponent
                        ),
                        to: progress
                    )
                    items.append(self.importFile(at: url))
                    self.report(
                        FilesBookImportProgress(
                            completedCount: index + 1,
                            totalCount: urls.count,
                            currentFilename: index + 1 == urls.count ? nil : urls[index + 1].lastPathComponent
                        ),
                        to: progress
                    )
                }
                continuation.resume(returning: FilesBookImportBatchResult(items: items))
            }
        }
    }

    private func importFile(at sourceURL: URL) -> FilesBookImportItemResult {
        let displayName = sourceURL.lastPathComponent.isEmpty ? "未命名文件" : sourceURL.lastPathComponent
        do {
            let safeFilename = try ImportedBookStore.validatedFilename(displayName)
            let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            var coordinationError: NSError?
            var operationResult: Result<ImportedBookInstallResult, Error>?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
                do {
                    let values = try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { throw FilesBookImportError.notRegularFile }
                    guard let fileSize = values.fileSize else { throw FilesBookImportError.unavailableSize }
                    let expectedSize = Int64(fileSize)
                    guard expectedSize <= ImportedBookStore.maximumImportSize else { throw ImportedBookStoreError.fileTooLarge }
                    guard self.store.hasAvailableSpace(for: expectedSize) else { throw ImportedBookStoreError.insufficientStorage }

                    let stagedURL = try self.store.makeStagingURL()
                    defer { self.store.removeTemporaryFile(stagedURL) }
                    try self.copy(from: coordinatedURL, to: stagedURL, expectedSize: expectedSize)
                    operationResult = .success(
                        try self.store.installStagedFile(
                            stagedURL: stagedURL,
                            filename: safeFilename,
                            source: .filesApp,
                            expectedSize: expectedSize
                        )
                    )
                } catch {
                    operationResult = .failure(error)
                }
            }

            if let coordinationError { throw coordinationError }
            guard let operationResult else { throw ImportedBookStoreError.missingFile }
            let installation = try operationResult.get()
            switch installation.disposition {
            case .created:
                return FilesBookImportItemResult(filename: safeFilename, outcome: .imported, detail: "已导入")
            case .replaced:
                return FilesBookImportItemResult(filename: safeFilename, outcome: .replaced, detail: "已覆盖同名小说并保留阅读进度")
            }
        } catch {
            return FilesBookImportItemResult(
                filename: displayName,
                outcome: outcome(for: error),
                detail: safeDescription(for: error)
            )
        }
    }

    private func copy(from sourceURL: URL, to stagedURL: URL, expectedSize: Int64) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: stagedURL)
        defer {
            try? input.close()
            try? output.close()
        }

        var copied: Int64 = 0
        while true {
            let data = try input.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            copied += Int64(data.count)
            guard copied <= ImportedBookStore.maximumImportSize else { throw ImportedBookStoreError.fileTooLarge }
            try output.write(contentsOf: data)
        }
        guard copied == expectedSize else { throw ImportedBookStoreError.sizeMismatch }
    }

    private func outcome(for error: Error) -> FilesBookImportOutcome {
        if let storeError = error as? ImportedBookStoreError {
            switch storeError {
            case .emptyFilename, .unsupportedExtension, .unsafePath, .fileTooLarge:
                return .skipped
            case .insufficientStorage, .sizeMismatch, .missingFile:
                return .failed
            }
        }
        if let importError = error as? FilesBookImportError, case .notRegularFile = importError {
            return .skipped
        }
        return .failed
    }

    private func safeDescription(for error: Error) -> String {
        if let error = error as? ImportedBookStoreError {
            return error.localizedDescription
        }
        if let error = error as? FilesBookImportError {
            return error.localizedDescription
        }
        return "无法读取此文件，请确认它已下载且仍可访问"
    }

    private func report(_ value: FilesBookImportProgress, to progress: @escaping (FilesBookImportProgress) -> Void) {
        DispatchQueue.main.async { progress(value) }
    }
}
