//
//  blocknotasApp.swift
//  blocknotas
//
//  Created by Moises rojas on 1/09/26.
//

import SwiftUI
import SwiftData

@main
struct blocknotasApp: App {
    let container: ModelContainer = PersistenceController.shared.container

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
