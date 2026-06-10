import CloudKit

/// Writes the device owner's own data to their private iCloud database and reads it back.
///
/// This is the **write path** (my data → cloud). It is deliberately separate from the
/// `DataService` **read path** (UI → data); the two meet later, in the sharing milestones,
/// once the cloud actually holds everyone's records.
///
/// Marked `@MainActor` for simplicity: everything here is awaited from the main-actor
/// ViewModel, and the heavy network work happens off-thread *inside* CloudKit while the
/// `await` is suspended — so keeping our own code on the main actor costs nothing and
/// sidesteps Swift 6 data-race checks. No UI is touched here.
@MainActor
final class CloudKitService {
    /// CloudKit record type. Plural by project convention (matches the schema in the Console).
    static let memberRecordType = "Members"

    /// Custom zone that holds the (eventually shared) community's member records.
    /// The default zone can't be shared or change-tracked, so sharing *requires* a custom zone —
    /// this is the foundation `CKShare` is built on. For now it's one fixed zone in the owner's
    /// private DB; per-community zones arrive when real sharing lands.
    static let groupZoneID = CKRecordZone.ID(zoneName: "GroupZone", ownerName: CKCurrentUserDefaultName)

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

    /// Where "the group" lives for this user.
    private struct GroupLocation {
        let database: CKDatabase
        let zoneID: CKRecordZone.ID
        let isOwned: Bool   // true = my own zone (private DB); false = a zone I accepted (shared DB)
    }

    /// Decide where the group lives: a zone I accepted (it shows up in my shared DB) wins;
    /// otherwise my own zone in the private DB. This is the owner/participant split that makes
    /// CloudKit sharing work — the owner reads/writes private, participants read/write shared.
    private func resolveGroupLocation() async -> GroupLocation {
        if let shared = try? await container.sharedCloudDatabase.allRecordZones().first {
            return GroupLocation(database: container.sharedCloudDatabase, zoneID: shared.zoneID, isOwned: false)
        }
        return GroupLocation(database: database, zoneID: Self.groupZoneID, isOwned: true)
    }

    // MARK: - Public API

    /// High-level entry point called from the ViewModel: confirm iCloud is available, upsert
    /// the owner's record from their live `User`, then read it back to prove the round-trip.
    /// Never throws — failures are logged, because a sync hiccup shouldn't crash the app.
    func syncMyData(_ user: User) async {
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                print("☁️ [CloudKit] iCloud not available (status \(status.rawValue)). Sign in via Settings.")
                return
            }

            let loc = await resolveGroupLocation()
            // Only the owner creates the zone; a participant writes into the zone they accepted.
            if loc.isOwned { try await ensureZoneExists() }
            try await upsertMyMemberRecord(from: user, in: loc)
            print("☁️ [CloudKit] WRITE ok — my record in \(loc.isOwned ? "owned" : "shared") zone \(loc.zoneID.zoneName)")
        } catch {
            print("❌ [CloudKit] sync failed:", error)
        }
    }

    // MARK: - Zone

    /// Create the custom zone if it doesn't exist yet. Saving a zone that already exists is a
    /// harmless no-op, so this is safe to call on every launch.
    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: Self.groupZoneID)
        _ = try await database.save(zone)
    }

    // MARK: - Sharing

    /// Fetch the zone's existing share, or create one if the zone isn't shared yet. Returns the
    /// share plus the container — both needed to present `UICloudSharingController`.
    ///
    /// This is **zone-wide** sharing: a single `CKShare` covers every record in `groupZoneID`, so
    /// anyone who accepts the invite can read all members in the community (and write their own).
    /// The share lives at the well-known record name `CKRecordNameZoneWideShare` inside the zone,
    /// and a zone can only have one — so we reuse the existing one if it's already there.
    func fetchOrCreateShare() async throws -> (CKShare, CKContainer) {
        try await ensureZoneExists()

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: Self.groupZoneID)
        do {
            if let existing = try await database.record(for: shareID) as? CKShare {
                return (existing, container)        // already shared → reuse
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not shared yet — fall through and create it.
        }

        let share = CKShare(recordZoneID: Self.groupZoneID)
        share[CKShare.SystemFieldKey.title] = "SKIBIDI Group"
        let result = try await database.modifyRecords(saving: [share], deleting: [])
        // Prefer the server-saved share (it carries the share URL/metadata).
        if case .success(let saved) = result.saveResults[share.recordID], let savedShare = saved as? CKShare {
            return (savedShare, container)
        }
        return (share, container)
    }

    // MARK: - Write (upsert)

    /// Save my data to my own record in the given location (private zone if owner, shared zone if
    /// participant). Fetches the existing record first (to hold the correct change tag), or
    /// creates a fresh one if none exists — i.e. an upsert.
    private func upsertMyMemberRecord(from user: User, in loc: GroupLocation) async throws {
        let recordID = CKRecord.ID(recordName: try await myRecordName(), zoneID: loc.zoneID)

        let record: CKRecord
        do {
            record = try await loc.database.record(for: recordID)    // exists → update it
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.memberRecordType, recordID: recordID)  // new
        }

        Self.encode(user, into: record)
        try await loc.database.save(record)
    }

    // MARK: - Read all (for displaying the group)

    /// Fetch every member record in the group zone — from my private zone if I own the group, or
    /// from the shared zone I accepted if I'm a participant. Solo this is just my record; once
    /// others join and write theirs, it's everyone's.
    /// Requires the `recordName` queryable index in the CloudKit schema (added in the Console).
    func fetchAllMembers() async throws -> [User] {
        let myName = try await myRecordName()
        let loc = await resolveGroupLocation()
        let query = CKQuery(recordType: Self.memberRecordType, predicate: NSPredicate(value: true))
        let (matches, _) = try await loc.database.records(matching: query, inZoneWith: loc.zoneID)
        return matches.compactMap { _, result in
            guard case .success(let record) = result, var user = Self.decode(record) else { return nil }
            // Identify "me" by the stable per-user record name (not a per-launch random id), so it
            // holds across devices and relaunches.
            if record.recordID.recordName == myName { user.isCurrentUser = true }
            return user
        }
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
            ringColor: (record["ringColor"] as? String).flatMap(User.RingColor.init) ?? .pink
        )
    }
}
