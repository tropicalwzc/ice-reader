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
    @State var full : String = ""
    
    @State var page : Int = 0
    @State var maximumPage : Int = 0
    @State private var showingAlert = false
    @State var index : String = ""
    @State private var firstJumpFin = false
    @State var hiddenNav : Bool = true

    @State var isFirstAppear = true
    func submit() {
        print("You entered \(index)")
        if let nextIndex = Int(index) {
            if nextIndex < vm.splitedContents.count && nextIndex >= 0 {
                vm.jumpToIndexSig.send(params: nextIndex)
                page = nextIndex
                self.vm.saveLastPage(name: bookName, page: page)
            }
        }
    }
    
    func readLastPage() {
        page = vm.readLastPage(name: bookName)
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
                    LazyVStack(spacing: 5) {
                        ForEach(0 ..< vm.splitedContents.count, id: \.self) { index in
                            ZStack(alignment: .topLeading) {
                                
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                HStack {
                                    Spacer()
                                    Text("\(index)")
                                        .font(.system(size: 12, weight: .thin))
                                        .foregroundColor(.black.opacity(0.6))
                                        .id(index)
                                        .padding(.trailing, 8)
                                        .padding(.top, 12)
                                        .italic()
                                }


                                Text(vm.splitedContents[index])
                                    .font(.system(size: 25, weight: .regular))
                                    .padding(.horizontal, 6)
                                    .lineSpacing(5)
                                    .tracking(1)
                                    .multilineTextAlignment(.leading)
                                    .onTapGesture {
                                        hiddenNav = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                            hiddenNav = true
                                        }
                                        page = index
                                        vm.saveLastPage(name: bookName, page: page)
                                    }
                                    .foregroundColor(Color.init(red: 0.2, green: 0.22, blue: 0.25))
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .foregroundColor(Color.gray.opacity(0.02))
                                RoundedRectangle(cornerRadius: 16)
                                    .foregroundColor(Color.white)
                                    .padding(2)
                            }

                        }
                    }
                    .onReceive(vm.jumpToIndexSig.publisher()) { nextIndex in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                            print("try to scroll to \(nextIndex)")
                            withAnimation {
                                proxy.scrollTo(nextIndex, anchor: .top)
                            }
                        })
                    }
                    .onReceive(vm.quickJumpToIndexSig.publisher()) { nextIndex in
                        proxy.scrollTo(nextIndex, anchor: .top)
                    }
                }
                .padding(.top, 0.5)
            }

        }
        .onAppear {
            vm.fetchAllDatas(bookName: bookName, page: page, extention: bookExtention) { res in
                full = res
                print("reload all datas")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                    readLastPage()
                })
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
                showingAlert = true
            } label: {
                Text("跳转")
            }
        }
        .navigationBarHidden(hiddenNav)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                            vm.blockSaveAction = true
                            print("recc exit \(page)")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            vm.blockSaveAction = false
                            print("recc enter \(page)")
                            vm.quickJumpToIndexSig.send(params: page)
                            vm.jumpToIndexSig.send(params: page)
                        }

    }
}


