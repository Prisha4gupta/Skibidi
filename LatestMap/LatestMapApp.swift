//
//  LatestMapApp.swift
//  LatestMap
//
//  Created by Jason Marsellino on 30/05/26.
//

import SwiftUI

/// App entry point; installs `RootTabView` as the root scene.
@main
struct LatestMapApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}

#Preview {
    RootTabView()
}
