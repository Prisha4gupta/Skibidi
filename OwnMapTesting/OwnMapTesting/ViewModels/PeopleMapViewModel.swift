import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class PeopleMapViewModel: ObservableObject {
    @Published var members: [Member] = []
    @Published var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let memberRepository: MemberRepository
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    init(memberRepository: MemberRepository, locationService: LocationService) {
        self.memberRepository = memberRepository
        self.locationService = locationService
        bindLocation()
    }

    func onAppear() {
        locationService.requestAuthorization()
        locationService.startUpdating()
        Task { await loadMembers() }
    }

    func loadMembers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await memberRepository.fetchMembers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bindLocation() {
        locationService.currentLocationPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] coord in
                guard let self else { return }
                self.region.center = coord
            }
            .store(in: &cancellables)
    }
}
