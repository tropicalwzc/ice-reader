//
//  BookShelfView.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

struct BookShelfView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var navPath = NavigationPath()
    @StateObject var vm : BookVM = BookVM()
    @AppStorage("LastReadBookName")
    var LastReadBookName = ""
    @State var isFirstLaunch = true
    
    func getImageName(index : Int) -> String {
        let remain = index % 35
        return "s\(remain)"
    }
    
    @ViewBuilder
    private func bookCell(name : String, index : Int) -> some View {
        
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(name)
                    .font(.system(size: 16, weight: .medium))
                    .minimumScaleFactor(0.4)
                    .foregroundColor(vm.isLastActive(name: name) ? Color.blue : Color.black)
                    .padding(.leading, 60)
                    .frame(height: 56)
                    .padding(.top, 4)
            }

            PerCentBarView(percent: vm.bookNames[index].progress, backColor: Color.gray.opacity(0.05), foreColor: Color.init("GoldenC").opacity(0.2))
                .padding(.bottom, -4)
    
        }
        .overlay(alignment: .leading) {
            Image(getImageName(index: index))
                .resizable()
                .frame(width: 48, height: 48)
        }
        
    }
    
    func gotoLastReadBook() {
        if !LastReadBookName.isEmpty {
            navPath.append(LastReadBookName)
        }
    }
    
    var body: some View {
        NavigationStack(path: $navPath) {
            GeometryReader  { proxy in
                VStack {
                    
                    HStack {
                        Image("s5")
                            .resizable()
                            .frame(width: 180, height: 180)
                        Text("今天想读哪本书啊？")
                            .font(.system(size: 25, weight: .medium))
                    }

                    
                    Spacer()
                    
                    ScrollView {
                        let gridCount = proxy.size.width > 780 ? 5 : 3
                        let gridItems: [GridItem] = .init(repeating: GridItem(spacing: 10), count: gridCount)
                        LazyVGrid(columns: gridItems, alignment: .center, spacing: 10) {
                            ForEach(0 ..< vm.bookNames.count, id: \.self) { index in
                                let name = vm.bookNames[index].name
                                let extention = vm.bookNames[index].extention

                                NavigationLink() {
                                    BookMainView(bookName: name, bookExtention: extention, vm: vm)
                                        .toolbar(.hidden, for: .tabBar)
                                        
                                } label: {
                                    bookCell(name: name, index: index)
                                        .padding(4)
                                        .frame(width: proxy.size.width / CGFloat(gridCount) - 10, height: 65)
                                        .background {
                                            Color.black.opacity(0.1)
                                                .cornerRadius(8)
                                        }

                                }
                                .onAppear {
                                    print("www \(proxy.size.width)")
                                }
                                .navigationDestination(for: String.self) { i in
                                    let extention = vm.getExtentionOfName(name: i)
                                    BookMainView(bookName: i, bookExtention: extention, vm: vm)
                                        .toolbar(.hidden, for: .tabBar)
                                }
                            }
                        }
                        .padding(.top, 20)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 6)
                    }
                }
                .onAppear {
                    if isFirstLaunch {
                        isFirstLaunch = false
                        gotoLastReadBook()
                    } else {
                        vm.updateProgresses()
                    }
                }
                .onReceive(GlobalSignalEmitter.cleanLastReadBook.publisher()) { _ in
                    navPath.removeLast()
                    vm.LastReadBookName = ""
                }

            }
 
        }

    }
}


