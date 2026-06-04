import SwiftUI
import MapKit

/// Manages community data, member selection, and navigation state for the People tab.
@MainActor
@Observable
class CommunityViewModel {
    // MARK: - Data
    var communities: [Community]
    var notifications: [AppNotification]
    var currentUser: User
    var activeSOSMessages: [UUID: String] = [:]

    // MARK: - Services (not observable UI state)
    @ObservationIgnored private let locationManager = LocationManager()
    @ObservationIgnored private let healthService = HealthKitService()
    /// Once the user has manually moved the map (or picked a community) we stop auto-recentering
    /// on each new location fix, so we don't fight the user's panning.
    @ObservationIgnored private var hasAutoRecentered = false
    
    // MARK: - Navigation State
    var selectedCommunity: Community?
    var selectedMember: User?
    var showingCommunitySheet = true
    var showingPeopleList = false
    var showingDashboard = false
    var showingMemberProfile = false
    var showingYourProfile = false
    var showingCreateCommunity = false
    var showingNotifications = false
    var showingEmergencySOS = false
    
    // MARK: - Map State
    var mapCameraPosition: MapCameraPosition
    
    init() {
        let mock = MockDataService.shared
        self.communities = mock.communities
        self.notifications = mock.notifications
        self.currentUser = mock.currentUser
        self.mapCameraPosition = .region(
            MKCoordinateRegion(
                center: mock.mapCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )

        // React to real device-location fixes (adapted from LatestMap's LocationService).
        locationManager.onLocationUpdate = { [weak self] coord in
            self?.handleLocationUpdate(coord)
        }
    }

    // MARK: - Lifecycle
    /// Called from the map's `.onAppear`: requests location + HealthKit permission, starts
    /// location updates, and loads the current user's real health metrics.
    func onAppear() {
        locationManager.requestAuthorization()
        locationManager.start()
        Task { await loadCurrentUserHealth() }
    }

    /// Folds the device owner's real HealthKit data onto their mock snapshot (mock stays the
    /// fallback for fields HealthKit can't supply, or when unavailable/unauthorized).
    func loadCurrentUserHealth() async {
        await healthService.requestAuthorization()
        let merged = await healthService.fetchTodaySnapshot(merging: currentUser.healthSnapshot)
        currentUser.healthSnapshot = merged
    }

    /// Updates the current user's stored coordinate and, until the user takes over the map,
    /// recenters on their real position.
    private func handleLocationUpdate(_ coord: CLLocationCoordinate2D) {
        currentUser.latitude = coord.latitude
        currentUser.longitude = coord.longitude

        guard !hasAutoRecentered, selectedCommunity == nil else { return }
        hasAutoRecentered = true
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )
    }

    /// Recenters the map on the current user's latest known coordinate (real fix when available,
    /// otherwise their mock location). Backs the "locate me" button.
    func recenterOnCurrentUser() {
        let center = locationManager.currentLocation ?? currentUser.coordinate
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        )
    }

    // MARK: - Map pins
    /// Pins shown on the map: the selected community's members (or everyone when none is
    /// selected), with the current user swapped in live (real location + real health). Members
    /// who never shared their location are excluded; paused members stay (frozen at last spot).
    var visibleMapMembers: [User] {
        let base = selectedCommunity?.members ?? allMapMembers
        return base
            .map { $0.isCurrentUser ? currentUser : $0 }
            .filter { $0.locationSharing.hasData }   // .never → off the map; .paused/.active → shown
    }

    var allMapMembers: [User] {
        var seen = Set<UUID>()
        var result: [User] = []
        for community in communities {
            for member in community.members {
                if !seen.contains(member.id) {
                    seen.insert(member.id)
                    result.append(member)
                }
            }
        }
        return result
    }

    func sosMessage(for user: User) -> String? {
        activeSOSMessages[user.id]
    }
    
    // MARK: - Actions
    func selectCommunity(_ community: Community) {
        selectedCommunity = community
        showingPeopleList = true
        showingCommunitySheet = false
        recenter(onMembersOf: community)
    }

    /// Centers the map on the centroid of a community's location-sharing members so the
    /// newly shown pins are in view. No-op if none share location.
    private func recenter(onMembersOf community: Community) {
        let shown = community.members
            .map { $0.isCurrentUser ? currentUser : $0 }
            .filter { $0.locationSharing.hasData }
        guard !shown.isEmpty else { return }
        let lat = shown.map(\.latitude).reduce(0, +) / Double(shown.count)
        let lon = shown.map(\.longitude).reduce(0, +) / Double(shown.count)
        hasAutoRecentered = true // selection owns the camera now; stop auto-following location
        mapCameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        )
    }
    
    func openDashboard() {
        showingPeopleList = false
        showingDashboard = true
    }
    
    func selectMember(_ member: User) {
        selectedMember = member
        if member.isCurrentUser {
            showingYourProfile = true
        } else {
            showingMemberProfile = true
        }
        showingPeopleList = false
        showingDashboard = false
    }
    
    func goBackToCommunities() {
        selectedCommunity = nil
        selectedMember = nil
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }
    
    func goBackToPeopleList() {
        selectedMember = nil
        showingMemberProfile = false
        showingYourProfile = false
        showingDashboard = false
        showingPeopleList = true
    }
    
    func dismissProfile() {
        selectedMember = nil
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }
    
    func createCommunity(name: String, type: CommunityType, memberCount: Int,
                         locationSharing: Bool, healthSharing: Bool, fitnessSharing: Bool,
                         dateActive: Date) {
        let newCommunity = Community(
            id: UUID(),
            name: name,
            type: type,
            imageData: nil,
            members: [currentUser],
            dateActive: dateActive,
            memberCount: memberCount,
            isLocationSharing: locationSharing,
            isHealthSharing: healthSharing,
            isFitnessSharing: fitnessSharing,
            hasNotification: false,
            notificationMessage: nil
        )
        communities.append(newCommunity)
        showingCreateCommunity = false
    }

    func leaveCommunity(_ community: Community) {
        communities.removeAll { $0.id == community.id }

        if selectedCommunity?.id == community.id {
            selectedCommunity = nil
            selectedMember = nil
            showingPeopleList = false
            showingDashboard = false
            showingMemberProfile = false
            showingYourProfile = false
            showingCommunitySheet = true
        }
    }

    func leaveAllCommunities() {
        communities.removeAll()
        selectedCommunity = nil
        selectedMember = nil
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }

    func sendEmergencySOS(message: String, communityID: UUID?) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let targetCommunities = communities.filter { community in
            communityID == nil || community.id == communityID
        }

        for community in targetCommunities {
            notifications.insert(
                AppNotification(
                    id: UUID(),
                    communityName: community.name,
                    communityEmoji: "🚨",
                    message: "SOS from You: \(trimmedMessage)",
                    timestamp: Date(),
                    isRead: false
                ),
                at: 0
            )
        }

        activeSOSMessages[currentUser.id] = trimmedMessage

        for index in communities.indices {
            if communityID == nil || communities[index].id == communityID {
                communities[index].hasNotification = true
            }
        }

        showingEmergencySOS = false
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = false
        showingNotifications = false
    }
}

/// Manages settings state: permissions, privacy, and location sharing.
@MainActor
@Observable
class SettingsViewModel {
    // MARK: - Permissions
    var isFitnessEnabled = true
    var isHealthEnabled = false
    var isWeatherEnabled = false
    
    // MARK: - Location
    var isLocationSharingEnabled = true
    
    // MARK: - Privacy
    var privacyLevel: PrivacyLevel = .everyone
    var showingPrivacyMenu = false
    
    // MARK: - Community
    var showingLeaveCommunity = false
    var communityToLeave: Community?
    
    // MARK: - Communities Reference
    var communities: [Community]
    
    init() {
        self.communities = MockDataService.shared.communities
    }
    
    func leaveCommunity(_ community: Community) {
        communities.removeAll { $0.id == community.id }
        showingLeaveCommunity = false
        communityToLeave = nil
    }

    func leaveAllCommunities() {
        communities.removeAll()
        showingLeaveCommunity = false
        communityToLeave = nil
    }
    
    func confirmLeave(community: Community) {
        communityToLeave = community
        showingLeaveCommunity = true
    }

    func confirmLeaveAllCommunities() {
        communityToLeave = nil
        showingLeaveCommunity = true
    }
}
