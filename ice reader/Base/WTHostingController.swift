//
//  WTHostingController.swift
//  iosApp
//
//  Created by skytoup on 2022/8/3.
//  Copyright © 2022 orgName. All rights reserved.
//

import SwiftUI
import UIKit

/// UIHostingController自定义功能
class WTHostingController<Content: View>: UIHostingController<Content> {
    /// 是否忽略safe area
    let isIgnoreSafeArea: Bool

    init(rootView: Content, isIgnoreSafeArea: Bool = false) {
        self.isIgnoreSafeArea = isIgnoreSafeArea

        super.init(rootView: rootView)

        view.backgroundColor = .clear
        if isIgnoreSafeArea {
            ignoreSafeArea()
        }
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        isIgnoreSafeArea = false

        super.init(coder: aDecoder)
    }

    /// 忽略safe area
    private func ignoreSafeArea() {
        guard let viewClass = object_getClass(view) else {
            return
        }

        let viewSubclassName = String(cString: class_getName(viewClass)).appending("_IgnoreSafeArea")
        if let viewSubclass = NSClassFromString(viewSubclassName) {
            object_setClass(view, viewSubclass)
        } else {
            guard let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String else {
                return
            }
            guard let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0) else {
                return
            }

            if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
                let safeAreaInsets: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in
                    .zero
                }
                class_addMethod(viewSubclass, #selector(getter: UIView.safeAreaInsets), imp_implementationWithBlock(safeAreaInsets), method_getTypeEncoding(method))
            }

            objc_registerClassPair(viewSubclass)
            object_setClass(view, viewSubclass)
        }
    }
}
