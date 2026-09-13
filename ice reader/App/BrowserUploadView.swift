import SwiftUI
import UIKit

protocol BrowserUploadIdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: BrowserUploadIdleTimerControlling {}

@MainActor
final class BrowserUploadViewModel: ObservableObject {
    enum PresentationState: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var state: PresentationState = .stopped
    @Published private(set) var urls: [URL] = []
    @Published private(set) var code = "------"
    @Published private(set) var expiresAt = Date()
    @Published private(set) var results: [BrowserUploadResult] = []

    var primaryURLs: [URL] {
        urls.filter { $0.host?.hasPrefix("10.") != true }
    }

    var otherURLs: [URL] {
        urls.filter { $0.host?.hasPrefix("10.") == true }
    }

    private let server: BrowserUploadServing
    private let bookVM: BookVM
    private let addressProvider: () -> [String]
    private let idleTimer: BrowserUploadIdleTimerControlling
    private var previousIdleTimerValue = false
    private var isVisible = false

    init(
        bookVM: BookVM,
        server: BrowserUploadServing? = nil,
        addressProvider: @escaping () -> [String] = PrivateIPv4AddressProvider.addresses,
        idleTimer: BrowserUploadIdleTimerControlling? = nil
    ) {
        self.bookVM = bookVM
        self.server = server ?? BrowserUploadServer()
        self.addressProvider = addressProvider
        self.idleTimer = idleTimer ?? UIApplication.shared
        self.server.onStateChange = { [weak self] state in self?.apply(state) }
        self.server.onImport = { [weak self] record in
            DispatchQueue.main.async { self?.receiveImportedBook(record) }
        }
        self.server.onResult = { [weak self] result in
            DispatchQueue.main.async { self?.receive(result) }
        }
    }

    func start() {
        results = []
        state = .starting
        if isVisible { idleTimer.isIdleTimerDisabled = true }
        server.start()
    }

    func stop() {
        server.stop()
        state = .stopped
        urls = []
        if isVisible { idleTimer.isIdleTimerDisabled = previousIdleTimerValue }
    }

    func appear() {
        guard !isVisible else { return }
        isVisible = true
        previousIdleTimerValue = idleTimer.isIdleTimerDisabled
        start()
    }

    func disappear() {
        guard isVisible else { return }
        stop()
        isVisible = false
        idleTimer.isIdleTimerDisabled = previousIdleTimerValue
    }

    func sceneChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard isVisible else { return }
            idleTimer.isIdleTimerDisabled = true
            if state == .stopped { start() }
        case .background, .inactive:
            stop()
            idleTimer.isIdleTimerDisabled = previousIdleTimerValue
        @unknown default:
            stop()
            idleTimer.isIdleTimerDisabled = previousIdleTimerValue
        }
    }

    func receive(_ result: BrowserUploadResult) {
        results.insert(result, at: 0)
    }

    private func receiveImportedBook(_ record: ImportedBookRecord) {
        bookVM.invalidateContent(bookID: record.id)
        bookVM.reloadImportedBooks()
    }

    private func apply(_ serverState: BrowserUploadServer.State) {
        switch serverState {
        case .stopped:
            state = .stopped
            urls = []
        case .starting:
            state = .starting
        case .failed(let message):
            state = .failed(message)
            urls = []
        case .ready(let port):
            code = server.authorization.code
            expiresAt = server.authorization.expiresAt
            urls = addressProvider().compactMap { URL(string: "http://\($0):\(port)") }
            state = urls.isEmpty ? .failed("没有找到可用的局域网 IPv4 地址。请让两台设备连接同一个非访客 Wi-Fi，并暂时关闭 VPN。") : .ready
        }
    }
}

struct BrowserUploadView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: BrowserUploadViewModel
    @State private var showingHelp = false

    init(bookVM: BookVM) {
        _viewModel = StateObject(wrappedValue: BrowserUploadViewModel(bookVM: bookVM))
    }

    var body: some View {
        List {
            statusSection
            if !viewModel.urls.isEmpty { addressSection }
            if case .ready = viewModel.state { codeSection }
            if !viewModel.results.isEmpty { resultSection }
            helpSection
        }
        .navigationTitle("浏览器上传")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch viewModel.state {
                case .stopped, .failed:
                    Button("重新开始") { viewModel.start() }
                case .starting, .ready:
                    Button("停止", role: .destructive) { viewModel.stop() }
                }
            }
        }
        .onAppear {
            viewModel.appear()
        }
        .onDisappear {
            viewModel.disappear()
        }
        .onChange(of: scenePhase) { phase in
            viewModel.sceneChanged(phase)
        }
    }

    private var statusSection: some View {
        Section("接收状态") {
            switch viewModel.state {
            case .stopped:
                Label("接收已停止", systemImage: "stop.circle")
            case .starting:
                HStack { ProgressView(); Text("正在启动本地接收服务…") }
            case .ready:
                Label("可以从电脑上传", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("请保持本页面显示并保持设备亮屏。离开 App 或锁屏后，接收服务会停止。")
                    .font(.footnote).foregroundStyle(.secondary)
            case .failed(let message):
                Label("无法开始接收", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.footnote)
                Text("若之前拒绝了本地网络权限，请到“设置 → Ice Reader → 本地网络”重新开启。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var addressSection: some View {
        Section("在电脑浏览器中打开") {
            ForEach(viewModel.primaryURLs, id: \.absoluteString) { url in
                addressRow(url)
            }
            if !viewModel.otherURLs.isEmpty {
                DisclosureGroup("其他地址（\(viewModel.otherURLs.count)）") {
                    ForEach(viewModel.otherURLs, id: \.absoluteString) { url in
                        addressRow(url)
                    }
                    Text("10 开头的地址通常来自大型内网、热点或 VPN；常见家庭和公司网络请优先尝试上方地址。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("电脑无需安装程序，也无需开放 Windows 防火墙入站端口。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func addressRow(_ url: URL) -> some View {
        HStack {
            Text(url.absoluteString).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button { UIPasteboard.general.string = url.absoluteString } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).accessibilityLabel("复制地址")
        }
    }

    private var codeSection: some View {
        Section("本次验证码") {
            Text(viewModel.code)
                .font(.system(size: 38, weight: .bold, design: .monospaced))
                .tracking(8).frame(maxWidth: .infinity).textSelection(.enabled)
            Text("验证码约 10 分钟有效，仅用于本次接收页面；停止或离开后立即失效。")
                .font(.footnote).foregroundStyle(.secondary)
            Text("有效期至 \(viewModel.expiresAt, style: .time)")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
    }

    private var resultSection: some View {
        Section("最近接收") {
            ForEach(viewModel.results) { result in
                Label {
                    VStack(alignment: .leading) { Text(result.title); Text(result.detail).font(.caption).foregroundStyle(.secondary) }
                } icon: {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.succeeded ? .green : .red)
                }
            }
        }
    }

    private var helpSection: some View {
        Section("连接不上？") {
            DisclosureGroup("查看排查方法", isExpanded: $showingHelp) {
                Text("确认电脑与本机连接同一个 Wi-Fi；访客网络/AP 隔离会阻止设备互访。暂时关闭 VPN，依次尝试上方每个地址，并保持本页位于前台。上传中断时，旧书不会被覆盖，可在浏览器中重试。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
