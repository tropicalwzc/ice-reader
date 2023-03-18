//
//  BookVM.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import Foundation
import Combine
import SwiftUI

struct BookInfo {
    internal init(name: String, extention: String, active: Bool = false) {
        self.name = name
        self.extention = extention
        self.active = active
    }
    
    var name : String
    var extention: String
    var active : Bool
}

class BookVM: ObservableObject {
    @Published var datas : [String]?
    @Published var bookNames:[BookInfo] = [
        BookInfo(name:"天启预报", extention:"txt"),
        BookInfo(name:"重生之似水流年", extention:"txt"),
        BookInfo(name:"希灵帝国", extention:"txt"),
        BookInfo(name:"深空彼岸", extention:"txt"),
        BookInfo(name:"才不是魔女", extention:"txt"),
        BookInfo(name:"我真没想重生啊", extention:"txt"),
        BookInfo(name:"夜的命名术", extention:"txt"),
        BookInfo(name:"大奉打更人", extention:"txt"),
        BookInfo(name:"不科学御兽", extention:"txt"),
        BookInfo(name:"黎明之剑", extention:"html"),
        BookInfo(name:"万道龙皇", extention:"txt"),
        BookInfo(name:"诡秘之主", extention:"txt"),
        BookInfo(name:"万族之劫", extention:"txt"),
        BookInfo(name:"我打造了旧日支配者神话", extention:"txt"),
        BookInfo(name:"镇妖博物馆", extention:"html"),
    ]
    
    @Published var fullContents: [String] = []
    @Published var splitedContents: Array<Substring> = []
    @Published var sequence: String.SubSequence = String.SubSequence(stringLiteral: "")
    
    @AppStorage("LastReadBookName")
    var LastReadBookName = ""
    
    func isLastActive(name : String) -> Bool {
       return LastReadBookName == name
    }
    
    func getExtentionOfName(name : String) -> String {
        for info in bookNames {
            if info.name == name {
                return info.extention
            }
        }
        return "txt"
    }
    
    func saveLastPage(name: String, page: Int) {
        UserDefaults.standard.set(String(page), forKey: name)
        let rr = readLastPage(name: name)
        print("after save rr is \(rr)")
    }
    
    func readLastPage(name: String) -> Int {
        let res = UserDefaults.standard.value(forKey: name)
        if let val = res as? String {
            print("val is \(String(describing: res))")
            if let fin = Int(val) {
                print("fin is \(String(describing: res))")
                return fin
            }
        }
        return 0
    }
    
    func calSplit(completion : @escaping(String) -> Void) {

        DispatchQueue.main.async {
            self.splitedContents = self.sequence.split(separator: "。")
            completion("T")
        }

    }
    
    func loadRawContent(bookName: String, extention: String = "html") {
        let contentLoader = ContentLoader()
        let rawContent = contentLoader.loadBundledContent(fromFileNamed: bookName, extention: extention)
        sequence = String.SubSequence(stringLiteral: rawContent)
    }
    
    func fetchAllDatas(bookName: String, page: Int, extention: String, completion : @escaping(String) -> Void) {
        loadRawContent(bookName: bookName, extention: extention)
        self.calSplit() { _ in
            completion("T")
        }
    }
}

struct ContentLoader {
    enum Error: Swift.Error {
        case fileNotFound(name: String)
        case fileDecodingFailed(name: String, Swift.Error)
    }
    
    func loadBundledContent(fromFileNamed name: String, extention : String) -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: extention
        ) else {
            print("ERROR UnknownURL")
            return "UnknownURL"
        }
        
        do {
            let data = try String(contentsOf: url, encoding: String.Encoding.utf8)
            return data
        } catch {
            print("ERROR ReadFailed")
            return ""
        }
    }

}


enum GlobalSignalEmitter {
    static let jumpToIndexSig = PassthroughSignalEmitter<Int>()
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
