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
    /// Members fetched live from the CloudKit group zone (your own record solo; everyone once
    /// sharing is live). Empty until the first fetch completes.
    var cloudMembers: [User] = []

    // MARK: - Services (not observable UI state)
    @ObservationIgnored private let locationManager = LocationManager()
    @ObservationIgnored private let healthService = HealthKitService()
    @ObservationIgnored private let cloudKit = CloudKitService()
    /// Polls the cloud group while the app is open so other members' updates appear ~live without
    /// requiring push notifications (which would need aps-environment, at odds with TestFlight).
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
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
    
    /// Demo-filler toggle. `false` = real mode: only you + your CloudKit group show; the mock
    /// communities, fake members (Member 1–4), and mock notifications are hidden. Flip to `true`
    /// to see the demo data again (e.g. for screenshots). The device owner (`currentUser`) is
    /// always loaded either way — real health, location, and name fold onto it.
    static let showDemoData = false

    /// Injected data source. Defaults to the mock so existing callers (`CommunityViewModel()`)
    /// behave exactly as before; pass a `CloudKitService` later to go live — no other change.
    init(dataService: DataService = MockDataService.shared) {
        self.communities = Self.showDemoData ? dataService.communities : []
        self.notifications = Self.showDemoData ? dataService.notifications : []
        // Restore the display name the user set previously, on a local copy *before* assigning —
        // mutating the @Observable `currentUser` setter touches all of `self`, which isn't fully
        // initialized yet. CloudKit can't hand out the iCloud name, so the user owns it (see
        // updateDisplayName).
        var user = dataService.currentUser
        // Fold the onboarding profile (saved locally on "Done!") onto the device owner, so the map
        // pin / profile show the real name + emoji + Apple identity. Falls back to the legacy
        // display-name key, then the mock default.
        if let profile = UserDefaultsProfileStore().load() {
            Self.apply(profile, to: &user)
        } else if let savedName = UserDefaults.standard.string(forKey: Self.displayNameKey), !savedName.isEmpty {
            user.name = savedName
        }
        self.currentUser = user
        self.mapCameraPosition = .region(
            MKCoordinateRegion(
                center: dataService.mapCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )

        // React to real device-location fixes (adapted from LatestMap's LocationService).
        locationManager.onLocationUpdate = { [weak self] coord in
            self?.handleLocationUpdate(coord)
        }
    }

    /// Fold a locally-saved onboarding profile onto a `User` (name + emoji + Apple identity).
    /// Shared by `init` and `reloadProfileFromLocalStore()` so both stay in sync.
    private static func apply(_ profile: StoredProfile, to user: inout User) {
        if !profile.fullName.isEmpty { user.name = profile.fullName }
        if !profile.selectedEmoji.isEmpty { user.emoji = profile.selectedEmoji }
        user.appleUserID = profile.appleUserID
    }

    /// Re-read the locally-saved onboarding profile and apply it to `currentUser`.
    ///
    /// The app builds `CommunityViewModel` once at launch — on a first run that happens *before*
    /// onboarding saves the profile, so `init` sees no profile and `currentUser` keeps the mock
    /// default name/emoji. Call this when onboarding completes so the map owner reflects what the
    /// user just entered, without waiting for the next launch.
    func reloadProfileFromLocalStore() {
        guard let profile = UserDefaultsProfileStore().load() else { return }
        Self.apply(profile, to: &currentUser)
    }

    // MARK: - Lifecycle
    /// Called from the map's `.onAppear`: requests location + HealthKit permission, starts
    /// location updates, and loads the current user's real health metrics.
    func onAppear() {
        locationManager.requestAuthorization()
        locationManager.start()
        Task {
            await loadCurrentUserHealth()
            // Read the group first so I can adopt my own name from the cloud (cross-device) before
            // writing — otherwise sync would overwrite it with this device's default.
            await refreshCloudMembers()
            // Push my freshly-loaded real data (health + location + name) up to my iCloud DB.
            await cloudKit.syncMyData(currentUser)
            // Re-read so my freshly-written record shows in the group.
            await refreshCloudMembers()
            // Keep steps (and other metrics) live: re-fetch whenever HealthKit reports new
            // samples, so the count updates while the app stays open.
            healthService.startStepUpdates { [weak self] in
                Task { await self?.loadCurrentUserHealth() }
            }
            startLiveRefresh()
        }
    }

    /// Called from the map's `.onDisappear`: stops live HealthKit updates + cloud polling.
    func onDisappear() {
        healthService.stopStepUpdates()
        stopLiveRefresh()
    }

    // MARK: - Live refresh (M5, poll-based)
    /// Re-fetches the cloud group every ~12s while the app is open, so other members' changes show
    /// up without push. Safe to call repeatedly — any existing loop is cancelled first.
    private func startLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                if Task.isCancelled { break }
                await self?.refreshCloudMembers()
            }
        }
    }

    private func stopLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    /// Stable id for the cloud-backed community, so refreshes update the same row instead of
    /// adding duplicates. The mock communities keep their own random ids and are never touched.
    private static let cloudCommunityID = UUID(uuidString: "00000000-0000-0000-0000-0000C10DC10D")!

    /// Fetches all members in the CloudKit group zone, then surfaces them as a separate real
    /// community ("My SKIBIDI Group") alongside the untouched mock ones.
    func refreshCloudMembers() async {
        do {
            // My own record already comes back flagged `isCurrentUser` (matched by stable record
            // name). Fall back to `appleUserID` — the stable Sign in with Apple identity — for
            // records that the record-name match missed.
            var fetched = try await cloudKit.fetchAllMembers()
            if !fetched.contains(where: { $0.isCurrentUser }),
               let myAppleID = currentUser.appleUserID, !myAppleID.isEmpty,
               let myIndex = fetched.firstIndex(where: { $0.appleUserID == myAppleID }) {
                fetched[myIndex].isCurrentUser = true
            }
            cloudMembers = fetched
            // Cross-device name: if I never set a name on THIS device, adopt the one stored in my
            // cloud record (set from another device). A locally-set name always wins.
            let hasLocalName = !(UserDefaults.standard.string(forKey: Self.displayNameKey) ?? "").isEmpty
            if !hasLocalName,
               let me = cloudMembers.first(where: { $0.isCurrentUser }),
               !me.name.isEmpty, me.name != "Your Name" {
                currentUser.name = me.name
            }
            print("☁️ [CloudKit] fetched \(cloudMembers.count) member(s):", cloudMembers.map(\.name))
            updateCloudCommunity()
        } catch {
            print("❌ [CloudKit] fetch members failed:", error)
        }
    }

    /// Rebuilds the cloud-backed community from `cloudMembers`. Removes the old one first so the
    /// row updates in place; drops it entirely when there are no members yet.
    private func updateCloudCommunity() {
        communities.removeAll { $0.id == Self.cloudCommunityID }
        guard !cloudMembers.isEmpty else { return }
        let cloud = Community(
            id: Self.cloudCommunityID,
            name: "My SKIBIDI Group",
            type: .detail,
            imageData: nil,
            members: cloudMembers,
            dateActive: Date(),
            memberCount: cloudMembers.count,
            isLocationSharing: true,
            isHealthSharing: true,
            isFitnessSharing: true,
            hasNotification: false,
            notificationMessage: nil
        )
        communities.insert(cloud, at: 0)   // show the real group first
    }

    // MARK: - Identity
    private static let displayNameKey = "userDisplayName"

    /// Sets the owner's display name, persists it locally, and re-pushes to CloudKit. This is how
    /// names work in the app: each member writes their own `displayName` into their record, and
    /// everyone reads names from records (CloudKit no longer hands out iCloud account names).
    func updateDisplayName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentUser.name = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.displayNameKey)
        Task { await cloudKit.syncMyData(currentUser) }
    }

    // MARK: - Sharing toggles (M6)
    /// Flip a sharing category. Setting it off re-syncs my record, which *deletes* that category's
    /// fields from the cloud (see `CloudKitService.encode`) — so it disappears from everyone's app,
    /// not just hidden locally.
    func setLocationSharing(_ on: Bool) { currentUser.locationSharing = on ? .active : .never; resyncSharing() }
    func setHealthSharing(_ on: Bool)   { currentUser.healthSharing   = on ? .active : .never; resyncSharing() }
    func setFitnessSharing(_ on: Bool)  { currentUser.fitnessSharing  = on ? .active : .never; resyncSharing() }

    private func resyncSharing() {
        Task {
            await cloudKit.syncMyData(currentUser)
            await refreshCloudMembers()
        }
    }

    // MARK: - Sharing
    /// Prepares (or reuses) the group's CloudKit share, so the view can present the system invite
    /// sheet. Returns `nil` on failure (logged) — the caller simply doesn't show the sheet.
    func prepareGroupShare() async -> ShareSheetData? {
        do {
            let (share, container) = try await cloudKit.fetchOrCreateShare()
            return ShareSheetData(share: share, container: container)
        } catch {
            print("❌ [Share] prepare failed:", error)
            return nil
        }
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

    /// True while the current user has an active SOS broadcast (drives the "Cancel SOS" affordance).
    var isCurrentUserSOSActive: Bool {
        activeSOSMessages[currentUser.id] != nil
    }

    /// Clears the current user's active SOS, so the map pin drops the red override and returns to
    /// its energy color. There was previously no way to stand down an SOS — once sent it stayed
    /// active for the whole session.
    func cancelSOS() {
        activeSOSMessages[currentUser.id] = nil
    }

    // MARK: - Actions
    func selectCommunity(_ community: Community) {
        selectedCommunity = community
        showingDashboard = true
        showingPeopleList = false
        showingCommunitySheet = false
        recenter(onMembersOf: community)
    }

    func membersForDashboard(in community: Community) -> [User] {
        community.members.map { $0.isCurrentUser ? currentUser : $0 }
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
    
    init(dataService: DataService = MockDataService.shared) {
        self.communities = CommunityViewModel.showDemoData ? dataService.communities : []
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
