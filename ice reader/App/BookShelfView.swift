//
//  BookShelfView.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

struct BookShelfView: View {
    
    @Environment(\.managedObjectContext) private var viewContext

    @StateObject var vm : BookVM = BookVM()

    @ViewBuilder
    private func bookCell(name : String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 18, weight: .heavy))
                .minimumScaleFactor(0.4)

        }
    }

    var body: some View {
        NavigationView {
            GeometryReader  { proxy in
                VStack {
                    
                    Spacer()
                    
                    ScrollView {
                        let gridItems: [GridItem] = .init(repeating: GridItem(spacing: 16), count: 3)
                        LazyVGrid(columns: gridItems, alignment: .center, spacing: 16) {
                            ForEach(vm.bookNames, id: \.name) { name, extention in
                                NavigationLink {
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
                            }
                        }
                        .padding(.top, 200)
                        .padding(.vertical, 16)
                    }
                }
            }
 
        }

    }
}


