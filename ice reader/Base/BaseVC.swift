//
//  BaseVC.swift
//  iosApp
//
//  Created by skytoup on 2022/7/7.
//  Copyright © 2022 orgName. All rights reserved.
//

import UIKit

class BaseVC: UIViewController {

    private var alreadyAppear = false

    override var preferredStatusBarStyle: UIStatusBarStyle {
        presentedViewController?.preferredStatusBarStyle ?? UIStatusBarStyle.default
    }

    /// 默认背景色
    var defaultViewBgColor: UIColor { .white }

    override func loadView() {
        super.loadView()

        view.backgroundColor = defaultViewBgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

    }


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !alreadyAppear {
            alreadyAppear = true
        }
    }

}
