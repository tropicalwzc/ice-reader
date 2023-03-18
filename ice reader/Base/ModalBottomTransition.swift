//
//  ModalBottomTransition.swift
//  iosApp
//
//  Created by skytoup on 2022/8/20.
//  Copyright © 2022 orgName. All rights reserved.
//

import UIKit

/// 模态样式
/// 底部往上出现, 底部往下收起, 点击背景dismiss
final class ModalBottomTransition: NSObject, UIViewControllerTransitioningDelegate {
    let config: Config
    var closeAction: (() -> Void)? {
        didSet {
            if closeAction != nil {
                bgView.addGestureRecognizer(tapGR)
            } else if bgView.gestureRecognizers?.contains(tapGR) ?? false {
                bgView.removeGestureRecognizer(tapGR)
            }
        }
    }

    private lazy var tapGR = UITapGestureRecognizer(target: self, action: #selector(clickBG(gr:)))
    private lazy var bgView = UIView()
    private weak var vc: UIViewController?

    private var presented: Presented?

    init(style: LayoutStyle, closeAction: (() -> Void)? = nil) {
        self.config = Config(style: style)
        self.closeAction = closeAction

        super.init()
    }

    init(config: Config) {
        self.config = config

        super.init()
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        self.presented = Presented(config: config) { [weak self] vc, view in
            guard let ws = self else {
                return
            }

            ws.vc = vc
            ws.bgView.removeFromSuperview()
            ws.bgView.isUserInteractionEnabled = true
            ws.bgView.frame = view.bounds
            ws.bgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(ws.bgView)
            view.sendSubviewToBack(ws.bgView)
        }
        return self.presented
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        Dismissed(config: config)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        PresentationController(config: config, presentedViewController: presented, presenting: presenting)
    }

    // MARK: - action

    @objc private func clickBG(gr: UITapGestureRecognizer) {
        guard let view = gr.view, let vc = vc else {
            return
        }

        let point = gr.location(in: view)
        if !vc.view.frame.contains(point) {
            closeAction?()
        }
    }

    // MARK: - private

    private func setupTapGR() -> UITapGestureRecognizer {
        let gr = UITapGestureRecognizer(target: self, action: #selector(clickBG(gr:)))
        bgView.addGestureRecognizer(gr)
        return gr
    }
}

extension ModalBottomTransition {
    final class PresentationController: UIPresentationController {
        let config: Config

        init(config: ModalBottomTransition.Config, presentedViewController: UIViewController, presenting: UIViewController?) {
            self.config = config
            super.init(presentedViewController: presentedViewController, presenting: presenting)
        }

        override func containerViewDidLayoutSubviews() {
            super.containerViewDidLayoutSubviews()
            guard let view = presentedView, view.superview != nil, let frame = containerView?.frame else {
                return
            }

            switch config.style {
            case .selfSize:
                let height = frame.height
                view.frame = .init(x: 0, y: height, width: frame.width, height: height)
            case .halfOfBounds:
                let height = frame.height / 2
                view.frame = .init(x: 0, y: height, width: frame.width, height: height)
            case .fixed(let height):
                view.frame = .init(x: 0, y: height, width: frame.width, height: height)
            case .fullScreen:
                let height = frame.height
                view.frame = .init(x: 0, y: height, width: frame.width, height: height)
            }
        }
    }
}

extension ModalBottomTransition {
    final class Presented: NSObject, UIViewControllerAnimatedTransitioning {
        typealias WillTransitionAction = (_ vc: UIViewController, _ onView: UIView) -> Void

        let config: Config
        let willTransitionAction: WillTransitionAction

        init(config: Config, willTransitionAction: @escaping WillTransitionAction) {
            self.config = config
            self.willTransitionAction = willTransitionAction

            super.init()
        }

        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            config.presentDuration
        }

        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let toVC = transitionContext.viewController(forKey: .to) else {
                return
            }

            let duration = transitionDuration(using: transitionContext)
            // let toFrame = transitionContext.finalFrame(for: toVC)
            let containerView = transitionContext.containerView
            let bgColor = config.bgColorTo

            containerView.backgroundColor = config.bgColorFrom

            containerView.addSubview(toVC.view)
            toVC.view.transform = .init(translationX: 0, y: containerView.bounds.height)

            willTransitionAction(toVC, containerView)
            UIView.animate(withDuration: duration, animations: { [weak toVC, weak containerView] in
                containerView?.backgroundColor = bgColor
                toVC?.view.transform = .identity
            }, completion: { [weak transitionContext] _ in
                let isCancel = transitionContext?.transitionWasCancelled ?? false
                transitionContext?.completeTransition(!isCancel)
            })
        }
    }

    final class Dismissed: NSObject, UIViewControllerAnimatedTransitioning {
        let config: Config

        init(config: Config) {
            self.config = config

            super.init()
        }

        func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
            config.dismissDuration
        }

        func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
            guard let fromVC = transitionContext.viewController(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }

            let duration = transitionDuration(using: transitionContext)
            let view = transitionContext.containerView
            let height = fromVC.view.bounds.height
            let bgColor = config.bgColorFrom

            UIView.animate(withDuration: duration) { [weak fromVC, weak view] in
                view?.backgroundColor = bgColor
                fromVC?.view.transform = .init(translationX: 0, y: height)
            } completion: { [weak fromVC, weak transitionContext] _ in
                let isCancel = transitionContext?.transitionWasCancelled ?? false
                if !isCancel {
                    fromVC?.view.removeFromSuperview()
                }
                transitionContext?.completeTransition(!isCancel)
            }
        }
    }
}

// MARK: defins

extension ModalBottomTransition {
    /// 布局样式
    enum LayoutStyle {
        /// 全屏
        case fullScreen
        /// 半屏
        case halfOfBounds
        /// 根据AutoLayout自动高度
        case selfSize
        /// 固定高度
        case fixed(height: CGFloat)
    }

    struct Config {
        let style: LayoutStyle
        let presentDuration: CGFloat
        let dismissDuration: CGFloat
        let bgColorFrom: UIColor
        let bgColorTo: UIColor

        init(style: LayoutStyle, presentDuration: CGFloat = 0.35, dismissDuration: CGFloat = 0.35, bgColorFrom: UIColor = .clear, bgColorTo: UIColor = .black.withAlphaComponent(0.6)) {
            self.style = style
            self.presentDuration = presentDuration
            self.dismissDuration = dismissDuration
            self.bgColorFrom = bgColorFrom
            self.bgColorTo = bgColorTo
        }
    }
}
