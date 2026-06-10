import CloudKit

/// The app's CloudKit backend: writes the device owner's data into every community zone they
/// belong to, and reads communities + member records back for the UI (via `CommunityViewModel`).
///
/// Marked `@MainActor` for simplicity: everything here is awaited from the main-actor
/// ViewModel, and the heavy network work happens off-thread *inside* CloudKit while the
/// `await` is suspended — so keeping our own code on the main actor costs nothing and
/// sidesteps Swift 6 data-race checks. No UI is touched here.
@MainActor
final class CloudKitService {
    /// CloudKit record type. Plural by project convention (matches the schema in the Console).
    static let memberRecordType = "Members"

    /// Explicit container id. We reference it directly instead of `CKContainer.default()` because
    /// the bundle id (com.bpjsr.tim) no longer matches the container name — the container was set
    /// up as `iCloud.com.bpjsr.skibidi` and kept (with all its schema) through the rename.
    /// `.default()` would resolve to `iCloud.<bundle-id>` and miss it.
    nonisolated static let containerID = "iCloud.com.bpjsr.skibidi"

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: CloudKitService.containerID)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    // MARK: - Community zones

    /// Each community is its own record zone named "community-<UUID>" — in MY private DB if I
    /// created it, or in the shared DB if I joined via a share link. The UUID doubles as the
    /// app-side `Community.id`, so rows stay stable across refreshes and devices.
    static let communityZonePrefix = "community-"
    static let communityRecordType = "CommunityInfo"
    private static let communityInfoRecordName = "community-info"

    static func communityID(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(communityZonePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(communityZonePrefix.count)))
    }

    /// A community's location in CloudKit plus everything fetched from its zone.
    struct CloudCommunity: Identifiable {
        let id: UUID
        let zoneID: CKRecordZone.ID
        let isOwned: Bool       // true = I created it (private DB); false = joined (shared DB)
        var name: String
        var createdAt: Date?
        var members: [User]
        var imageData: Data?    // community avatar, stored as a CKAsset and loaded back into Data
    }

    /// All community zones I'm part of: zones I created (private DB) + zones I joined
    /// (shared DB). Non-community zones — e.g. the legacy "GroupZone" — are ignored.
    private func communityZoneRefs() async throws -> [(zoneID: CKRecordZone.ID, isOwned: Bool)] {
        var refs: [(CKRecordZone.ID, Bool)] = []
        for zone in try await database.allRecordZones()
        where Self.communityID(fromZoneName: zone.zoneID.zoneName) != nil {
            refs.append((zone.zoneID, true))
        }
        // Propagate shared-DB failures instead of treating them as "no joined communities" —
        // swallowing them made every joined team vanish for one bad tick, which the change
        // feed would misread as "team deleted". An empty shared DB returns [] without error.
        let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
        for zone in sharedZones
        where Self.communityID(fromZoneName: zone.zoneID.zoneName) != nil {
            refs.append((zone.zoneID, false))
        }
        return refs
    }

    private func databaseFor(isOwned: Bool) -> CKDatabase {
        isOwned ? database : container.sharedCloudDatabase
    }

    // MARK: - Identity & location

    private var cachedRecordName: String?

    /// A record name unique to THIS iCloud user, so every member writes a distinct record in the
    /// shared zone. A fixed name would make participants overwrite each other (and the owner).
    private func myRecordName() async throws -> String {
        if let cached = cachedRecordName { return cached }
        let userID = try await container.userRecordID()
        let name = "member-\(userID.recordName)"
        cachedRecordName = name
        return name
    }

    // MARK: - Public API

    /// Upsert my member record into EVERY community zone I'm part of (created or joined), so
    /// each community sees my latest data. No communities yet → nothing to sync. Never throws —
    /// failures are logged, because a sync hiccup shouldn't crash the app.
    /// `sosCommunityIDs` controls which community zones carry my active SOS message — that's how
    /// the "Send to" audience is enforced. `nil` = broadcast my SOS to every zone; a set = write it
    /// only to those communities and clear it from the rest; an empty set = clear it everywhere.
    func syncMyData(_ user: User, sosCommunityIDs: Set<UUID>? = nil) async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                print("☁️ [CloudKit] iCloud not available (status \(status.rawValue)). Sign in via Settings.")
                return
            }
            let refs = try await communityZoneRefs()
            guard !refs.isEmpty else {
                print("☁️ [CloudKit] no communities yet — nothing to sync")
                return
            }
            for ref in refs {
                // Strip my SOS out of any zone that isn't a chosen target, so the message reaches
                // exactly the audience I picked (and nobody else).
                var scoped = user
                if let ids = sosCommunityIDs,
                   let cid = Self.communityID(fromZoneName: ref.zoneID.zoneName),
                   !ids.contains(cid) {
                    scoped.sosMessage = nil
                }
                do {
                    try await upsertMyMemberRecord(from: scoped,
                                                   database: databaseFor(isOwned: ref.isOwned),
                                                   zoneID: ref.zoneID)
                } catch {
                    print("❌ [CloudKit] sync to \(ref.zoneID.zoneName) failed:", error)
                }
            }
            print("☁️ [CloudKit] WRITE ok — my record in \(refs.count) zone(s)")
        } catch {
            print("❌ [CloudKit] sync failed:", error)
        }
    }

    // MARK: - Sharing

    /// Create a brand-new community: its own zone, a `CommunityInfo` record carrying the name,
    /// and a zone-wide share in "anyone with the link" mode (the link itself grants access —
    /// no email lookup). Returns the share + container for the system invite sheet.
    func createCommunity(named name: String, imageData: Data? = nil) async throws -> (CloudCommunity, CKShare, CKContainer) {
        let id = UUID()
        let zoneID = CKRecordZone.ID(zoneName: Self.communityZonePrefix + id.uuidString,
                                     ownerName: CKCurrentUserDefaultName)
        _ = try await database.save(CKRecordZone(zoneID: zoneID))

        let createdAt = Date()
        let infoID = CKRecord.ID(recordName: Self.communityInfoRecordName, zoneID: zoneID)
        let info = CKRecord(recordType: Self.communityRecordType, recordID: infoID)
        info["name"] = name
        info["createdAt"] = createdAt
        if let imageData, let asset = Self.makeImageAsset(imageData) {
            info["image"] = asset
        }
        try await database.save(info)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = name
        share.publicPermission = .readWrite   // "anyone with the link" — no email invite dance
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        var savedShare = share
        if case .success(let saved) = result.saveResults[share.recordID], let s = saved as? CKShare {
            savedShare = s   // prefer the server copy (carries the share URL)
        }
        let community = CloudCommunity(id: id, zoneID: zoneID, isOwned: true,
                                       name: name, createdAt: createdAt, members: [],
                                       imageData: imageData)
        return (community, savedShare, container)
    }

    /// A `CKAsset` must be backed by a file on disk, so spill the avatar bytes to a temp file
    /// and hand CloudKit the URL — it copies the contents at save time.
    private static func makeImageAsset(_ data: Data) -> CKAsset? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        do {
            try data.write(to: url)
            return CKAsset(fileURL: url)
        } catch {
            print("❌ [CloudKit] failed to stage community image asset:", error)
            return nil
        }
    }

    /// Fetch every community I'm in — info + all member records per zone. My own record in
    /// each community comes back flagged `isCurrentUser` (matched by stable record name).
    /// Requires the `recordName` queryable index on `Members` (already set in the Console).
    func fetchCommunities() async throws -> [CloudCommunity] {
        let myName = try await myRecordName()
        var communities: [CloudCommunity] = []
        for ref in try await communityZoneRefs() {
            guard let id = Self.communityID(fromZoneName: ref.zoneID.zoneName) else { continue }
            let db = databaseFor(isOwned: ref.isOwned)

            var name = "Team"
            var createdAt: Date?
            var imageData: Data?
            let infoID = CKRecord.ID(recordName: Self.communityInfoRecordName, zoneID: ref.zoneID)
            let query = CKQuery(recordType: Self.memberRecordType, predicate: NSPredicate(value: true))

            // The info fetch and the member query are independent round-trips — run them
            // concurrently so each zone costs one network wait instead of two.
            async let infoFetch = db.record(for: infoID)
            async let memberFetch = db.records(matching: query, inZoneWith: ref.zoneID)

            if let info = try? await infoFetch {
                name = info["name"] as? String ?? name
                createdAt = info["createdAt"] as? Date
                if let asset = info["image"] as? CKAsset, let url = asset.fileURL {
                    imageData = try? Data(contentsOf: url)
                }
            } else {
                print("❌ [CloudKit] info record unreadable for zone \(ref.zoneID.zoneName) — name/photo will fall back")
            }

            let (matches, _) = try await memberFetch
            let members: [User] = matches.compactMap { _, result in
                guard case .success(let record) = result, var user = Self.decode(record) else { return nil }
                if record.recordID.recordName == myName { user.isCurrentUser = true }
                return user
            }
            communities.append(CloudCommunity(id: id, zoneID: ref.zoneID, isOwned: ref.isOwned,
                                              name: name, createdAt: createdAt, members: members,
                                              imageData: imageData))
        }
        return communities
    }

    /// Fetch the community's existing zone-wide share — creating it for an owned zone if
    /// missing — for presenting `UICloudSharingController`. Participants read the existing
    /// share from the shared DB (they can re-share the link, but only the owner manages it).
    func fetchOrCreateShare(for community: CloudCommunity) async throws -> (CKShare, CKContainer) {
        let db = databaseFor(isOwned: community.isOwned)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: community.zoneID)
        do {
            if let existing = try await db.record(for: shareID) as? CKShare {
                // Migrate pre-public shares to "anyone with the link" (owner only).
                if community.isOwned, existing.publicPermission == .none {
                    existing.publicPermission = .readWrite
                    if let saved = try? await db.save(existing) as? CKShare {
                        return (saved, container)
                    }
                }
                return (existing, container)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Owned zone not shared yet — fall through and create.
        }
        guard community.isOwned else { throw CKError(.unknownItem) }
        let share = CKShare(recordZoneID: community.zoneID)
        share[CKShare.SystemFieldKey.title] = community.name
        share.publicPermission = .readWrite
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        if case .success(let saved) = result.saveResults[share.recordID], let s = saved as? CKShare {
            return (s, container)
        }
        return (share, container)
    }

    // MARK: - Change subscriptions (M5 push)

    private static let privateSubscriptionID = "private-db-changes"
    private static let sharedSubscriptionID = "shared-db-changes"

    /// Install silent-push subscriptions on both databases (idempotent), so the server pings
    /// the app whenever a community zone changes and the UI refreshes without waiting for the
    /// poll. Best-effort: failures are logged — the poll still covers us.
    func ensureSubscriptions() async {
        await ensureSubscription(id: Self.privateSubscriptionID, in: database, label: "private")
        await ensureSubscription(id: Self.sharedSubscriptionID, in: container.sharedCloudDatabase, label: "shared")
    }

    private func ensureSubscription(id: String, in db: CKDatabase, label: String) async {
        if (try? await db.subscription(for: id)) != nil { return }   // already installed
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        // Silent push: no banner, no sound, no user permission prompt — just "wake and fetch".
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await db.save(subscription)
            print("☁️ [CloudKit] \(label)-DB change subscription installed")
        } catch {
            print("❌ [CloudKit] \(label)-DB subscription failed:", error)
        }
    }

    // MARK: - Leave / delete

    /// Remove a community from my world.
    /// Owner → delete the zone outright; its records and share die with it, so the group
    /// dissolves for everyone (CloudKit has no ownership transfer — that's the deal).
    /// Participant → delete my member record (so others stop seeing me), then drop the zone
    /// from my shared DB, which ends my share participation; the owner's data is untouched.
    /// Throws on failure so the caller keeps the row — otherwise the next poll would resurrect
    /// a community we only pretended to remove.
    func removeCommunity(_ community: CloudCommunity) async throws {
        let db = databaseFor(isOwned: community.isOwned)
        if !community.isOwned {
            // Best-effort: leaving works without this, but my stale record would linger.
            let myID = CKRecord.ID(recordName: try await myRecordName(), zoneID: community.zoneID)
            _ = try? await db.deleteRecord(withID: myID)
        }
        // The async API only throws on whole-operation failures; a per-zone failure comes back
        // inside `deleteResults`. Surface it, or a failed leave looks like success, the row is
        // removed locally, and the next fetch self-heals my member record right back in.
        let result = try await db.modifyRecordZones(saving: [], deleting: [community.zoneID])
        if case .failure(let error) = result.deleteResults[community.zoneID] {
            throw error
        }
        print("☁️ [CloudKit] removed community \(community.name) (\(community.isOwned ? "deleted" : "left"))")
    }

    // MARK: - Write (upsert)

    /// Save my data to my own record in one community zone. Fetches the existing record first
    /// (to hold the correct change tag), or creates a fresh one — i.e. an upsert.
    private func upsertMyMemberRecord(from user: User, database db: CKDatabase,
                                      zoneID: CKRecordZone.ID) async throws {
        let recordID = CKRecord.ID(recordName: try await myRecordName(), zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.memberRecordType, recordID: recordID)
        }
        Self.encode(user, into: record)
        try await db.save(record)
    }

    // MARK: - Mapping  (User / HealthSnapshot  ⟷  CKRecord)

    /// Translate a `User` into CloudKit fields. A `CKRecord` is dictionary-like; Swift `Int`,
    /// `Double`, and `String` bridge to CloudKit number/string types automatically. Enums are
    /// stored as their raw `String` so they survive the round-trip unambiguously.
    /// Each category is gated by the user's sharing flag: when a category is OFF, its fields are
    /// set to `nil`, which **deletes them from the cloud** on save (not just hidden in the UI) —
    /// that's what makes the privacy toggle real. Identity, profile, and the flags always sync.
    static func encode(_ user: User, into record: CKRecord) {
        record["userUUID"]        = user.id.uuidString          // transient app-local id (per launch)
        record["appleUserID"]     = user.appleUserID            // stable owner identity across launches
        record["displayName"]     = user.name
        record["emoji"]           = user.emoji
        record["status"]          = user.status.rawValue
        record["ringColor"]       = user.ringColor.rawValue
        record["locationSharing"] = user.locationSharing.rawValue
        record["healthSharing"]   = user.healthSharing.rawValue
        record["fitnessSharing"]  = user.fitnessSharing.rawValue
        // Emergency SOS. Setting `nil` deletes the field from this zone's record, so standing the
        // SOS down (or never targeting this community) clears the red pin for that audience.
        record["sosMessage"]      = user.sosMessage

        let h = user.healthSnapshot

        // Location
        if user.locationSharing.hasData {
            record["latitude"]  = user.latitude
            record["longitude"] = user.longitude
        } else {
            record["latitude"]  = nil
            record["longitude"] = nil
        }

        // Health metrics
        if user.healthSharing.hasData {
            record["steps"]            = h.steps
            record["stepsDistanceKm"]  = h.stepsDistanceKm
            record["sleepHours"]       = h.sleepHours
            record["restingHeartRate"] = h.restingHeartRate
            record["hydrationPercent"] = h.hydrationPercent
        } else {
            record["steps"]            = nil
            record["stepsDistanceKm"]  = nil
            record["sleepHours"]       = nil
            record["restingHeartRate"] = nil
            record["hydrationPercent"] = nil
        }

        // Fitness / activity rings
        if user.fitnessSharing.hasData {
            record["moveCalories"]    = h.moveCalories
            record["moveGoal"]        = h.moveGoal
            record["exerciseMinutes"] = h.exerciseMinutes
            record["exerciseGoal"]    = h.exerciseGoal
            record["standHours"]      = h.standHours
            record["standGoal"]       = h.standGoal
            record["activeCalories"]  = h.activeCalories
        } else {
            record["moveCalories"]    = nil
            record["moveGoal"]        = nil
            record["exerciseMinutes"] = nil
            record["exerciseGoal"]    = nil
            record["standHours"]      = nil
            record["standGoal"]       = nil
            record["activeCalories"]  = nil
        }
    }

    /// Translate a CloudKit record back into a `User`. Used to verify the round-trip now, and
    /// to render other members' records once sharing lands. Returns `nil` if the record is
    /// missing the bare essentials. Missing optional fields fall back to sensible defaults.
    static func decode(_ record: CKRecord) -> User? {
        guard
            let uuidString = record["userUUID"] as? String,
            let id = UUID(uuidString: uuidString)
        else { return nil }

        // Pull fields into typed locals first. A single 12-arg initializer of `record[x] as? T ?? d`
        // expressions can blow up Swift's type-checker ("unable to type-check in reasonable time");
        // independent `let`s each check trivially and read just as clearly.
        let int: (String) -> Int = { record[$0] as? Int ?? 0 }
        let dbl: (String) -> Double = { record[$0] as? Double ?? 0 }
        let appleUserID = record["appleUserID"] as? String

        let snapshot = HealthSnapshot(
            steps:            int("steps"),
            stepsDistanceKm:  dbl("stepsDistanceKm"),
            sleepHours:       dbl("sleepHours"),
            restingHeartRate: int("restingHeartRate"),
            hydrationPercent: int("hydrationPercent"),
            moveCalories:     int("moveCalories"),
            moveGoal:         int("moveGoal"),
            exerciseMinutes:  int("exerciseMinutes"),
            exerciseGoal:     int("exerciseGoal"),
            standHours:       int("standHours"),
            standGoal:        int("standGoal"),
            activeCalories:   int("activeCalories")
        )

        return User(
            id: id,
            appleUserID: appleUserID,
            name: record["displayName"] as? String ?? "Unknown",
            emoji: record["emoji"] as? String ?? "👤",
            isCurrentUser: false,
            status: (record["status"] as? String).flatMap(MemberStatus.init) ?? .normal,
            healthSnapshot: snapshot,
            latitude: record["latitude"] as? Double ?? 0,
            longitude: record["longitude"] as? Double ?? 0,
            locationSharing: (record["locationSharing"] as? String).flatMap(SharingState.init) ?? .active,
            healthSharing: (record["healthSharing"] as? String).flatMap(SharingState.init) ?? .active,
            fitnessSharing: (record["fitnessSharing"] as? String).flatMap(SharingState.init) ?? .active,
            sosMessage: record["sosMessage"] as? String,
            ringColor: (record["ringColor"] as? String).flatMap(User.RingColor.init) ?? .pink
        )
    }
}
