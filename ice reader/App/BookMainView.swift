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
    
    func submit() {
        print("You entered \(index)")
        if let nextIndex = Int(index) {
            if nextIndex < vm.splitedContents.count && nextIndex >= 0 {
                GlobalSignalEmitter.jumpToIndexSig.send(params: nextIndex)
                page = nextIndex
            }
        }
    }
    
    func readLastPage() {
        page = vm.readLastPage(name: bookName)
        GlobalSignalEmitter.jumpToIndexSig.send(params: page)
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
                    LazyVStack(spacing: 1) {
                        ForEach(0 ..< vm.splitedContents.count, id: \.self) { index in
                            ZStack(alignment: .topLeading) {
                                
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                
                                Text("\(index)")
                                    .font(.system(size: 12, weight: .thin))
                                    .foregroundColor(.black.opacity(0.6))
                                    .id(index)
                                    .padding(.leading, 8)
                                    .padding(.top, 12)
                                    .italic()
                                    .onDisappear {
                                        if firstJumpFin {
                                            print("may disappear \(index)")
                                            if index > page + 30 {
                                                page = index
                                                vm.saveLastPage(name: bookName, page: page)
                                            }
                                        }

                                    }

                                Text(vm.splitedContents[index])
                                    .font(.system(size: 24, weight: .medium))
                                    .padding(.leading, 4)
                                    .padding(.trailing, 2)
                                    .lineSpacing(5)
                                    .multilineTextAlignment(.leading)
                                    .onTapGesture {
                                        page = index
                                        vm.saveLastPage(name: bookName, page: page)
                                    }
                                    .foregroundColor(Color.init(red: 0.38, green: 0.39, blue: 0.4))
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
                    .onReceive(GlobalSignalEmitter.jumpToIndexSig.publisher()) { nextIndex in
                        
                        print("try to scroll to \(nextIndex)")
                        withAnimation {
                            proxy.scrollTo(nextIndex, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: {
                            firstJumpFin = true
                        })
                        page = nextIndex
                        vm.saveLastPage(name: bookName, page: page)
                    }
  
                }
            }

        }
        .onAppear {
            vm.fetchAllDatas(bookName: bookName, page: page, extention: bookExtention) { res in
                full = res
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

    }
}

