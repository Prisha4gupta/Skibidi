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
    /// Communities fetched live from CloudKit (created + joined), with their members. Mirrored
    /// into `communities` as UI rows by `rebuildCloudCommunityRows()`.
    private var cloudCommunities: [CloudKitService.CloudCommunity] = []
    /// Ids of the cloud-backed rows currently in `communities`, so refreshes replace exactly
    /// those rows and never touch the mock ones.
    private var cloudCommunityIDs: Set<UUID> = []

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
            await refreshCloudCommunities()
            // Push my freshly-loaded real data (health + location + name) up to my iCloud DB.
            await cloudKit.syncMyData(currentUser)
            // Re-read so my freshly-written record shows in the group.
            await refreshCloudCommunities()
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
                await self?.refreshCloudCommunities()
            }
        }
    }

    private func stopLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    /// Fetches all CloudKit communities (mine + joined) and mirrors them into the UI list.
    func refreshCloudCommunities() async {
        do {
            var fetched = try await cloudKit.fetchCommunities()
            // My record comes back flagged `isCurrentUser` (stable record name). Fall back to
            // `appleUserID` — the stable Sign in with Apple identity — for records the
            // record-name match missed.
            if let myAppleID = currentUser.appleUserID, !myAppleID.isEmpty {
                for i in fetched.indices
                where !fetched[i].members.contains(where: { $0.isCurrentUser }) {
                    if let j = fetched[i].members.firstIndex(where: { $0.appleUserID == myAppleID }) {
                        fetched[i].members[j].isCurrentUser = true
                    }
                }
            }
            cloudCommunities = fetched
            // Cross-device name: if I never set a name on THIS device, adopt the one stored in
            // my cloud record (set from another device). A locally-set name always wins.
            let hasLocalName = !(UserDefaults.standard.string(forKey: Self.displayNameKey) ?? "").isEmpty
            if !hasLocalName,
               let me = fetched.flatMap(\.members).first(where: { $0.isCurrentUser }),
               !me.name.isEmpty, me.name != "Your Name" {
                currentUser.name = me.name
            }
            print("☁️ [CloudKit] fetched \(fetched.count) communit(y/ies):",
                  fetched.map { "\($0.name) [\($0.members.count)]" })
            rebuildCloudCommunityRows()
        } catch {
            print("❌ [CloudKit] fetch communities failed:", error)
        }
    }

    /// Replace the cloud-backed rows in `communities` with fresh ones (mock rows untouched)
    /// and re-point `selectedCommunity` — it's a value copy, so an open member list would
    /// otherwise never see new joiners.
    private func rebuildCloudCommunityRows() {
        communities.removeAll { cloudCommunityIDs.contains($0.id) }
        cloudCommunityIDs = Set(cloudCommunities.map(\.id))
        let rows = cloudCommunities.map { cloud in
            Community(
                id: cloud.id,
                name: cloud.name,
                type: .detail,
                imageData: nil,
                members: cloud.members,
                dateActive: cloud.createdAt ?? Date(),
                memberCount: cloud.members.count,
                isLocationSharing: true,
                isHealthSharing: true,
                isFitnessSharing: true,
                hasNotification: false,
                notificationMessage: nil
            )
        }
        communities.insert(contentsOf: rows, at: 0)   // real groups first
        if let selected = selectedCommunity, cloudCommunityIDs.contains(selected.id) {
            selectedCommunity = communities.first { $0.id == selected.id }
        }
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
            await refreshCloudCommunities()
        }
    }

    /// Creates a real CloudKit community (own zone + share) and returns the invite-sheet data
    /// so the caller drops straight into sharing the link. `nil` on failure (logged).
    func createCommunity(name: String) async -> ShareSheetData? {
        do {
            let (_, share, container) = try await cloudKit.createCommunity(named: name)
            await cloudKit.syncMyData(currentUser)   // put my record in the new zone
            await refreshCloudCommunities()
            showingCreateCommunity = false
            return ShareSheetData(share: share, container: container)
        } catch {
            print("❌ [Community] create failed:", error)
            return nil
        }
    }

    /// Invite sheet for a specific community. `nil` for mock rows or on failure (logged).
    func prepareGroupShare(for community: Community) async -> ShareSheetData? {
        guard let cloud = cloudCommunities.first(where: { $0.id == community.id }) else { return nil }
        do {
            let (share, container) = try await cloudKit.fetchOrCreateShare(for: cloud)
            return ShareSheetData(share: share, container: container)
        } catch {
            print("❌ [Share] prepare failed:", error)
            return nil
        }
    }

    // MARK: - Health
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
        var base = selectedCommunity?.members ?? allMapMembers
        // My own pin is local (CoreLocation) — it shows whether or not I'm in any community yet.
        if !base.contains(where: { $0.isCurrentUser }) {
            base.append(currentUser)
        }
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
