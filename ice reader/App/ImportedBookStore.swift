import CryptoKit
import Foundation

enum ImportedBookSource: Codable, Equatable {
    case legacyLAN(serverID: String, bookID: String)
    case browserUpload(relativePath: String?)
    case filesApp

    private enum CodingKeys: String, CodingKey { case kind, serverID, bookID, relativePath }
    private enum Kind: String, Codable { case legacyLAN, browserUpload, filesApp }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .legacyLAN:
            self = .legacyLAN(serverID: try values.decode(String.self, forKey: .serverID), bookID: try values.decode(String.self, forKey: .bookID))
        case .browserUpload:
            self = .browserUpload(relativePath: try values.decodeIfPresent(String.self, forKey: .relativePath))
        case .filesApp:
            self = .filesApp
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .legacyLAN(let serverID, let bookID):
            try values.encode(Kind.legacyLAN, forKey: .kind)
            try values.encode(serverID, forKey: .serverID)
            try values.encode(bookID, forKey: .bookID)
        case .browserUpload(let relativePath):
            try values.encode(Kind.browserUpload, forKey: .kind)
            try values.encodeIfPresent(relativePath, forKey: .relativePath)
        case .filesApp:
            try values.encode(Kind.filesApp, forKey: .kind)
        }
    }
}

enum ImportedBookInstallDisposition: Equatable {
    case created
    case replaced
}

struct ImportedBookInstallResult: Equatable {
    let record: ImportedBookRecord
    let disposition: ImportedBookInstallDisposition
}

struct ImportedBookRecord: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var fileExtension: String
    var relativePath: String
    var source: ImportedBookSource
    var contentHash: String
    var size: Int64
    var importedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, fileExtension, relativePath, source, serverID, serverBookID
        case contentHash, size, importedAt
    }

    init(id: String, title: String, fileExtension: String, relativePath: String, source: ImportedBookSource, contentHash: String, size: Int64, importedAt: Date) {
        self.id = id
        self.title = title
        self.fileExtension = fileExtension
        self.relativePath = relativePath
        self.source = source
        self.contentHash = contentHash
        self.size = size
        self.importedAt = importedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        fileExtension = try values.decode(String.self, forKey: .fileExtension)
        relativePath = try values.decode(String.self, forKey: .relativePath)
        contentHash = try values.decode(String.self, forKey: .contentHash)
        size = try values.decode(Int64.self, forKey: .size)
        importedAt = try values.decode(Date.self, forKey: .importedAt)
        if let decodedSource = try values.decodeIfPresent(ImportedBookSource.self, forKey: .source) {
            source = decodedSource
        } else {
            source = .legacyLAN(serverID: try values.decode(String.self, forKey: .serverID), bookID: try values.decode(String.self, forKey: .serverBookID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(fileExtension, forKey: .fileExtension)
        try values.encode(relativePath, forKey: .relativePath)
        try values.encode(source, forKey: .source)
        try values.encode(contentHash, forKey: .contentHash)
        try values.encode(size, forKey: .size)
        try values.encode(importedAt, forKey: .importedAt)
    }
}

enum ImportedBookStoreError: LocalizedError, Equatable {
    case emptyFilename
    case unsupportedExtension
    case unsafePath
    case fileTooLarge
    case insufficientStorage
    case sizeMismatch
    case missingFile

    var errorDescription: String? {
        switch self {
        case .emptyFilename: return "文件名不能为空"
        case .unsupportedExtension: return "仅支持 TXT、TEXT、MD、MARKDOWN、HTML 和 HTM 小说文件"
        case .unsafePath: return "文件路径不安全"
        case .fileTooLarge: return "单个文件不能超过 200 MB"
        case .insufficientStorage: return "设备可用空间不足"
        case .sizeMismatch: return "上传内容不完整，请重试"
        case .missingFile: return "本机书籍文件不存在"
        }
    }
}

final class ImportedBookStore: @unchecked Sendable {
    static let shared = ImportedBookStore()
    static let maximumImportSize: Int64 = 200 * 1024 * 1024
    static let maximumUploadSize = maximumImportSize
    static let supportedExtensions: Set<String> = ["txt", "text", "md", "markdown", "html", "htm"]

    private let fileManager: FileManager
    private let directory: URL
    private let stagingDirectory: URL
    private let catalogURL: URL
    private let lock = NSLock()
    private var catalog: [ImportedBookRecord] = []

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let baseDirectory {
            directory = baseDirectory
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = applicationSupport.appendingPathComponent("ImportedLibrary", isDirectory: true)
        }
        stagingDirectory = directory.appendingPathComponent("Staging", isDirectory: true)
        catalogURL = directory.appendingPathComponent("catalog.json")
        try? fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        catalog = Self.loadCatalog(from: catalogURL)
        cleanupStaging()
    }

    func records() -> [ImportedBookRecord] {
        lock.lock()
        defer { lock.unlock() }
        return catalog
    }

    func validRecords() -> [ImportedBookRecord] {
        records().filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
    }

    func fileURL(for record: ImportedBookRecord) -> URL {
        directory.appendingPathComponent(record.relativePath, isDirectory: false)
    }

    func makeStagingURL() throws -> URL {
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let url = stagingDirectory.appendingPathComponent(UUID().uuidString + ".partial")
        guard fileManager.createFile(atPath: url.path, contents: nil) else { throw ImportedBookStoreError.missingFile }
        return url
    }

    func hasAvailableSpace(for byteCount: Int64) -> Bool {
        guard byteCount >= 0, byteCount <= Self.maximumUploadSize else { return false }
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return true }
        return Int64(available) > byteCount + 8 * 1024 * 1024
    }

    func installStagedFile(stagedURL: URL, filename: String, source: ImportedBookSource, expectedSize: Int64) throws -> ImportedBookInstallResult {
        let safeFilename = try Self.validatedFilename(filename)
        let safeSource: ImportedBookSource
        switch source {
        case .browserUpload(let relativePath):
            safeSource = .browserUpload(relativePath: try Self.validatedDisplayPath(relativePath))
        case .legacyLAN, .filesApp:
            safeSource = source
        }
        guard expectedSize >= 0, expectedSize <= Self.maximumImportSize else { throw ImportedBookStoreError.fileTooLarge }
        let attributes = try fileManager.attributesOfItem(atPath: stagedURL.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualSize == expectedSize else { throw ImportedBookStoreError.sizeMismatch }
        return try commit(
            stagedURL: stagedURL,
            title: (safeFilename as NSString).deletingPathExtension,
            fileExtension: Self.fileExtension(for: safeFilename),
            source: safeSource,
            contentHash: try Self.sha256(of: stagedURL),
            size: actualSize
        )
    }

    @discardableResult
    func installBrowserUpload(stagedURL: URL, filename: String, displayRelativePath: String?, expectedSize: Int64) throws -> ImportedBookRecord {
        try installStagedFile(
            stagedURL: stagedURL,
            filename: filename,
            source: .browserUpload(relativePath: displayRelativePath),
            expectedSize: expectedSize
        ).record
    }

    func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let index = catalog.firstIndex(where: { $0.id == id }) else { return }
        let record = catalog[index]
        let url = fileURL(for: record)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        catalog.remove(at: index)
        try saveLocked()
    }

    func removeTemporaryFile(_ url: URL) { try? fileManager.removeItem(at: url) }

    func cleanupStaging() {
        guard let files = try? fileManager.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "partial" { try? fileManager.removeItem(at: file) }
    }

    static func validatedFilename(_ filename: String) throws -> String {
        let value = filename.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ImportedBookStoreError.emptyFilename }
        guard value.count <= 240, value == (value as NSString).lastPathComponent,
              !value.hasPrefix("."), !value.contains("/"), !value.contains("\\"), !value.contains(".."),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw ImportedBookStoreError.unsafePath }
        guard supportedExtensions.contains(fileExtension(for: value)) else { throw ImportedBookStoreError.unsupportedExtension }
        return value
    }

    static func validatedDisplayPath(_ path: String?) throws -> String? {
        guard let path, !path.isEmpty else { return nil }
        let value = path.precomposedStringWithCanonicalMapping
        guard value.utf8.count <= 1024, !value.hasPrefix("/"), !value.hasPrefix("\\"), !value.contains("\\"),
              value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
              }) else { throw ImportedBookStoreError.unsafePath }
        return value
    }

    static func clampedPage(_ page: Int, contentCount: Int) -> Int {
        guard contentCount > 0 else { return 0 }
        return min(max(page, 0), contentCount - 1)
    }

    static func decodeText(at url: URL) throws -> String {
        if let value = try? String(contentsOf: url, encoding: .utf8) { return value }
        let rawEncoding = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
        return try String(contentsOf: url, encoding: String.Encoding(rawValue: rawEncoding))
    }

    static func sha256(of url: URL) throws -> String {
        guard let stream = InputStream(url: url) else { throw ImportedBookStoreError.missingFile }
        stream.open()
        defer { stream.close() }
        var digest = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? ImportedBookStoreError.missingFile }
            if count == 0 { break }
            digest.update(data: Data(buffer[0..<count]))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func commit(stagedURL: URL, title: String, fileExtension: String, source: ImportedBookSource, contentHash: String, size: Int64) throws -> ImportedBookInstallResult {
        lock.lock()
        defer { lock.unlock() }
        let existingIndex = catalog.firstIndex { Self.normalizedTitle($0.title) == Self.normalizedTitle(title) }
        let disposition: ImportedBookInstallDisposition = existingIndex == nil ? .created : .replaced
        let localID = existingIndex.map { catalog[$0].id } ?? UUID().uuidString
        let relativePath = existingIndex.map { catalog[$0].relativePath } ?? "\(localID).\(fileExtension)"
        let destination = directory.appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagedURL)
        } else {
            try fileManager.moveItem(at: stagedURL, to: destination)
        }
        let record = ImportedBookRecord(id: localID, title: title, fileExtension: Self.fileExtension(for: relativePath), relativePath: relativePath, source: source, contentHash: contentHash, size: size, importedAt: Date())
        if let existingIndex { catalog[existingIndex] = record } else { catalog.append(record) }
        let duplicates = catalog.filter { $0.id != localID && Self.normalizedTitle($0.title) == Self.normalizedTitle(title) }
        catalog.removeAll { $0.id != localID && Self.normalizedTitle($0.title) == Self.normalizedTitle(title) }
        try saveLocked()
        for duplicate in duplicates { try? fileManager.removeItem(at: fileURL(for: duplicate)) }
        return ImportedBookInstallResult(record: record, disposition: disposition)
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private static func fileExtension(for filename: String) -> String { (filename as NSString).pathExtension.lowercased() }

    private static func loadCatalog(from url: URL) -> [ImportedBookRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ImportedBookRecord].self, from: data)) ?? []
    }

    private func saveLocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
    }
}
