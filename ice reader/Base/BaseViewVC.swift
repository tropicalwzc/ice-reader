//
//  BaseViewVC.swift
//  iosApp
//
//  Created by skytoup on 2022/7/7.
//  Copyright © 2022 orgName. All rights reserved.
//

import SwiftUI
import UIKit

class BaseViewVC<Content: View>: BaseVC {
    /// 是否忽略SwiftUI view的safe area
    /// - 继承重写属性
    var isIgnoreViewSafeArea: Bool { false }

    private(set) lazy var context = ViewVCContext(containerVC: self)

    private lazy var contentView = ContentView(view: body, context: context)
    private lazy var hostingVC = WTHostingController(rootView: contentView, isIgnoreSafeArea: isIgnoreViewSafeArea)

    var liftActions: ViewVCLiftActions { internalLiftActions }
    private let internalLiftActions = InternalViewVCLiftActions()

    var body: Content {
        fatalError("need override this property")
    }

    deinit {
        internalLiftActions.deallocAction?()
    }

    override func loadView() {
        super.loadView()

        hostingVC.view.backgroundColor = .clear
        hostingVC.view.frame = view.bounds
        hostingVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        internalLiftActions.willAppearAction?(animated)
        context.internalLiftActions.willAppearAction?(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        internalLiftActions.didAppearAction?(animated)
        context.internalLiftActions.didAppearAction?(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        internalLiftActions.willDisappearAction?(animated)
        context.internalLiftActions.willDisappearAction?(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        internalLiftActions.didDisappearAction?(animated)
        context.internalLiftActions.didDisappearAction?(animated)
    }
}

extension BaseViewVC {
    private struct ContentView<Content: View>: View {
        let view: Content

        /// 上下文
        @ObservedObject var context: ViewVCContext
        
        var body: some View {
            view
                .onAppear()
                .environmentObject(context)
        }
    }
}

// MARK: - ViewVCContext

/// 仅BaseViewVC内有自动设置, 其它地方的View没有
final class ViewVCContext: ObservableObject {

    /// 包装view的容器vc
    private(set) weak var containerVC: UIViewController?

    var liftActions: ViewVCLiftActions { internalLiftActions }
    fileprivate let internalLiftActions = InternalViewVCLiftActions()

    var navigationController: UINavigationController? {
        containerVC?.navigationController
    }

    var tabBarController: UITabBarController? {
        containerVC?.tabBarController
    }

    init(containerVC: UIViewController?) {
        self.containerVC = containerVC
    }

    /// pop或dismiss containerVC
    func popOrDismissVC(completion: (() -> Void)? = nil) {
        if containerVC?.presentingViewController != nil {
            containerVC?.dismiss(animated: true, completion: completion)
        } else if let completion {
            CATransaction.begin()
            CATransaction.setCompletionBlock(completion)
            navigationController?.popViewController(animated: true)
            CATransaction.commit()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

}

// MARK: - ViewVCLiftActions

protocol ViewVCLiftActions {
    typealias AppearBlock = (_ animated: Bool) -> Void
}

private class InternalViewVCLiftActions: ViewVCLiftActions {
    var willAppearAction: AppearBlock?
    var didAppearAction: AppearBlock?
    var willDisappearAction: AppearBlock?
    var didDisappearAction: AppearBlock?
    var deallocAction: (() -> Void)?
}

protocol ImpViewVCLiftActionsSetter {
    var liftActions: ViewVCLiftActions { get }
}

extension ImpViewVCLiftActionsSetter {
    private var internalLiftActions: InternalViewVCLiftActions? {
        liftActions as? InternalViewVCLiftActions
    }

    func onWillAppear(_ block: ViewVCLiftActions.AppearBlock?) -> Self {
        internalLiftActions?.willAppearAction = block
        return self
    }

    func onDidAppear(_ block: ViewVCLiftActions.AppearBlock?) -> Self {
        internalLiftActions?.didAppearAction = block
        return self
    }

    func onWillDisappear(_ block: ViewVCLiftActions.AppearBlock?) -> Self {
        internalLiftActions?.willDisappearAction = block
        return self
    }

    func onDidDisappear(_ block: ViewVCLiftActions.AppearBlock?) -> Self {
        internalLiftActions?.didDisappearAction = block
        return self
    }

    func onDealloc(_ block: (() -> Void)?) -> Self {
        internalLiftActions?.deallocAction = block
        return self
    }
}

extension ViewVCContext: ImpViewVCLiftActionsSetter {}
extension BaseViewVC: ImpViewVCLiftActionsSetter {}

//class MyView: _UIHostingView<PetRandomPrizeView> {
//
//}
