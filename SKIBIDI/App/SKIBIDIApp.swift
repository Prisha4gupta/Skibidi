import SwiftUI

@main
struct SKIBIDIApp: App {
    @State private var communityVM = CommunityViewModel()
    
    var body: some Scene {
        WindowGroup {
            PeopleMapView(viewModel: communityVM)
                .task { await CloudKitSmokeTest.run() }   // TEMP: remove after Phase 3
        }
    }
}

