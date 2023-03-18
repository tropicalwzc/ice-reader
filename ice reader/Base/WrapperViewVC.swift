//
//  WrapperViewVC.swift
//  iosApp
//
//  Created by skytoup on 2023/1/31.
//  Copyright © 2023 orgName. All rights reserved.
//

import SwiftUI
import UIKit

class WrapperViewVC<ContentView: View>: BaseViewVC<ContentView> {
    typealias ViewBlock = (_ context: ViewVCContext) -> ContentView

    let config: WrapperViewVCConfig

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredStatusBarStyle: UIStatusBarStyle { config.statusBarStyle }
    override var defaultViewBgColor: UIColor { config.bgColor }
    override var isIgnoreViewSafeArea: Bool { config.isIgnoreSafeArea }


    override var body: ContentView {
        contentViewBlock(context)
    }

    private let contentViewBlock: (_ context: ViewVCContext) -> ContentView

    init(config: WrapperViewVCConfig? = nil, @ViewBuilder content: @escaping ViewBlock, setupBlock: ((_ context: ViewVCContext) -> Void)? = nil) {
        self.config = config ?? WrapperViewVCConfig()
        contentViewBlock = content

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct WrapperViewVCConfig {
    var bgColor: UIColor = .white
    var isIgnoreSafeArea: Bool = false
    var statusBarStyle: UIStatusBarStyle = UIStatusBarStyle.default
}

// MARK: - view + wrap vc

private let overFullScreenTransitionAssObjKey = UnsafeRawPointer(bitPattern: "__view_vc_wrap_over_full_screen_transition__".hash)!

extension View {
    func wrapVC(config: WrapperViewVCConfig? = nil) -> WrapperViewVC<Self> {
        WrapperViewVC(config: config, content: { _ in self })
    }

    func wrapOverFullScreenVC(config: WrapperViewVCConfig?, bgColor: UIColor? = nil) -> WrapperViewVC<Self> {
        let vc = WrapperViewVC(config: config, content: { _ in self })

        vc.modalPresentationStyle = .custom
        let color = bgColor ?? .black.withAlphaComponent(0.6)
        let transitionConfig = ModalBottomTransition.Config(style: .fullScreen, bgColorTo: color)
        let transition = ModalBottomTransition(config: transitionConfig)
        vc.transitioningDelegate = transition
        objc_setAssociatedObject(vc, overFullScreenTransitionAssObjKey, transition, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        return vc
    }

    func wrapOverFullScreenVC(bgColor: UIColor? = nil) -> WrapperViewVC<Self> {
        let viewVCConfig = WrapperViewVCConfig(bgColor: .clear)
        return wrapOverFullScreenVC(config: viewVCConfig, bgColor: bgColor)
    }
}
