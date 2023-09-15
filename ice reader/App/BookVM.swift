//
//  BookVM.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import Foundation
import Combine
import SwiftUI
import RegexBuilder

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
    // 新书必须在最后添加
    // iCloud进度最多支持前1024本书
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
        BookInfo(name:"这个剑修有点稳", extention:"txt"),
        BookInfo(name:"武侠开局奖励满级神功", extention:"txt"),
        BookInfo(name:"九鼎记", extention:"txt"),
        BookInfo(name:"教主的退休日常", extention:"txt"),
        BookInfo(name:"问道红尘", extention:"txt"),
        BookInfo(name:"精灵掌门人", extention:"txt"),
        BookInfo(name:"星门时光之主", extention:"txt"),
        BookInfo(name:"凡人修仙传", extention:"txt"),
        BookInfo(name:"遮天", extention:"txt"),
        BookInfo(name:"烂柯棋缘", extention:"txt"),
        BookInfo(name:"我的徒弟都是大反派", extention:"txt"),
        BookInfo(name:"魔临", extention:"txt"),
        BookInfo(name:"佣兵战争", extention:"txt"),
        BookInfo(name:"诸界末日在线", extention:"txt"),
        BookInfo(name:"我的治愈系游戏", extention:"txt"),
        BookInfo(name:"修真聊天群", extention:"txt"),
        BookInfo(name:"大乘期才有逆袭系统", extention:"txt"),
        BookInfo(name:"亲爱的该吃药了", extention:"txt"),
        BookInfo(name:"末日从噩梦开始", extention:"txt"),
        BookInfo(name:"全职艺术家", extention:"txt"),
        BookInfo(name:"长夜余火", extention:"txt"),
        BookInfo(name:"重生后被倒追很正常吧", extention:"txt"),
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
    var cloudBookDict: [String : String]? = nil
    
    let cloudManager = NSUbiquitousKeyValueStore.default
    
    func isLastActive(name : String) -> Bool {
        return LastReadBookName == name
    }
    
    func initCloudBookDict() {
        var resDict : [String : String] = [:]
        let total = bookNames.count > 1023 ? 1023 : bookNames.count
        for i in 0..<total {
            resDict[bookNames[i].name] = "syncIR"+String(i)
        }
        cloudBookDict = resDict
    }
    
    func getCloudKey(name: String) -> String? {
        if cloudBookDict == nil {
            initCloudBookDict()
        }
        if let dict = cloudBookDict {
            return dict[name]
        }
        return nil
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
        if blockSaveAction {
            //print("Catch background save action")
            return
        }
        
        DispatchQueue.global(qos: .userInteractive).async {
            UserDefaults.standard.set(String(page), forKey: name)
            let progress = Double(page) / self.splitedContentsCount
            UserDefaults.standard.set(progress, forKey: self.getProgressKey(name: name))
            if let cloudKey = self.getCloudKey(name: name) {
                UserDefaults.standard.set(String(page), forKey: cloudKey)
            }
        }
        
    }
    
    func readCloudString(name: String) -> String? {
        if let cloudKey = self.getCloudKey(name: name) {
           return UserDefaults.standard.string(forKey: cloudKey)
        }
        return nil
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
        
//        print("ReadLast \(readCloudString(name: name))")
        
        let res = UserDefaults.standard.value(forKey: name)
        var localVal: Int = 0
        if let val = res as? String {
            if let fin = Int(val) {
//                print("local \(name) is \(fin)")
                localVal = fin
            }
        }
        
        if let cloudStr = readCloudString(name: name) {
            if let cloudVal = Int(cloudStr) {
//                print("cloud \(name) is \(cloudVal)")
                if cloudVal > localVal {
                    localVal = cloudVal
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
    
    func loadRawContent(bookName: String, extention: String = "html") {
        let contentLoader = ContentLoader()
        let rawContent = contentLoader.loadBundledContent(fromFileNamed: bookName, extention: extention)
        self.sequence = String.SubSequence(stringLiteral: rawContent)
    }
    
    func fetchAllDatas(bookName: String, page: Int, extention: String, completion : @escaping(String) -> Void) {
        CloudManager.shared.initCloudListener()
        DispatchQueue.global(qos: .default).async {
            self.loadRawContent(bookName: bookName, extention: extention)
            self.calSplit() { _ in
                completion("T")
            }
        }
    }
    
    func updateProgresses() {
        DispatchQueue.global(qos: .default).async {
            for i in 0 ..< self.bookNames.count {
                let progress = self.readLastProgressOf(name: self.bookNames[i].name)
                DispatchQueue.main.async {
                    self.bookNames[i].progress = progress
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
    
    func loadBundledContent(fromFileNamed name: String, extention : String) -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: extention
        ) else {
            //print("ERROR UnknownURL")
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
            //print("ERROR ReadFailed")
            return ""
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
