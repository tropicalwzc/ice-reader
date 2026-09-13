import XCTest
@testable import ice_reader

final class BrowserUploadServerTests: XCTestCase {
    func testParserHandlesFragmentedHeaderAndInitialBody() throws {
        let prefix = Data("PUT /api/upload?filename=%E4%B9%A6.txt HTTP/1.1\r\nHost: 192.168.1.2:1234\r\nContent-Length: 3\r\n".utf8)
        XCTAssertNil(try BrowserUploadHTTPParser.parseHeader(from: prefix))
        let parsed = try XCTUnwrap(BrowserUploadHTTPParser.parseHeader(from: prefix + Data("\r\nabc".utf8)))
        XCTAssertEqual(parsed.0.method, "PUT")
        XCTAssertEqual(parsed.1, Data("abc".utf8))
        XCTAssertEqual(try BrowserUploadHTTPParser.contentLength(for: parsed.0, maximum: 10), 3)
    }

    func testParserRejectsFramingAndLimits() throws {
        XCTAssertThrowsError(try BrowserUploadHTTPParser.contentLength(for: request(headers: ["transfer-encoding": "chunked", "content-length": "3"]), maximum: 10))
        XCTAssertThrowsError(try BrowserUploadHTTPParser.contentLength(for: request(headers: [:]), maximum: 10))
        XCTAssertThrowsError(try BrowserUploadHTTPParser.contentLength(for: request(headers: ["content-length": "11"]), maximum: 10))
        XCTAssertThrowsError(try BrowserUploadHTTPParser.parseHeader(from: Data(repeating: 65, count: BrowserUploadHTTPParser.maximumHeaderBytes + 1)))
    }

    func testCodeExchangeExpiryAuthorizationAndRateLimit() throws {
        var now = Date(timeIntervalSince1970: 100)
        let auth = BrowserUploadAuthorization(lifetime: 60, now: { now }, code: "123456")
        for _ in 0..<5 { XCTAssertThrowsError(try auth.exchange(code: "000000", client: "client")) }
        XCTAssertThrowsError(try auth.exchange(code: "123456", client: "client"))
        now.addTimeInterval(61)
        XCTAssertThrowsError(try auth.exchange(code: "123456", client: "another"))
        let valid = BrowserUploadAuthorization(code: "654321")
        let token = try valid.exchange(code: "654321", client: "client")
        XCTAssertTrue(valid.authorizes("Bearer \(token)"))
        valid.invalidate()
        XCTAssertFalse(valid.authorizes("Bearer \(token)"))
    }

    func testPrivateAddressFiltering() {
        ["10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.2.3"].forEach { XCTAssertTrue(PrivateIPv4AddressProvider.isUsable($0)) }
        ["127.0.0.1", "169.254.1.1", "100.64.0.1", "172.15.1.1", "172.32.1.1", "8.8.8.8", "::1"].forEach { XCTAssertFalse(PrivateIPv4AddressProvider.isUsable($0)) }
    }

    func testUnsafeNamesAndPathAttacksAreRejected() {
        for value in ["", ".hidden.txt", "../a.txt", "/a.txt", "a\\b.txt", "a\u{0000}.txt"] {
            XCTAssertThrowsError(try ImportedBookStore.validatedFilename(value))
        }
    }

    @MainActor
    func testViewModelLifecycleAddressAndResultAggregation() throws {
        let store = ImportedBookStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let bookVM = BookVM(importedStore: store)
        let server = FakeBrowserUploadServer()
        let idleTimer = FakeIdleTimer()
        let viewModel = BrowserUploadViewModel(bookVM: bookVM, server: server, addressProvider: { ["10.0.0.2", "172.20.1.8", "192.168.8.9"] }, idleTimer: idleTimer)
        viewModel.appear()
        XCTAssertEqual(server.startCount, 1)
        XCTAssertTrue(idleTimer.isIdleTimerDisabled)
        server.onStateChange?(.ready(4567))
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.primaryURLs.map(\.absoluteString), ["http://172.20.1.8:4567", "http://192.168.8.9:4567"])
        XCTAssertEqual(viewModel.otherURLs.map(\.absoluteString), ["http://10.0.0.2:4567"])
        XCTAssertEqual(viewModel.code, "123456")
        viewModel.receive(BrowserUploadResult(title: "三体", succeeded: true, detail: "已导入"))
        XCTAssertEqual(viewModel.results.first?.title, "三体")
        viewModel.sceneChanged(.background)
        XCTAssertEqual(server.stopCount, 1)
        XCTAssertEqual(viewModel.state, .stopped)
        XCTAssertFalse(idleTimer.isIdleTimerDisabled)
        viewModel.sceneChanged(.active)
        XCTAssertEqual(server.startCount, 2)
        XCTAssertTrue(idleTimer.isIdleTimerDisabled)
        viewModel.disappear()
        XCTAssertFalse(idleTimer.isIdleTimerDisabled)
    }

    private func request(headers: [String: String]) -> BrowserUploadHTTPRequest {
        BrowserUploadHTTPRequest(method: "PUT", target: "/api/upload", version: "HTTP/1.1", headers: headers)
    }
}

private final class FakeBrowserUploadServer: BrowserUploadServing {
    var onStateChange: ((BrowserUploadServer.State) -> Void)?
    var onImport: ((ImportedBookRecord) -> Void)?
    var onResult: ((BrowserUploadResult) -> Void)?
    let authorization = BrowserUploadAuthorization(code: "123456")
    var startCount = 0
    var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

private final class FakeIdleTimer: BrowserUploadIdleTimerControlling {
    var isIdleTimerDisabled = false
}
