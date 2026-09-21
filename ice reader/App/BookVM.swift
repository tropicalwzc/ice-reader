//
//  BookVM.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import Foundation
import Combine
import CryptoKit
import SwiftUI
import RegexBuilder

enum BookLocation: Equatable {
    case bundled
    case imported(relativePath: String)
}

struct BookInfo: Identifiable {
    internal init(id: String? = nil, name: String, extention: String, active: Bool = false, location: BookLocation = .bundled) {
        self.id = id ?? "bundled:\(name)"
        self.name = name
        self.extention = extention
        self.active = active
        self.location = location
        self.progress = 0.0
    }

    let id: String
    var name : String
    var extention: String
    var active : Bool
    let location: BookLocation
    var progress : Double
}

/// iCloud progress plumbing used by `BookVM`.
///
/// The protocol exists so reading-progress behavior can be exercised in tests
/// without touching the real ubiquitous key-value store.
protocol ProgressCloudSync {
    /// Revision of the newest deliberate override written by any device, or 0.
    func overrideRevision(forKey key: String) -> Int64
    /// Publishes a deliberate progress value that must win the next merge.
    func forceUpdateProgress(_ progress: Int64, forKey key: String)
}

/// Production conformance backed by `MKiCloudSync`, whose API is class-level.
struct LiveProgressCloudSync: ProgressCloudSync {
    func overrideRevision(forKey key: String) -> Int64 {
        MKiCloudSync.overrideRevision(forKey: key)
    }

    func forceUpdateProgress(_ progress: Int64, forKey key: String) {
        MKiCloudSync.forceUpdateProgress(progress, forKey: key)
    }
}

/// Pure progress arithmetic shared by the reader and its tests.
enum ReadingProgress {
    /// Clamps a stored page into the valid range of the current content.
    static func clamp(page: Int, contentCount: Int) -> Int {
        guard contentCount > 0 else { return 0 }
        return min(max(page, 0), contentCount - 1)
    }

    /// Fraction of the book that has been read, always within `0...1`.
    static func fraction(page: Int, contentCount: Int) -> Double {
        guard contentCount > 0 else { return 0 }
        let clamped = clamp(page: page, contentCount: contentCount)
        return min(max(Double(clamped) / Double(contentCount), 0), 1)
    }
}

class BookVM: ObservableObject {
    /// Serialises position persistence so rapid updates cannot land out of order.
    private static let progressWriteQueue = DispatchQueue(label: "ice.reader.progress.write", qos: .userInteractive)
    private let importedStore: ImportedBookStore
    private let bundledBookCount = 1
    private let defaults: UserDefaults
    private let cloud: ProgressCloudSync
    @Published var datas : [String]?
    // 正式小说通过浏览器上传；App 只内置一个可读占位样例。
    @Published var bookNames:[BookInfo] = [
        BookInfo(name:"样例占位", extention:"txt"),
    ]
    
    @Published var splitedContents: Array<Substring> = []
    @Published var splitedContentsCount: Double = 1.0
    private var sequence: String.SubSequence = String.SubSequence(stringLiteral: "")
    
    @AppStorage("LastReadBookName")
    var LastReadBookName = ""
    var blockSaveAction = false
    
    var completeBookName = ""
    
    let cloudManager = NSUbiquitousKeyValueStore.default

    var hasImportedBooks: Bool {
        bookNames.contains { book in
            if case .imported = book.location {
                return true
            }
            return false
        }
    }

    var importedBookRecords: [ImportedBookRecord] {
        importedStore.validRecords()
    }

    init(
        importedStore: ImportedBookStore = .shared,
        defaults: UserDefaults = .standard,
        cloud: ProgressCloudSync = LiveProgressCloudSync()
    ) {
        self.importedStore = importedStore
        self.defaults = defaults
        self.cloud = cloud
        // Progress reads consult the override revision, which needs the sync
        // prefix to be configured before the first read.
        CloudManager.shared.initCloudListener()
        reloadImportedBooks()
    }

    func reloadImportedBooks() {
        let bundled = Array(bookNames.prefix(bundledBookCount))
        let imported = importedStore.validRecords().map {
            BookInfo(
                id: $0.id,
                name: $0.title,
                extention: $0.fileExtension,
                location: .imported(relativePath: $0.relativePath)
            )
        }
        if Thread.isMainThread {
            applyBookList(bundled + imported)
        } else {
            DispatchQueue.main.async {
                self.applyBookList(bundled + imported)
            }
        }
    }

    private func applyBookList(_ books: [BookInfo]) {
        bookNames = books
        if !LastReadBookName.isEmpty, book(for: LastReadBookName) == nil {
            LastReadBookName = ""
        }
        // Replacing a book's bytes changes its split count, so the cached
        // content must not be reused. Otherwise the reader would clamp and
        // persist a position against the previous split count.
        if !completeBookName.isEmpty, book(for: completeBookName) == nil {
            completeBookName = ""
            splitedContents = []
            splitedContentsCount = 1
        }
        updateProgresses()
    }

    func importedBookWasDeleted(_ record: ImportedBookRecord) {
        invalidateContent(bookID: record.id)
        if LastReadBookName == record.id {
            LastReadBookName = ""
            GlobalSignalEmitter.cleanLastReadBook.send(params: true)
        }
        reloadImportedBooks()
    }

    func importedRecord(id: String) -> ImportedBookRecord? {
        importedStore.records().first { $0.id == id }
    }

    func deleteImportedBook(id: String) throws {
        guard let record = importedRecord(id: id) else { return }
        try importedStore.delete(id: id)
        importedBookWasDeleted(record)
    }

    func importFiles(
        at urls: [URL],
        progress: @escaping (FilesBookImportProgress) -> Void
    ) async -> FilesBookImportBatchResult {
        let result = await FilesBookImportCoordinator(store: importedStore).importFiles(at: urls, progress: progress)
        if result.successfulCount > 0 {
            await MainActor.run {
                completeBookName = ""
                splitedContents = []
                splitedContentsCount = 1
                reloadImportedBooks()
            }
        }
        return result
    }

    func invalidateContent(bookID: String) {
        if completeBookName == bookID {
            completeBookName = ""
            splitedContents = []
            splitedContentsCount = 1
        }
    }

    func book(for identifier: String) -> BookInfo? {
        bookNames.first { $0.id == identifier } ?? bookNames.first { $0.name == identifier }
    }

    func displayName(for identifier: String) -> String {
        book(for: identifier)?.name ?? identifier
    }

    private func progressStorageKey(for identifier: String) -> String {
        guard let book = book(for: identifier) else { return identifier }
        switch book.location {
        case .bundled:
            return book.name
        case .imported:
            return "ImportedBook.\(book.id)"
        }
    }
    
    func isLastActive(name : String) -> Bool {
        guard let book = book(for: name) else { return LastReadBookName == name }
        return LastReadBookName == book.id || LastReadBookName == book.name
    }
    
    /// Cloud key for the bundled placeholder list.
    ///
    /// Computed rather than cached: progress reads and writes happen on a
    /// background queue, and a lazily cached dictionary would be mutated from
    /// several threads at once.
    private var bundledCloudKeys: [String: String] {
        var resDict: [String: String] = [:]
        let total = min(bundledBookCount, bookNames.count)
        for i in 0..<total {
            resDict[bookNames[i].id] = "syncIRA" + String(i)
        }
        return resDict
    }

    func getCloudKey(name: String) -> String? {
        guard let book = book(for: name) else { return nil }
        switch book.location {
        case .bundled:
            return bundledCloudKeys[book.id]
        case .imported:
            return Self.importedCloudKey(for: book.name)
        }
    }

    static func importedCloudKey(for title: String) -> String {
        let normalizedTitle = normalizedCloudTitle(title)
        let digest = SHA256.hash(data: Data(normalizedTitle.utf8))
        let shortenedDigest = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "syncImported.\(shortenedDigest)"
    }

    private static func normalizedCloudTitle(_ title: String) -> String {
        title
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
    }
    
    func getExtentionOfName(name : String) -> String {
        return book(for: name)?.extention ?? "txt"
    }
    
    /// Persists a reading position.
    ///
    /// `forceCloudSync` publishes the value as a deliberate revision so it wins
    /// the next merge on every device. A deliberate backward jump (re-reading an
    /// earlier page) must set it, otherwise the still-larger cloud value would
    /// pull the reader forward again.
    func saveLastPage(name: String, page: Int, forceCloudSync: Bool = false) {
        if blockSaveAction {
            //print("Catch background save action")
            return
        }

        // A dedicated serial queue keeps position writes in order. On the global
        // concurrent queue two rapid scroll updates could land out of order and
        // leave an older page stored as the newest progress.
        Self.progressWriteQueue.async {
            let storageKey = self.readingStorageKey(for: name)
            self.persistLocalReadingState(name: name, page: page, storageKey: storageKey, storage: self.defaults)
            if let cloudKey = self.getCloudKey(name: name) {
                if forceCloudSync {
                    self.cloud.forceUpdateProgress(Int64(page), forKey: cloudKey)
                } else {
                    self.defaults.set(String(page), forKey: cloudKey)
                }
            }
        }

    }

    /// Persists a reading position on the calling thread.
    ///
    /// Used by lifecycle paths that must not lose the position to a pending
    /// background queue, such as entering the background or dismissing the reader.
    func saveLastPageNow(name: String, page: Int, forceCloudSync: Bool = false) {
        let storageKey = readingStorageKey(for: name)
        persistLocalReadingState(name: name, page: page, storageKey: storageKey, storage: defaults)
        if let cloudKey = getCloudKey(name: name) {
            if forceCloudSync {
                cloud.forceUpdateProgress(Int64(page), forKey: cloudKey)
            } else {
                defaults.set(String(page), forKey: cloudKey)
            }
        }
    }

    private func persistLocalReadingState(name: String, page: Int, storageKey: String, storage: UserDefaults) {
        storage.set(String(page), forKey: storageKey)
        let progress = readingFraction(page: page)
        storage.set(progress, forKey: getProgressKey(name: name))
    }

    /// Fraction of the loaded book represented by `page`, clamped to `0...1`.
    func readingFraction(page: Int) -> Double {
        ReadingProgress.fraction(page: page, contentCount: Int(splitedContentsCount))
    }

    func readCloudString(name: String) -> String? {
        if let cloudKey = self.getCloudKey(name: name) {
            return defaults.string(forKey: cloudKey)
        }
        return nil
    }
    
    func getProgressKey(name : String) -> String {
        return "\(readingStorageKey(for: name))ReadingProgress"
    }

    func readingStorageKey(for name: String) -> String {
        return progressStorageKey(for: name)
    }
    
    func readLastProgressOf(name: String) -> Double {
        let res = defaults.value(forKey: getProgressKey(name: name))
        if let val = res as? Double {
            return val
        }
        return 0.0
    }

    func getAppliedCloudOverrideKey(cloudKey: String) -> String {
        return "AppliedCloudOverride_\(cloudKey)"
    }

    /// Locally stored page, ignoring any cloud value. No side effects.
    func storedLocalPage(name: String) -> Int {
        let storageKey = readingStorageKey(for: name)
        guard let raw = defaults.value(forKey: storageKey) as? String,
              let value = Int(raw) else { return 0 }
        return value
    }

    /// Page published from the cloud, ignoring any local value. No side effects.
    func storedCloudPage(name: String) -> Int? {
        guard let cloudStr = readCloudString(name: name), let value = Int(cloudStr) else { return nil }
        return value
    }

    /// Resolves the restored reading position without writing to local or cloud
    /// storage.
    ///
    /// This is deliberately read-only. Historically this method also wrote the
    /// larger of the local and cloud values back into local storage, which is how
    /// a deliberate backward jump on one device was silently reverted by the
    /// larger progress coming from iCloud. Callers that want to move the viewport
    /// must go through `consumeExternalProgressOverride(name:)` and the reader's
    /// explicit alignment path instead.
    func readLastPage(name: String) -> Int {
        let localVal = storedLocalPage(name: name)
        guard let cloudVal = storedCloudPage(name: name) else { return localVal }
        guard let cloudKey = getCloudKey(name: name) else { return max(localVal, cloudVal) }

        let overrideRevision = cloud.overrideRevision(forKey: cloudKey)
        let appliedRevision = appliedOverrideRevision(cloudKey: cloudKey)
        if overrideRevision > appliedRevision {
            // Another device deliberately published a newer position. It wins
            // even when it is smaller, because it is the user's explicit choice.
            return cloudVal
        }

        return max(localVal, cloudVal)
    }

    func appliedOverrideRevision(cloudKey: String) -> Int64 {
        Int64(defaults.integer(forKey: getAppliedCloudOverrideKey(cloudKey: cloudKey)))
    }

    /// Whether another device published a revision this app has not applied yet.
    /// Read-only, so a caller can decide whether to move the viewport before
    /// marking the revision as applied.
    func hasFreshExternalProgressOverride(name: String) -> Bool {
        guard let cloudKey = getCloudKey(name: name) else { return false }
        return cloud.overrideRevision(forKey: cloudKey) > appliedOverrideRevision(cloudKey: cloudKey)
    }

    /// Returns a genuinely newer position published by another device, or `nil`
    /// when there is nothing new to apply. Records that the revision was applied
    /// so the same override is not replayed on every poll.
    func consumeExternalProgressOverride(name: String) -> Int? {
        guard let cloudKey = getCloudKey(name: name),
              let cloudVal = storedCloudPage(name: name) else { return nil }
        let overrideRevision = cloud.overrideRevision(forKey: cloudKey)
        guard overrideRevision > appliedOverrideRevision(cloudKey: cloudKey) else { return nil }
        defaults.set(overrideRevision, forKey: getAppliedCloudOverrideKey(cloudKey: cloudKey))
        return cloudVal
    }
    
    func readCloudPage(name : String) -> Int {
        if let cloudStr = readCloudString(name: name) {
            if let cloudVal = Int(cloudStr) {
                return cloudVal
            }
        }
        return 0
    }
    
    func calSplit(completion : @escaping(String) -> Void) {
        
        DispatchQueue.global(qos: .default).async {
            var splited: [Substring.SubSequence] = []
            var valided = false
            
            if self.sequence.suffix(1000).contains("    ") {
                splited = self.sequence.split(separator: "    ")
                if splited.count > 4000 {
                    valided = true
                }
                
            }
            
            if !valided {
                //               print("other match begin")
                if self.sequence.suffix(1000).contains("　　") {
                    splited = self.sequence.split(separator: "　　")
                    if splited.count > 4000 {
                        valided = true
                    }
                }
            }
            
            
            if !valided {
                //          print("best match begin")
                let newLineRegex = Regex {
                    Capture(CharacterClass.verticalWhitespace)
                }
                splited = self.sequence.split(separator: newLineRegex)
                if splited.count > 10000 {
                    valided = true
                }
            }
            
            DispatchQueue.main.async {
                self.splitedContents = splited
                self.splitedContentsCount = Double(self.splitedContents.count)
                self.sequence = String.SubSequence(stringLiteral: "")
                completion("T")
            }
        }
    }
    
    func loadRawContent(bookName: String, extention: String = "html") throws {
        let contentLoader = ContentLoader()
        guard let book = book(for: bookName) else { throw ContentLoader.Error.fileNotFound(name: bookName) }
        let rawContent: String
        switch book.location {
        case .bundled:
            rawContent = try contentLoader.loadBundledContent(fromFileNamed: book.name, extention: extention)
        case .imported:
            guard let record = importedStore.records().first(where: { $0.id == book.id }) else {
                throw ContentLoader.Error.fileNotFound(name: book.name)
            }
            rawContent = try contentLoader.loadContent(at: importedStore.fileURL(for: record))
        }
        self.sequence = String.SubSequence(stringLiteral: rawContent)
    }
    
    func fetchAllDatas(bookName: String, extention: String, completion : @escaping(String) -> Void) {
        CloudManager.shared.initCloudListener()
        DispatchQueue.global(qos: .userInteractive).async {
            if self.completeBookName == bookName {
                print("already load \(bookName)")
                completion("T")
            } else {
                do {
                    try self.loadRawContent(bookName: bookName, extention: extention)
                    self.calSplit() { _ in
                        self.completeBookName = bookName
                        completion("T")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.completeBookName = ""
                        self.splitedContents = []
                        self.splitedContentsCount = 1
                        GlobalSignalEmitter.cleanLastReadBook.send(params: true)
                        completion("F")
                    }
                }
            }
        }
    }
    
    func updateProgresses() {
        let books = bookNames
        DispatchQueue.global(qos: .default).async {
            for book in books {
                let progress = self.readLastProgressOf(name: book.id)
                DispatchQueue.main.async {
                    guard let index = self.bookNames.firstIndex(where: { $0.id == book.id }) else { return }
                    self.bookNames[index].progress = progress
                }
            }
        }
        
    }
}

struct ContentLoader {
    enum Error: Swift.Error {
        case fileNotFound(name: String)
        case fileDecodingFailed(name: String, Swift.Error)
    }
    
    func loadBundledContent(fromFileNamed name: String, extention : String) throws -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: extention
        ) else {
            //print("ERROR UnknownURL")
            throw Error.fileNotFound(name: name)
        }
        
        do {
            return try loadContent(at: url)
        } catch {
            throw Error.fileDecodingFailed(name: name, error)
        }
    }

    func loadContent(at url: URL) throws -> String {
        do {
            return try ImportedBookStore.decodeText(at: url)
        } catch {
            throw Error.fileDecodingFailed(name: url.lastPathComponent, error)
        }
    }
    
}


enum GlobalSignalEmitter {
    static let cleanLastReadBook = PassthroughSignalEmitter<Bool>()
}

/// 信号发送器
protocol SignalEmitter<Params> {
    associatedtype Params
    associatedtype EmitterError: Error
    
    /// 获取推送接收器
    /// - Returns:
    func publisher() -> AnyPublisher<Params, EmitterError>
    
    /// 发送数据
    /// - Parameter params:
    func send(params: Params)
}

extension SignalEmitter where Params == Void {
    func send() {
        send(params: ())
    }
}

struct PassthroughSignalEmitter<Params>: SignalEmitter {
    private let subject = PassthroughSubject<Params, Never>()
    
    func publisher() -> AnyPublisher<Params, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func send(params: Params) {
        subject.send(params)
    }
}
