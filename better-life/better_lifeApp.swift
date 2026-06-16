//
//  better_lifeApp.swift
//  better-life
//
//  Created by 张金琛 on 2026/4/19.
//

import SwiftUI
import SwiftData

@main
struct better_lifeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [DailyRecord.self, WordProgress.self])
    }
}
