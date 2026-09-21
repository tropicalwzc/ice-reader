//
//  BookMainView.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

/// Vertical offset of a rendered row relative to the scroll view, used to work
/// out which row is actually visible at the top of the screen.
private struct RowOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct BookMainView: View {
    let bookName : String
    let bookExtention : String
    @ObservedObject var vm : BookVM

    @State var smallHeadpage : Int = 0
    @State private var showingAlert = false
    @State var index : String = ""
    @State var hiddenNav : Bool = true
    @State var isFirstAppear = true
    @State var loadFinished = true

    /// The single source of truth for the persisted reading position.
    @State private var readingIndex: Int = 0
    /// Exclusive upper bound of the rendered range. Grows with the reading
    /// position but is never derived from it, so persisting progress cannot
    /// rebuild the list and move the scroll anchor.
    @State private var windowEnd: Int = 0
    /// An explicit request to move the viewport, consumed once.
    @State private var pendingJump: Int?
    /// Last processed frame report, so an unchanged map does not churn state.
    @State private var handledOffsets: [Int: CGFloat] = [:]

    let pageSize : Int = UIDevice.current.userInterfaceIdiom == .pad ? 20 : 10

    func submit(forceCloudSync: Bool) {
        print("total split count now is \(vm.splitedContents.count)")
        guard let nextIndex = Int(index) else { return }
        guard nextIndex >= 0, nextIndex < vm.splitedContents.count else { return }
        // A deliberate jump is a user action, so it is persisted immediately.
        // `forceCloudSync` publishes a new revision, which is what lets a
        // deliberate backward jump survive the larger progress stored in iCloud.
        readingIndex = nextIndex
        requestJump(to: nextIndex)
        vm.saveLastPage(name: bookName, page: nextIndex, forceCloudSync: forceCloudSync)
    }

    func stripSmallPage() {
        var small = readingIndex - pageSize
        if small < 0 {
            small = 0
        }
        smallHeadpage = small
    }

    /// Moves the viewport to `target` and makes sure the row is inside the
    /// rendered window.
    func requestJump(to target: Int) {
        let clamped = ReadingProgress.clamp(page: target, contentCount: vm.splitedContents.count)
        smallHeadpage = min(smallHeadpage, clamped)
        if windowEnd < clamped + 1 {
            windowEnd = min(clamped + 1, max(vm.splitedContents.count, 1))
        }
        pendingJump = clamped
    }

    /// Restores the stored position for the view that is currently on screen.
    ///
    /// This runs when the view appears, not on every state change, so returning
    /// from another screen cannot re-anchor a reader whose scroll offset is
    /// already correct. Running it unconditionally (rather than once per book) is
    /// what keeps a recreated reader from briefly showing page 0.
    func restoreInitialPosition() {
        let stored = vm.readLastPage(name: bookName)
        guard !vm.splitedContents.isEmpty else {
            readingIndex = 0
            smallHeadpage = 0
            windowEnd = 0
            return
        }

        let resolved = ReadingProgress.clamp(page: stored, contentCount: vm.splitedContents.count)
        readingIndex = resolved
        if resolved != stored {
            // Content became shorter; persist the corrected position.
            vm.saveLastPage(name: bookName, page: resolved)
        }
        stripSmallPage()
        requestJump(to: resolved)
        vm.LastReadBookName = bookName
    }

    /// Records where the user actually is. Driven by visible rows rather than by
    /// lazy-container creation, so idle re-renders never write progress.
    func trackVisibleRows(_ offsets: [Int: CGFloat]) {
        guard !offsets.isEmpty, offsets != handledOffsets else { return }
        handledOffsets = offsets

        // The nearest row to the top edge is the row the user is reading. Picking
        // the row with the smallest absolute offset avoids a threshold-dependent
        // choice oscillating between two rows while scrolling.
        guard let top = offsets.min(by: { abs($0.value) < abs($1.value) })?.key else { return }
        setReadingIndex(to: top)
    }

    func setReadingIndex(to newValue: Int) {
        guard newValue != readingIndex else { return }
        readingIndex = newValue
        // Rows above the reading position only waste range; the reading area
        // renders from at most one page above it.
        if smallHeadpage > newValue {
            smallHeadpage = newValue
        }
        // The window's upper bound only grows with the reading position.
        // Shrinking it here would rebuild the list and move the scroll anchor,
        // which is exactly the perturbation this change removes. `ForEach` index
        // arithmetic is cheap and `LazyVStack` still only renders visible rows.
        if windowEnd < newValue + pageSize {
            windowEnd = min(newValue + pageSize, max(vm.splitedContents.count, 1))
        }
        vm.saveLastPage(name: bookName, page: newValue)
    }

    func persistCurrentPosition() {
        guard !vm.splitedContents.isEmpty else { return }
        let clamped = ReadingProgress.clamp(page: readingIndex, contentCount: vm.splitedContents.count)
        vm.saveLastPageNow(name: bookName, page: clamped)
    }

    func pureBookName() -> String {
        let suq = vm.displayName(for: bookName).split(separator: ".")
        let ff = suq.first ?? ""
        return String(ff)
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                let total = min(max(windowEnd, readingIndex + 1), vm.splitedContents.count)
                ScrollView(showsIndicators: false) {
                    if self.loadFinished && !vm.splitedContents.isEmpty && smallHeadpage < total {
                        LazyVStack(spacing: 5) {
                            ForEach(smallHeadpage ..< total, id: \.self) { index in
                                rowView(index: index)
                                    .background(
                                        GeometryReader { geometry in
                                            Color.clear.preference(
                                                key: RowOffsetKey.self,
                                                value: [index: geometry.frame(in: .named("readerScroll")).minY]
                                            )
                                        }
                                    )
                            }
                        }
                        .onPreferenceChange(RowOffsetKey.self) { offsets in
                            trackVisibleRows(offsets)
                        }
                    } else {
                        LoadingView()
                    }
                }
                .coordinateSpace(name: "readerScroll")
                .padding(.top, 0.5)
                .onChange(of: pendingJump) { target in
                    guard let target else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        pendingJump = nil
                    }
                }
            }
        }
        .onAppear {
            self.loadFinished = false

            vm.fetchAllDatas(bookName: bookName, extention: bookExtention) { res in
                guard res == "T" else {
                    DispatchQueue.main.async {
                        self.loadFinished = false
                    }
                    return
                }
                //print("reload all datas")
                DispatchQueue.main.async {
                    self.loadFinished = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                    restoreInitialPosition()
                })

                if isFirstAppear {
                    isFirstAppear = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: {
                        recursiveCheck(remain: 5)
                    })
                }
            }
        }

        .navigationTitle("\(pureBookName()) \(readingIndex)")
        .alert("跳转到哪一页?", isPresented: $showingAlert) {
            TextField("跳转到哪一页?", text: $index).keyboardType(UIKeyboardType.decimalPad)
            Button("OK") {
                submit(forceCloudSync: true)
            }
        } message: {
            Text("(总共\(vm.splitedContents.count)页)")
        }
        .toolbar {
            Button {
                index = "\(readingIndex)"
                showingAlert = true
            } label: {
                Text("跳转")
            }
        }
        .statusBarHidden(hiddenNav)
        .navigationBarHidden(hiddenNav)
        .onDisappear {
            // Capture the final position while the view still knows it.
            persistCurrentPosition()
            vm.updateProgresses()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            // Flush before suppressing saves so the last stretch of reading is kept.
            persistCurrentPosition()
            vm.blockSaveAction = true

        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            vm.blockSaveAction = false
            if !checkCloudUpdateIfNeed() {
                recursiveCheck(remain: 10)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MKiCloudSyncDidUpdateToLatest"))) { _ in
            _ = checkCloudUpdateIfNeed()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Guarantees the save gate cannot remain stuck, even on a launch path
            // that never received a background transition.
            vm.blockSaveAction = false
        }

    }

    @ViewBuilder
    private func rowView(index: Int) -> some View {
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
            }

            Text(vm.splitedContents[index])
                .font(.system(size: 25, weight: .regular))
                .padding(.horizontal, 6)
                .lineSpacing(5)
                .tracking(1)
                .multilineTextAlignment(.leading)
                .onTapGesture {
                    // Tapping only reveals the navigation bar. It must not move
                    // the reading position; that is the job of scrolling and the
                    // explicit jump action.
                    if hiddenNav == true {
                        hiddenNav = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            hiddenNav = true
                        }
                    }
                }
                .foregroundColor(Color.init("BookColor"))
                .padding(.top, 8)
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

    /// Aligns to a position that another device published.
    ///
    /// Returns `true` when the viewport moved. The stored position tracks the
    /// reader's own progress while scrolling, so it equals `readingIndex` exactly
    /// when the reader is sitting on their stored position. Anywhere else the
    /// user is mid-read, and an external value — even a deliberate backward push
    /// from another device — must not drag them away. Deferred overrides stay
    /// pending and are applied later, once the reader is back on the stored
    /// position.
    @discardableResult
    func checkCloudUpdateIfNeed() -> Bool {
        guard !vm.splitedContents.isEmpty else { return false }
        guard readingIndex == vm.storedLocalPage(name: bookName) else { return false }

        if vm.hasFreshExternalProgressOverride(name: bookName) {
            guard let external = vm.consumeExternalProgressOverride(name: bookName) else { return false }
            return alignTo(external)
        }

        let stored = vm.readLastPage(name: bookName)
        guard stored > readingIndex else { return false }
        return alignTo(stored)
    }

    private func alignTo(_ target: Int) -> Bool {
        guard !vm.splitedContents.isEmpty else { return false }
        let clamped = ReadingProgress.clamp(page: target, contentCount: vm.splitedContents.count)
        guard clamped != readingIndex else { return false }
        print("start cloud jump")
        readingIndex = clamped
        index = "\(clamped)"
        requestJump(to: clamped)
        vm.saveLastPage(name: bookName, page: clamped)
        return true
    }
}
