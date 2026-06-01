import SwiftUI

/// App root: the two-tab shell (People map / Settings) and the composition root that builds
/// the service graph and wires it into each tab's ViewModel.
struct RootTabView: View {
    // Services constructed once here and injected down (manual DI / composition root).
    // REVIEW: held as plain `let` on a View, so they're recreated if RootTabView is ever
    // re-instantiated; fine as a single top-level view, but not a View's job conceptually.
    private let healthService: HealthService = MockHealthService()
    private let locationService: LocationService = RealLocationService()
    private let memberRepository: MemberRepository = MockMemberRepository()

    var body: some View {
        TabView {
            CommunitiesMapView(
                viewModel: CommunitiesViewModel(
                    memberRepository: memberRepository,
                    locationService: locationService
                ),
                healthService: healthService
            )
            .tabItem { Label("Communities", systemImage: "person.3.fill") }

            SettingsView(
                viewModel: SettingsViewModel(
                    healthService: healthService,
                    locationService: locationService
                )
            )
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
