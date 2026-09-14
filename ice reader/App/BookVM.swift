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

class BookVM: ObservableObject {
    private let importedStore: ImportedBookStore
    private let bundledBookCount = 1
    @Published var datas : [String]?
    // 正式小说通过浏览器上传；App 只内置一个可读占位样例。
    @Published var bookNames:[BookInfo] = [
        BookInfo(name:"样例占位", extention:"txt"),
    ]
    
    @Published var splitedContents: Array<Substring> = []
    @Published var splitedContentsCount: Double = 1.0
    private var sequence: String.SubSequence = String.SubSequence(stringLiteral: "")
    
    let jumpToIndexSig = PassthroughSignalEmitter<Int>()
    let quickJumpToIndexSig = PassthroughSignalEmitter<Int>()
    let cleanLastReadBook = PassthroughSignalEmitter<Bool>()
    @AppStorage("LastReadBookName")
    var LastReadBookName = ""
    var blockSaveAction = false
    
    var completeBookName = ""
    var cloudBookDict: [String : String]? = nil
    
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

    init(importedStore: ImportedBookStore = .shared) {
        self.importedStore = importedStore
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
    
    func initCloudBookDict() {
        var resDict : [String : String] = [:]
        let total = min(bundledBookCount, bookNames.count)
        for i in 0..<total {
            resDict[bookNames[i].id] = "syncIRA"+String(i)
        }
        cloudBookDict = resDict
    }
    
    func getCloudKey(name: String) -> String? {
        if cloudBookDict == nil {
            initCloudBookDict()
        }
        guard let book = book(for: name) else { return nil }
        switch book.location {
        case .bundled:
            return cloudBookDict?[book.id]
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
    
    func saveLastPage(name: String, page: Int, forceCloudSync: Bool = false) {
        if blockSaveAction {
            //print("Catch background save action")
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            let storageKey = self.readingStorageKey(for: name)
            self.persistLocalReadingState(name: name, page: page, storageKey: storageKey)
            if let cloudKey = self.getCloudKey(name: name) {
                if forceCloudSync {
                    MKiCloudSync.forceUpdateProgress(Int64(page), forKey: cloudKey)
                } else {
                    UserDefaults.standard.set(String(page), forKey: cloudKey)
                }
            }
        }
        
    }

    private func persistLocalReadingState(name: String, page: Int, storageKey: String) {
        UserDefaults.standard.set(String(page), forKey: storageKey)
        let progress = splitedContentsCount > 0 ? Double(page) / splitedContentsCount : 0
        UserDefaults.standard.set(progress, forKey: getProgressKey(name: name))
    }
    
    func readCloudString(name: String) -> String? {
        if let cloudKey = self.getCloudKey(name: name) {
            return UserDefaults.standard.string(forKey: cloudKey)
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
        let res = UserDefaults.standard.value(forKey: getProgressKey(name: name))
        if let val = res as? Double {
            return val
        }
        return 0.0
    }

    func getAppliedCloudOverrideKey(cloudKey: String) -> String {
        return "AppliedCloudOverride_\(cloudKey)"
    }
    
    func readLastPage(name: String) -> Int {
        
        //        print("ReadLast \(readCloudString(name: name))")
        
        let storageKey = readingStorageKey(for: name)
        let res = UserDefaults.standard.value(forKey: storageKey)
        var localVal: Int = 0
        if let val = res as? String {
            if let fin = Int(val) {
                //                print("local \(name) is \(fin)")
                localVal = fin
            }
        }
        
        if let cloudKey = getCloudKey(name: name),
           let cloudStr = readCloudString(name: name) {
            if let cloudVal = Int(cloudStr) {
                let overrideRevision = MKiCloudSync.overrideRevision(forKey: cloudKey)
                let appliedOverrideKey = getAppliedCloudOverrideKey(cloudKey: cloudKey)
                let appliedRevision = Int64(UserDefaults.standard.integer(forKey: appliedOverrideKey))

                if overrideRevision > appliedRevision {
                    persistLocalReadingState(name: name, page: cloudVal, storageKey: storageKey)
                    UserDefaults.standard.set(overrideRevision, forKey: appliedOverrideKey)
                    return cloudVal
                }

                //                print("cloud \(name) is \(cloudVal)")
                if cloudVal >= localVal {
                    localVal = cloudVal
                    persistLocalReadingState(name: name, page: cloudVal, storageKey: storageKey)
                }
            }
        }
        
        return localVal
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
