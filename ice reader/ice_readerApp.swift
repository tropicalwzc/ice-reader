//
//  ice_readerApp.swift
//  ice reader
//
//  Created by 王子诚 on 2023/3/18.
//

import SwiftUI

@main
struct ice_readerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            BookShelfView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
