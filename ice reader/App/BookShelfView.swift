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
    @State var isLoading = false
    @State private var pendingDeletion: BookInfo?
    @State private var deletionError: String?
    @State private var isFilesImporterPresented = false
    @State private var isImportingFiles = false
    @State private var filesImportProgress: FilesBookImportProgress?
    @State private var filesImportResult: FilesBookImportBatchResult?
    @State private var isShowingFilesImportResult = false
    
    func getImageName(index : Int) -> String {
        let remain = index % 60
        return "s\(remain)"
    }
    
    @ViewBuilder
    private func bookCell(book: BookInfo, index : Int) -> some View {
        
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(book.name)
                    .font(.system(size: 16, weight: .medium))
                    .minimumScaleFactor(0.4)
                    .foregroundColor(vm.isLastActive(name: book.id) ? Color.blue : Color("BookColor"))
                    .padding(.leading, 64)
                    .frame(height: 56)
                    .padding(.top, 4)
            }
            
            PerCentBarView(percent: vm.bookNames[index].progress, backColor: Color.gray.opacity(0.05), foreColor: Color.init("GoldenC").opacity(0.2))
                .padding(.bottom, -4)
            
        }
        .overlay(alignment: .leading) {
            Image(getImageName(index: index))
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8.0))
        }
        
    }
    
    func gotoLastReadBook() {
        if !LastReadBookName.isEmpty {
            print("Go to last read book \(LastReadBookName)")
            guard let book = vm.book(for: LastReadBookName) else {
                LastReadBookName = ""
                return
            }
            isLoading = true
            vm.fetchAllDatas(bookName: book.id, extention: book.extention) { result in
                isLoading = false
                if result == "T" {
                    navPath.append(book.id)
                }
            }
        }
    }

    private var firstImportGuide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("还没有导入小说", systemImage: "books.vertical")
                .font(.headline)

            Text("可以直接从系统“文件”中选择多本小说；如果小说在电脑上，也可以通过同一 Wi-Fi 用浏览器批量上传。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isFilesImporterPresented = true
            } label: {
                Label("从文件 App 导入", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImportingFiles)
            .accessibilityLabel("从系统文件 App 选择小说")

            NavigationLink {
                BrowserUploadView(bookVM: vm)
            } label: {
                Label("从局域网导入", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("打开浏览器上传并接收小说")
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    
    var body: some View {
        NavigationStack(path: $navPath) {
            GeometryReader  { proxy in
                VStack {
                    let titleImgStr = String(format: "s%d", Int.random(in: 1...19))
                    HStack {
                        Image(titleImgStr)
                            .resizable()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 12.0))
                        Text("今天想读哪本书啊？")
                            .font(.system(size: 25, weight: .bold))
                    }

                    if isImportingFiles, let progress = filesImportProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                ProgressView()
                                Text(progress.currentFilename.map { "正在导入《\($0)》" } ?? "正在完成导入…")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            ProgressView(value: progress.fractionCompleted)
                            Text("已处理 \(progress.completedCount) / \(progress.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    
                    Spacer()
                    
                    if isLoading {
                        LoadingView()
                    } else {
                        ScrollView {
                            let gridCount = proxy.size.width > 780 ? 5 : 3
                            let gridItems: [GridItem] = .init(repeating: GridItem(spacing: 10), count: gridCount)
                            LazyVGrid(columns: gridItems, alignment: .center, spacing: 10) {
                                ForEach(0 ..< vm.bookNames.count, id: \.self) { index in
                                    let book = vm.bookNames[index]
                                    
                                    NavigationLink() {
                                        BookMainView(bookName: book.id, bookExtention: book.extention, vm: vm)
                                            .toolbar(.hidden, for: .tabBar)
                                        
                                    } label: {
                                        bookCell(book: book, index: index)
                                            .padding(4)
                                            .frame(height: 65)
                                            .frame(maxWidth: .infinity)
                                            .background {
                                                Color("BookColor").opacity(0.1)
                                                    .cornerRadius(8)
                                            }
                                        
                                    }
                                    .contextMenu {
                                        if case .imported = book.location {
                                            Button("删除本机小说", role: .destructive) { pendingDeletion = book }
                                        }
                                    }
                                    
                                }
                            }
                            .padding(.top, 20)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 6)

                            if !vm.hasImportedBooks {
                                firstImportGuide
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 20)
                            }
                            
                        }
                    }
                    
                }
                .navigationDestination(for: String.self) { i in
                    let extention = vm.getExtentionOfName(name: i)
                    BookMainView(bookName: i, bookExtention: extention, vm: vm)
                        .toolbar(.hidden, for: .tabBar)
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
                    if !navPath.isEmpty {
                        navPath.removeLast()
                    }
                    vm.LastReadBookName = ""
                }
                .confirmationDialog(
                    "删除《\(pendingDeletion?.name ?? "")》？",
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("删除本机小说", role: .destructive) {
                        if let book = pendingDeletion {
                            do { try vm.deleteImportedBook(id: book.id) }
                            catch { deletionError = error.localizedDescription }
                        }
                        pendingDeletion = nil
                    }
                    Button("取消", role: .cancel) { pendingDeletion = nil }
                } message: {
                    Text("只删除这台设备上的小说文件；长按已导入的书籍可再次使用此操作。")
                }
                .alert("删除失败", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                    Button("好") { deletionError = nil }
                } message: { Text(deletionError ?? "未知错误") }
                .alert("文件导入结果", isPresented: $isShowingFilesImportResult) {
                    Button("好") { filesImportResult = nil }
                } message: {
                    Text(filesImportSummary)
                }
                .fileImporter(
                    isPresented: $isFilesImporterPresented,
                    allowedContentTypes: FilesBookImportCoordinator.supportedContentTypes,
                    allowsMultipleSelection: true
                ) { result in
                    handleFilesSelection(result)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        NavigationLink {
                            LocalBookManagementView(bookVM: vm)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "books.vertical")
                                Text("管理")
                            }
                        }
                        .accessibilityLabel("管理本机小说")

                        Menu {
                            Button {
                                isFilesImporterPresented = true
                            } label: {
                                Label("从文件 App 导入", systemImage: "folder")
                            }

                            NavigationLink {
                                BrowserUploadView(bookVM: vm)
                            } label: {
                                Label("从局域网导入", systemImage: "wifi")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("导入小说")
                            }
                        }
                        .disabled(isImportingFiles)
                        .accessibilityLabel("导入小说")
                    }
                }
                
            }
            
        }
        
    }

    private var filesImportSummary: String {
        guard let result = filesImportResult else { return "没有选择需要导入的文件。" }
        var lines = [
            "新导入 \(result.importedCount) 本，覆盖 \(result.replacedCount) 本，跳过 \(result.skippedCount) 本，失败 \(result.failedCount) 本。"
        ]
        let issues = result.items.filter { $0.outcome == .skipped || $0.outcome == .failed }
        lines.append(contentsOf: issues.prefix(8).map { "\($0.filename)：\($0.detail)" })
        if issues.count > 8 {
            lines.append("另有 \(issues.count - 8) 个文件未列出。")
        }
        return lines.joined(separator: "\n")
    }

    private func handleFilesSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty, !isImportingFiles else { return }
            isImportingFiles = true
            filesImportProgress = FilesBookImportProgress(completedCount: 0, totalCount: urls.count, currentFilename: urls.first?.lastPathComponent)
            Task {
                let batch = await vm.importFiles(at: urls) { progress in
                    filesImportProgress = progress
                }
                filesImportResult = batch
                filesImportProgress = nil
                isImportingFiles = false
                isShowingFilesImportResult = true
            }
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            filesImportResult = FilesBookImportBatchResult(items: [
                FilesBookImportItemResult(filename: "文件选择", outcome: .failed, detail: "无法打开文件选择器，请重试")
            ])
            isShowingFilesImportResult = true
        }
    }
}
