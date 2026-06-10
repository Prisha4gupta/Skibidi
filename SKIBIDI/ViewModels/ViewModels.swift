import SwiftUI
import MapKit
import UserNotifications

/// Manages community data, member selection, and navigation state for the People tab.
@MainActor
@Observable
class CommunityViewModel {
    // MARK: - Data
    var communities: [Community]
    var notifications: [AppNotification]
    var currentUser: User
    /// Which audience my active SOS targets, mirroring the "Send to" picker: `nil` while
    /// `currentUser.sosMessage != nil` means broadcast to all groups & people; a community id
    /// means that group only. Drives `currentSOSTargets`, which scopes every CloudKit sync.
    @ObservationIgnored private var sosTargetCommunityID: UUID?
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
    /// Polls the cloud group while the app is open so other members' updates appear ~live even
    /// when a CloudKit change push doesn't arrive (silent pushes are best-effort).
    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    /// Once the user has manually moved the map (or picked a community) we stop auto-recentering
    /// on each new location fix, so we don't fight the user's panning.
    @ObservationIgnored private var hasAutoRecentered = false

    // MARK: - Permission intents (from onboarding)
    // The onboarding toggles are the single source of truth for whether we track at all. We load
    // them from the saved profile and gate `onAppear` on them — the system prompt already happened
    // during onboarding, so the map never re-requests. Defaulted on for installs with no saved
    // profile yet (the map falls back to the previous behavior until onboarding writes the intents).
    @ObservationIgnored private var locationIntent = true
    @ObservationIgnored private var healthIntent = true
    @ObservationIgnored private var fitnessIntent = true
    
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
    
    /// Where the map sits before the first real GPS fix (Bali, matching the trip context).
    private static let defaultMapCenter = CLLocationCoordinate2D(latitude: -8.4095, longitude: 115.1889)

    /// The device owner before onboarding + HealthKit fill in the real data: empty metrics
    /// (live values fold in via `loadCurrentUserHealth`) and a placeholder coordinate that the
    /// first location fix replaces.
    private static func makeDefaultUser() -> User {
        User(
            id: UUID(),
            name: "Your Name",
            emoji: "👻",
            isCurrentUser: true,
            status: .active,
            healthSnapshot: .empty,
            latitude: -8.5069,
            longitude: 115.2625,
            ringColor: .pink
        )
    }

    init() {
        self.communities = []
        self.notifications = Self.loadPersistedNotifications()
        // Restore the display name the user set previously, on a local copy *before* assigning —
        // mutating the @Observable `currentUser` setter touches all of `self`, which isn't fully
        // initialized yet. CloudKit can't hand out the iCloud name, so the user owns it (see
        // updateDisplayName).
        var user = Self.makeDefaultUser()
        // Fold the onboarding profile (saved locally on "Done!") onto the device owner, so the map
        // pin / profile show the real name + emoji + Apple identity. Falls back to the legacy
        // display-name key, then the mock default.
        if let profile = UserDefaultsProfileStore().load() {
            Self.apply(profile, to: &user)
            // Capture the onboarding permission toggles for `onAppear` gating. Plain stored-property
            // assignment, so it's allowed here before the rest of `self` is initialized.
            locationIntent = profile.locationIntent
            healthIntent = profile.healthIntent
            fitnessIntent = profile.fitnessIntent ?? profile.healthIntent
        } else if let savedName = UserDefaults.standard.string(forKey: Self.displayNameKey), !savedName.isEmpty {
            user.name = savedName
        }
        self.currentUser = user
        self.mapCameraPosition = .region(
            MKCoordinateRegion(
                center: Self.defaultMapCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )

        // React to real device-location fixes (adapted from LatestMap's LocationService).
        locationManager.onLocationUpdate = { [weak self] coord in
            self?.handleLocationUpdate(coord)
        }

        // A just-accepted share invite: write my record into the new zone and refresh right
        // away, so joining feels instant instead of waiting for the next poll tick.
        NotificationCenter.default.addObserver(
            forName: .cloudKitShareAccepted, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.cloudKit.syncMyData(self.currentUser, sosCommunityIDs: self.currentSOSTargets)
                await self.refreshCloudCommunities()
            }
        }

        // A CloudKit silent push said something changed server-side — refresh right away
        // instead of waiting for the next poll tick.
        NotificationCenter.default.addObserver(
            forName: .cloudKitDataChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshCloudCommunities()
            }
        }
    }

    /// Fold a locally-saved onboarding profile onto a `User` (name + emoji + Apple identity).
    /// Shared by `init` and `reloadProfileFromLocalStore()` so both stay in sync.
    private static func apply(_ profile: StoredProfile, to user: inout User) {
        if !profile.fullName.isEmpty { user.name = profile.fullName }
        if !profile.selectedEmoji.isEmpty { user.emoji = profile.selectedEmoji }
        user.appleUserID = profile.appleUserID
        // The onboarding/settings toggles are the sharing source of truth. Off → `.never`, so
        // the CloudKit encode deletes those fields and other members see "Not shared" instead
        // of zeroed-out metrics.
        user.locationSharing = profile.locationIntent ? .active : .never
        user.healthSharing = profile.healthIntent ? .active : .never
        user.fitnessSharing = (profile.fitnessIntent ?? profile.healthIntent) ? .active : .never
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
        loadPermissionIntents()
    }

    /// Pull the onboarding permission toggles off the saved profile so `onAppear` can gate tracking
    /// on them. No profile yet (pre-onboarding launch) → keep the defaults. The OS prompt itself
    /// already happened in onboarding; here we only decide whether to *use* the granted capability.
    private func loadPermissionIntents() {
        guard let profile = UserDefaultsProfileStore().load() else { return }
        locationIntent = profile.locationIntent
        healthIntent = profile.healthIntent
        fitnessIntent = profile.fitnessIntent ?? profile.healthIntent
    }

    // MARK: - Lifecycle
    /// Called from the map's `.onAppear`. Permissions were already requested during onboarding, so
    /// we do NOT prompt here — we only *use* the capabilities the user opted into via the onboarding
    /// toggles (`locationIntent` / `healthIntent`). A toggle left off means we never start that
    /// tracking, so the onboarding choice is the single source of truth.
    func onAppear() {
        // Location: start only if opted in. `start()` itself no-ops unless the OS granted access.
        if locationIntent {
            locationManager.start()
        }
        Task {
            // Health/fitness both come from HealthKit — read if either is opted in.
            if healthIntent || fitnessIntent {
                await loadCurrentUserHealth()
            }
            // Read the group first so I can adopt my own name from the cloud (cross-device) before
            // writing — otherwise sync would overwrite it with this device's default.
            await refreshCloudCommunities()
            // Push my freshly-loaded real data (health + location + name) up to my iCloud DB.
            await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets)
            // Re-read so my freshly-written record shows in the group.
            await refreshCloudCommunities()
            // Keep steps (and other metrics) live: re-fetch whenever HealthKit reports new
            // samples, so the count updates while the app stays open.
            if healthIntent || fitnessIntent {
                healthService.startStepUpdates { [weak self] in
                    Task { await self?.loadCurrentUserHealth() }
                }
            }
            // Install CloudKit change subscriptions (idempotent) so the server pings us when
            // a community zone changes — refreshes then happen push-driven, the poll is backup.
            await cloudKit.ensureSubscriptions()
            startLiveRefresh()
        }
    }

    /// Called from the map's `.onDisappear`: stops live HealthKit updates + cloud polling.
    func onDisappear() {
        healthService.stopStepUpdates()
        stopLiveRefresh()
    }

    // MARK: - Live refresh (M5, poll-based)
    /// Re-fetches the cloud group every ~6s while the app is open, so other members' changes show
    /// up without push. Safe to call repeatedly — any existing loop is cancelled first.
    private func startLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
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
            markMyRecords(in: &fetched)
            // Self-heal: a community without my record means I just joined it (accepted a share)
            // or an earlier sync failed — write my record now and re-fetch, so I show up without
            // waiting for a relaunch. Idempotent; at worst it retries on the next poll tick.
            if fetched.contains(where: { c in !c.members.contains(where: { $0.isCurrentUser }) }) {
                await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets)
                fetched = try await cloudKit.fetchCommunities()
                markMyRecords(in: &fetched)
            }
            emitChangeNotifications(from: cloudCommunities, to: fetched)
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

    /// Flag my own record in each community. It comes back flagged `isCurrentUser` already
    /// (stable record name); fall back to `appleUserID` — the stable Sign in with Apple
    /// identity — for records the record-name match missed.
    private func markMyRecords(in fetched: inout [CloudKitService.CloudCommunity]) {
        guard let myAppleID = currentUser.appleUserID, !myAppleID.isEmpty else { return }
        for i in fetched.indices
        where !fetched[i].members.contains(where: { $0.isCurrentUser }) {
            if let j = fetched[i].members.firstIndex(where: { $0.appleUserID == myAppleID }) {
                fetched[i].members[j].isCurrentUser = true
            }
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
                imageData: cloud.imageData,
                members: cloud.members,
                dateActive: cloud.createdAt ?? Date(),
                memberCount: cloud.members.count,
                isLocationSharing: true,
                isHealthSharing: true,
                isFitnessSharing: true,
                // Rebuilds wipe row state, so the badge is derived from the feed each time.
                hasNotification: notifications.contains { !$0.isRead && $0.communityName == cloud.name },
                notificationMessage: nil
            )
        }
        communities.insert(contentsOf: rows, at: 0)   // real groups first
        if let selected = selectedCommunity, cloudCommunityIDs.contains(selected.id) {
            selectedCommunity = communities.first { $0.id == selected.id }
        }
    }

    // MARK: - Notification feed

    private static let notificationsKey = "notificationFeed"
    /// Whether we already hold a first cloud snapshot. The first fetch after launch is the
    /// baseline — diffing it against the empty pre-launch state would announce every existing
    /// member as "just joined".
    @ObservationIgnored private var hasBaselineSnapshot = false

    /// Turn the difference between two consecutive cloud snapshots into feed entries:
    /// member joins/leaves, incoming SOS, invites I accepted, and teams that disappeared.
    private func emitChangeNotifications(from old: [CloudKitService.CloudCommunity],
                                         to new: [CloudKitService.CloudCommunity]) {
        guard hasBaselineSnapshot else {
            hasBaselineSnapshot = true
            // An SOS already active before launch must still surface — missing one is worse
            // than an occasional repeat (the duplicate check in emitSOSNotifications filters those).
            for community in new {
                emitSOSNotifications(previous: [:], current: community)
            }
            return
        }

        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        var seen = Set<UUID>()

        for community in new {
            seen.insert(community.id)
            guard let previous = oldByID[community.id] else {
                // A community appearing mid-session that I didn't create = an accepted invite.
                if !community.isOwned {
                    pushNotification(community: community, emoji: "👥",
                                     message: "You joined \"\(community.name)\"")
                }
                emitSOSNotifications(previous: [:], current: community)
                continue
            }

            let oldMembers = Self.membersByIdentity(previous.members)
            let newMembers = Self.membersByIdentity(community.members)

            for (key, member) in newMembers where oldMembers[key] == nil && !member.isCurrentUser {
                pushNotification(community: community, emoji: "👥",
                                 message: "\(member.name) joined")
            }
            for (key, member) in oldMembers where newMembers[key] == nil && !member.isCurrentUser {
                pushNotification(community: community, emoji: "👥",
                                 message: "\(member.name) left")
            }
            emitSOSNotifications(previous: oldMembers, current: community)
        }

        // Gone without me leaving locally → the owner deleted it (or my access was revoked).
        // Trustworthy because fetch failures now abort the refresh instead of returning [].
        for community in old where !seen.contains(community.id) && !community.isOwned {
            pushNotification(community: community, emoji: "👥",
                             message: "\"\(community.name)\" is no longer available")
        }
    }

    /// Notify SOS messages that are new (or changed) since the previous snapshot, skipping my
    /// own and entries already in the feed (guards baseline repeats across relaunches).
    private func emitSOSNotifications(previous: [String: User],
                                      current community: CloudKitService.CloudCommunity) {
        for member in community.members where !member.isCurrentUser {
            guard let sos = member.sosMessage,
                  previous[Self.identity(of: member)]?.sosMessage != sos else { continue }
            let message = "SOS from \(member.name): \(sos)"
            guard !notifications.contains(where: {
                $0.message == message && $0.communityName == community.name
            }) else { continue }
            pushNotification(community: community, emoji: "🚨", message: message)
            postSOSBanner(from: member.name, sos: sos, teamName: community.name)
        }
    }

    /// Lock-screen banner for an incoming SOS — the one event urgent enough to surface
    /// outside the app (joins/leaves stay in-app only). iOS suppresses it while the app is
    /// foregrounded (the red pin + feed already show it there), and it's a silent no-op if
    /// the user never granted notification permission in onboarding.
    private func postSOSBanner(from memberName: String, sos: String, teamName: String) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 SOS from \(memberName)"
        content.body = "\(sos) — \(teamName)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Stable cross-poll identity for a member. The record's `userUUID` changes when that
    /// member relaunches their app, so prefer the durable Apple identity, then the name.
    private static func identity(of member: User) -> String {
        if let appleID = member.appleUserID, !appleID.isEmpty { return appleID }
        return member.name
    }

    private static func membersByIdentity(_ members: [User]) -> [String: User] {
        var result: [String: User] = [:]
        for member in members { result[identity(of: member)] = member }
        return result
    }

    /// Insert a feed entry and persist. The community-row badge is derived from unread entries
    /// during `rebuildCloudCommunityRows`, which runs right after the diff.
    private func pushNotification(community: CloudKitService.CloudCommunity, emoji: String, message: String) {
        notifications.insert(
            AppNotification(
                id: UUID(),
                communityName: community.name,
                communityEmoji: emoji,
                message: message,
                timestamp: Date(),
                isRead: false
            ),
            at: 0
        )
        persistNotifications()
    }

    /// Flip everything to read — called when the notification sheet closes, so the bell dot
    /// and row badges go dark until something new happens.
    func markNotificationsRead() {
        guard notifications.contains(where: { !$0.isRead }) else { return }
        for index in notifications.indices {
            notifications[index].isRead = true
        }
        for index in communities.indices {
            communities[index].hasNotification = false
        }
        persistNotifications()
    }

    /// The feed survives relaunches via UserDefaults — newest first, capped so it can't grow
    /// unbounded.
    private func persistNotifications() {
        if notifications.count > 50 {
            notifications.removeLast(notifications.count - 50)
        }
        if let data = try? JSONEncoder().encode(notifications) {
            UserDefaults.standard.set(data, forKey: Self.notificationsKey)
        }
    }

    private static func loadPersistedNotifications() -> [AppNotification] {
        guard let data = UserDefaults.standard.data(forKey: Self.notificationsKey),
              let saved = try? JSONDecoder().decode([AppNotification].self, from: data) else { return [] }
        return saved
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
        Task { await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets) }
    }

    // MARK: - Sharing toggles (M6)
    /// Flip a sharing category. Setting it off re-syncs my record, which *deletes* that category's
    /// fields from the cloud (see `CloudKitService.encode`) — so other members see "Not shared",
    /// not just hidden locally. The choice is persisted onto the stored profile so a relaunch
    /// keeps it; turning a category back on (re)starts the matching local data pipeline.
    func setLocationSharing(_ on: Bool) {
        currentUser.locationSharing = on ? .active : .never
        locationIntent = on
        persistIntents { $0.locationIntent = on }
        if on { locationManager.start() } else { locationManager.stop() }
        resyncSharing()
    }

    func setHealthSharing(_ on: Bool) {
        currentUser.healthSharing = on ? .active : .never
        healthIntent = on
        persistIntents { $0.healthIntent = on }
        if on { startHealthUpdates() } else { stopHealthUpdatesIfUnused() }
        resyncSharing()
    }

    func setFitnessSharing(_ on: Bool) {
        currentUser.fitnessSharing = on ? .active : .never
        fitnessIntent = on
        persistIntents { $0.fitnessIntent = on }
        if on { startHealthUpdates() } else { stopHealthUpdatesIfUnused() }
        resyncSharing()
    }

    /// Write a toggle change back onto the saved onboarding profile, so the next launch
    /// derives the same sharing states (see `apply`). No profile yet → nothing to persist.
    private func persistIntents(_ mutate: (inout StoredProfile) -> Void) {
        let store = UserDefaultsProfileStore()
        guard var profile = store.load() else { return }
        mutate(&profile)
        try? store.save(profile)
    }

    /// (Re)start the HealthKit read + live step observer — used when health or fitness sharing
    /// is switched on after launch, where `onAppear` already skipped them.
    private func startHealthUpdates() {
        Task {
            await loadCurrentUserHealth()
            healthService.startStepUpdates { [weak self] in
                Task { await self?.loadCurrentUserHealth() }
            }
        }
    }

    /// Stop the live HealthKit observer once neither health nor fitness sharing needs it.
    private func stopHealthUpdatesIfUnused() {
        if !healthIntent && !fitnessIntent {
            healthService.stopStepUpdates()
        }
    }

    private func resyncSharing() {
        Task {
            await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets)
            await refreshCloudCommunities()
        }
    }

    /// Creates a real CloudKit community (own zone + share) and returns the invite-sheet data
    /// so the caller drops straight into sharing the link. `nil` on failure (logged).
    func createCommunity(name: String, imageData: Data? = nil) async -> ShareSheetData? {
        do {
            let (created, share, container) = try await cloudKit.createCommunity(named: name, imageData: imageData)
            // Show the new team immediately — its name and photo are already known locally.
            // Writing my member record + the re-fetch catch up in the background; the next
            // refresh replaces this optimistic row with the server copy.
            cloudCommunities.insert(created, at: 0)
            rebuildCloudCommunityRows()
            showingCreateCommunity = false
            Task {
                await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets)   // put my record in the new zone
                await refreshCloudCommunities()
            }
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

    /// SOS to render on a pin. My own comes from the local source of truth (`currentUser`) so it
    /// shows instantly; everyone else's comes from their CloudKit-synced record, which only carries
    /// the message if I'm in an audience the sender chose.
    func sosMessage(for user: User) -> String? {
        user.id == currentUser.id ? currentUser.sosMessage : user.sosMessage
    }

    /// True while the current user has an active SOS broadcast (drives the "Cancel SOS" affordance).
    var isCurrentUserSOSActive: Bool {
        currentUser.sosMessage != nil
    }

    /// The community zones my active SOS should be written into (see `CloudKitService.syncMyData`):
    /// empty = no SOS anywhere, `nil` = broadcast to all, a single id = that group only.
    private var currentSOSTargets: Set<UUID>? {
        guard currentUser.sosMessage != nil else { return [] }
        if let id = sosTargetCommunityID { return [id] }
        return nil
    }

    /// Pushes my current SOS state to CloudKit scoped to its chosen audience, then refreshes so the
    /// change (or stand-down) is reflected locally.
    private func syncSOS() async {
        await cloudKit.syncMyData(currentUser, sosCommunityIDs: currentSOSTargets)
        await refreshCloudCommunities()
    }

    /// Clears the current user's active SOS, so the map pin drops the red override and returns to
    /// its energy color — and removes the message from CloudKit so it disappears for everyone it
    /// was sent to, not just locally.
    func cancelSOS() {
        currentUser.sosMessage = nil
        sosTargetCommunityID = nil
        Task { await syncSOS() }
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
    
    /// Whether I created this community. `true` → removing it deletes the group for everyone
    /// (CloudKit can't transfer ownership); `false` → I just leave; `nil` → mock/local-only row.
    /// Drives the swipe-action label ("Delete" vs "Leave").
    func ownsCommunity(_ community: Community) -> Bool? {
        cloudCommunities.first { $0.id == community.id }?.isOwned
    }

    /// Owner deletes the community for everyone; a participant leaves it. The cloud removal must
    /// succeed before the row goes — a local-only removal would just resurrect on the next poll.
    /// Returns whether the removal actually happened, so callers can confirm or report failure.
    @discardableResult
    func leaveCommunity(_ community: Community) async -> Bool {
        if let cloud = cloudCommunities.first(where: { $0.id == community.id }) {
            do {
                try await cloudKit.removeCommunity(cloud)
            } catch {
                print("❌ [Community] remove failed:", error)
                return false
            }
            cloudCommunities.removeAll { $0.id == cloud.id }
            cloudCommunityIDs.remove(cloud.id)
        }
        communities.removeAll { $0.id == community.id }

        if selectedCommunity?.id == community.id {
            resetNavigationAfterLeaving()
        }
        return true
    }

    private func resetNavigationAfterLeaving() {
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
        persistNotifications()

        // Set the message + audience locally (instant red pin for me), then push to CloudKit so the
        // chosen people see it too. `communityID == nil` broadcasts; otherwise just that group.
        currentUser.sosMessage = trimmedMessage
        sosTargetCommunityID = communityID

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

        Task { await syncSOS() }
    }
}
