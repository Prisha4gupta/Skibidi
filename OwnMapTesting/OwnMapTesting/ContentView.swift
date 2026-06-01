import SwiftUI

struct ContentView: View {
    // Services are constructed once and injected into the view model.
    private let memberRepository: MemberRepository = MockMemberRepository()
    private let locationService: LocationService = RealLocationService()

    var body: some View {
        PeopleMapView(
            viewModel: PeopleMapViewModel(
                memberRepository: memberRepository,
                locationService: locationService
            )
        )
    }
}

#Preview {
    ContentView()
}
