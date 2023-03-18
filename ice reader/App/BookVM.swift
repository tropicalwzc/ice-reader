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
        self.progress = 0.0
    }
    
    var name : String
    var extention: String
    var active : Bool
    var progress : Double
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
        BookInfo(name:"我的属性修行人生", extention:"txt"),
        BookInfo(name:"一世之尊", extention:"txt"),
        BookInfo(name:"吞噬星空", extention:"txt"),
        BookInfo(name:"惊悚乐园", extention:"txt"),
        BookInfo(name:"我师兄实在是太稳健了", extention:"txt"),
        BookInfo(name:"我有一座冒险屋", extention:"txt"),
        BookInfo(name:"斗破苍穹", extention:"txt"),
        BookInfo(name:"大王饶命", extention:"txt"),
        BookInfo(name:"超神机械师", extention:"html"),
        BookInfo(name:"圣墟", extention:"txt"),
        BookInfo(name:"牧神记", extention:"txt"),
        BookInfo(name:"轮回乐园", extention:"txt"),
        BookInfo(name:"完美世界", extention:"txt"),
        BookInfo(name:"全球高武", extention:"txt"),
        BookInfo(name:"伏天氏", extention:"txt"),
        BookInfo(name:"从红月开始", extention:"txt"),
        BookInfo(name:"亏成首富从游戏开始", extention:"txt"),
        BookInfo(name:"第一序列", extention:"txt"),
        BookInfo(name:"深夜书屋", extention:"txt"),
        BookInfo(name:"一念永恒", extention:"txt"),
        BookInfo(name:"奥术神座", extention:"txt"),
        BookInfo(name:"全职高手", extention:"txt"),
        BookInfo(name:"异常生物见闻录", extention:"txt"),
    ]
    
    @Published var fullContents: [String] = []
    @Published var splitedContents: Array<Substring> = []
    @Published var splitedContentsCount: Double = 1.0
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
        let progress = Double(page) / splitedContentsCount
        UserDefaults.standard.set(progress, forKey: getProgressKey(name: name))
        print("after save rr is \(rr)")
    }
    
    func getProgressKey(name : String) -> String {
        return "\(name)ReadingProgress"
    }
    
    func readLastProgressOf(name: String) -> Double {
        let res = UserDefaults.standard.value(forKey: getProgressKey(name: name))
        if let val = res as? Double {
            return val
        }
        return 0.0
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
            self.splitedContentsCount = Double(self.splitedContents.count)
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
    
    func updateProgresses() {
        for i in 0 ..< bookNames.count {
            let progress = readLastProgressOf(name: bookNames[i].name)
            bookNames[i].progress = progress
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
            GlobalSignalEmitter.cleanLastReadBook.send(params: true)
            return "UnknownURL"
        }
        
        do {
            var data = try? String(contentsOf: url, encoding: String.Encoding.utf8)
            if data == nil {
                let encode = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                let encoding = String.Encoding.init(rawValue: encode)
                data = try String(contentsOf: url, encoding: encoding)
            }
            return data ?? ""
        } catch {
            GlobalSignalEmitter.cleanLastReadBook.send(params: true)
            print("ERROR ReadFailed")
            return ""
        }
    }

}


enum GlobalSignalEmitter {
    static let jumpToIndexSig = PassthroughSignalEmitter<Int>()
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
