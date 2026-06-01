import Foundation
import Combine
import CoreLocation
import MapKit

/// Drives the Communities tab: owns the community list and which community is selected, derives
/// the members shown on the map from that selection, and recenters the map (on device location
/// until a community is picked, then on the selected community's members).
/// `@MainActor` — all `@Published` mutations occur on the main thread.
@MainActor
final class CommunitiesViewModel: ObservableObject {
    /// Source for the community list shown in the sheet.
    @Published var communities: [Community] = []
    /// Currently focused community; its members drive `displayedMembers` / the map pins.
    @Published var selectedCommunityID: Community.ID?
    /// Two-way bound to the `Map`; recentered by location updates and community selection (initial: Jakarta).
    @Published var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    /// Drives a loading indicator during `load`.
    @Published var isLoading: Bool = false
    /// Non-nil surfaces a fetch error to the View.
    @Published var errorMessage: String?

    private let memberRepository: MemberRepository
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    /// Map annotation source: members of the selected community, or empty when none is selected.
    /// Recomputed from `@Published` `selectedCommunityID`/`communities`, so the map updates on change.
    var displayedMembers: [Member] {
        selectedCommunity?.members ?? []
    }

    /// The community matching `selectedCommunityID`, if any.
    var selectedCommunity: Community? {
        guard let id = selectedCommunityID else { return nil }
        return communities.first { $0.id == id }
    }

    init(memberRepository: MemberRepository, locationService: LocationService) {
        self.memberRepository = memberRepository
        self.locationService = locationService
        bindLocation()
    }

    /// View lifecycle intent: requests location auth, starts updates, and loads communities.
    func onAppear() {
        locationService.requestAuthorization()
        locationService.startUpdating()
        Task { await load() }
    }

    /// Loads communities into `communities` and focuses the first one so the map opens with pins.
    /// Toggles `isLoading`; sets `errorMessage` on failure.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            communities = try await memberRepository.fetchCommunities()
            if selectedCommunityID == nil, let first = communities.first {
                select(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Selection intent: switches which community's members the map shows and recenters on them.
    func select(_ community: Community) {
        selectedCommunityID = community.id
        recenter(on: community.members)
    }

    /// Centers `region` on the centroid of `members` (no-op when empty) so the new pins are in view.
    private func recenter(on members: [Member]) {
        guard !members.isEmpty else { return }
        let lat = members.map(\.location.latitude).reduce(0, +) / Double(members.count)
        let lon = members.map(\.location.longitude).reduce(0, +) / Double(members.count)
        region.center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Subscribes to the location stream and recenters `region` on each fix — but only until the
    /// user has picked a community, after which community selection owns the map's focus.
    /// `receive(on: .main)` is belt-and-suspenders given `@MainActor`; `[weak self]` avoids a retain cycle.
    private func bindLocation() {
        locationService.currentLocationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                guard let self, self.selectedCommunityID == nil else { return }
                self.region.center = coord
            }
            .store(in: &cancellables)
    }
}
