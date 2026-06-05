import SwiftUI

@main
struct SKIBIDIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var communityVM = CommunityViewModel()
    
    var body: some Scene {
        WindowGroup {
            PeopleMapView(viewModel: communityVM)
        }
    }
}

