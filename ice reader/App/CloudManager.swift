//
//  CloudManager.swift
//  ice reader
//
//  Created by 王子诚 on 2023/9/14.
//

import Foundation

class CloudManager {
    static let shared = CloudManager()
    var inited : Bool = false
    func initCloudListener() {
        if inited {
            return
        }
        inited = true
        MKiCloudSync.start(withPrefix: "sync")
    }
}
