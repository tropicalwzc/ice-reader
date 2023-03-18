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

    @ViewBuilder
    private func bookCell(name : String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 18, weight: .heavy))
                .minimumScaleFactor(0.4)

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
                    
                    Spacer()
                    
                    ScrollView {
                        let gridItems: [GridItem] = .init(repeating: GridItem(spacing: 16), count: 3)
                        LazyVGrid(columns: gridItems, alignment: .center, spacing: 16) {
                            ForEach(0 ..< vm.bookNames.count, id: \.self) { index in
                                let name = vm.bookNames[index].name
                                let extention = vm.bookNames[index].extention

                                NavigationLink() {
                                    BookMainView(bookName: name, bookExtention: extention, vm: vm)
                                        .toolbar(.hidden, for: .tabBar)
                                        
                                } label: {
                                    bookCell(name: name)
                                        .padding(16)
                                        .frame(width: proxy.size.width / 3 - 16, height: 80)
                                        .background {
                                            Color.black.opacity(0.1)
                                                .cornerRadius(8)
                                        }

                                }
                                .navigationDestination(for: String.self) { i in
                                    let extention = vm.getExtentionOfName(name: i)
                                    BookMainView(bookName: i, bookExtention: extention, vm: vm)
                                        .toolbar(.hidden, for: .tabBar)
                                }
                            }
                        }
                        .padding(.top, 200)
                        .padding(.vertical, 16)
                    }
                }
                .onAppear {
                    if isFirstLaunch {
                        isFirstLaunch = false
                        gotoLastReadBook()
                    }
                }
            }
 
        }

    }
}


