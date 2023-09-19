//
//  BookMainView.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

struct BookMainView: View {
    let bookName : String
    let bookExtention : String
    @ObservedObject var vm : BookVM
    
    @State var smallHeadpage : Int = 0
    @State var page : Int = 0
    @State var maximumPage : Int = 0
    @State private var showingAlert = false
    @State var index : String = ""
    @State private var firstJumpFin = false
    @State var hiddenNav : Bool = true
    @State var isFirstAppear = true
    @State var loadFinished = true
    
    let pageSize : Int = UIDevice.current.userInterfaceIdiom == .pad ? 20 : 10
    
    func submit() {
        //print("You entered \(index)")
        if let nextIndex = Int(index) {
            if nextIndex < vm.splitedContents.count  {
                if nextIndex >= smallHeadpage {
                    page = nextIndex
                    self.stripSmallPage()
                    vm.jumpToIndexSig.send(params: nextIndex)
                    self.vm.saveLastPage(name: bookName, page: page)
                } else {
                    var small = nextIndex - pageSize
                    if small < 0 {
                        small = 0
                    }
                    smallHeadpage = small
                    if nextIndex >= smallHeadpage {
                        page = nextIndex
                        self.stripSmallPage()
                        vm.jumpToIndexSig.send(params: nextIndex)
                        self.vm.saveLastPage(name: bookName, page: page)
                    }
                }
                
            }
        }
    }
    
    func stripSmallPage() {
        var small = page - pageSize
        if small < 0 {
            small = 0
        }
        smallHeadpage = small
    }
    
    func readLastPage() {
        page = vm.readLastPage(name: bookName)
        self.stripSmallPage()
        vm.jumpToIndexSig.send(params: page)
        vm.LastReadBookName = bookName
    }
    
    func pureBookName() -> String {
        let suq = bookName.split(separator: ".")
        let ff = suq.first ?? ""
        return String(ff)
    }
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    let total = (page + pageSize < vm.splitedContents.count ? page + pageSize : vm.splitedContents.count)
                    if self.loadFinished && smallHeadpage < total {
                        
                        LazyVStack(spacing: 5) {
                            ForEach(smallHeadpage ..< total, id: \.self) { index in
                                ZStack(alignment: .topLeading) {
                                    
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    
                                    HStack {
                                        Spacer()
                                        Text("\(index)")
                                            .font(.system(size: 5, weight: .bold))
                                            .foregroundColor(Color.gray.opacity(0.01))
                                            .id(index)
                                            .padding(.trailing, 3)
                                            .padding(.top, 1)
                                    }.onAppear {
                                        if index == page + pageSize - 1 {
                                            //print("Scroll to tail , auto page")
                                            page = index
                                            vm.saveLastPage(name: bookName, page: page)
                                        }
                                    }
                                    
                                    
                                    Text(vm.splitedContents[index])
                                        .font(.system(size: 25, weight: .regular))
                                        .padding(.horizontal, 6)
                                        .lineSpacing(5)
                                        .tracking(1)
                                        .multilineTextAlignment(.leading)
                                        .onTapGesture {
                                            if hiddenNav == true {
                                                hiddenNav = false
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                                    hiddenNav = true
                                                }
                                                page = index
                                                vm.saveLastPage(name: bookName, page: page)
                                            }
                                        }
                                        .foregroundColor(Color.init("BookColor"))
                                        .padding(.top, 8)
                                }
                            }
                        }
                        .onReceive(vm.jumpToIndexSig.publisher()) { nextIndex in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
                                //print("try to scroll to \(nextIndex)")
                                withAnimation {
                                    proxy.scrollTo(nextIndex, anchor: .top)
                                }
                            })
                        }
                        .onReceive(vm.quickJumpToIndexSig.publisher()) { nextIndex in
                            proxy.scrollTo(nextIndex, anchor: .top)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                            
                        }
                    } else {
                        LoadingView()
                    }
                    
                    
                }
                .padding(.top, 0.5)
            }
            
        }
        .onAppear {
            self.loadFinished = false
            
            vm.fetchAllDatas(bookName: bookName, page: page, extention: bookExtention) { res in
                //print("reload all datas")
                DispatchQueue.main.async {
                    self.loadFinished = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                    readLastPage()
                })
                
                if isFirstAppear {
                    isFirstAppear = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: {
                        recursiveCheck(remain: 5)
                    })
                }
            }
        }
        
        .navigationTitle("\(pureBookName()) \(page)")
        .alert("跳转到哪一页?", isPresented: $showingAlert) {
            TextField("跳转到哪一页?", text: $index).keyboardType(UIKeyboardType.decimalPad)
            Button("OK", action: submit)
        } message: {
            Text("(总共\(vm.splitedContents.count)页)")
        }
        .toolbar {
            Button {
                index = "\(page)"
                showingAlert = true
            } label: {
                Text("跳转")
            }
        }
        .statusBarHidden(hiddenNav)
        .navigationBarHidden(hiddenNav)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            vm.blockSaveAction = true
            
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            vm.blockSaveAction = false
            if !checkCloudUpdateIfNeed() {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    vm.jumpToIndexSig.send(params: page)
                }
                recursiveCheck(remain: 10)
            }
        }
        
    }
    
    func recursiveCheck(remain: Int) {
        if remain < 0 {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: {
            let res = checkCloudUpdateIfNeed()
            if !res {
                recursiveCheck(remain: remain - 1)
            }
        })
    }
    
    func checkCloudUpdateIfNeed() -> Bool {
        let cloudPage = vm.readCloudPage(name: bookName)
        print("cloud \(cloudPage) local \(page)")
        if cloudPage > page {
            print("start cloud jump")
            page = cloudPage
            index = "\(page)"
            submit()
            return true
        }
        return false
    }
}


