//
//  PhotoCleanApp.swift
//  PhotoClean
//
//  Created by Nirdosh on 15/04/25.
//

import SwiftUI

@main
struct PhotoCleanApp: App {
    // Create ONE instance of the ViewModel and keep it alive
    @StateObject private var analysisViewModel = AnalysisViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(analysisViewModel) // Inject into environment OR pass directly
        }
    }
}
