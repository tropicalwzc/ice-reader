import SwiftUI

struct LocalBookManagementView: View {
    @ObservedObject var bookVM: BookVM
    @State private var pendingDeletion: ImportedBookRecord?
    @State private var deletionError: String?

    var body: some View {
        Group {
            if bookVM.importedBookRecords.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("还没有导入的小说").font(.headline)
                    Text("可返回书架，点击“从局域网导入”从电脑浏览器上传。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(32)
            } else {
                List {
                    Section("本机小说（\(bookVM.importedBookRecords.count)）") {
                        ForEach(bookVM.importedBookRecords) { record in
                            bookRow(record)
                                .swipeActions {
                                    Button("删除", role: .destructive) { pendingDeletion = record }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("管理本机小说")
        .confirmationDialog(
            "删除《\(pendingDeletion?.title ?? "")》？",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除本机小说", role: .destructive) {
                if let record = pendingDeletion {
                    do { try bookVM.deleteImportedBook(id: record.id) }
                    catch { deletionError = error.localizedDescription }
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("这会删除 iPhone 或 iPad 上的小说文件，不会影响电脑上的源文件。")
        }
        .alert("删除失败", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("好") { deletionError = nil }
        } message: {
            Text(deletionError ?? "未知错误")
        }
    }

    private func bookRow(_ record: ImportedBookRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                Text("\(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file)) · \(sourceDescription(record.source))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { pendingDeletion = record } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .accessibilityLabel("删除《\(record.title)》")
        }
    }

    private func sourceDescription(_ source: ImportedBookSource) -> String {
        switch source {
        case .browserUpload: return "浏览器上传"
        case .legacyLAN: return "旧版局域网导入"
        case .filesApp: return "文件 App 导入"
        }
    }
}
