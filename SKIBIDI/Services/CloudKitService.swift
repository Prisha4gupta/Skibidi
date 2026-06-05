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

    /// A *stable* record name for "my own member record". Because the name is constant, every
    /// launch updates the same record instead of creating a new one (the smoke test's bug:
    /// it made a fresh random record each run). The private DB is per-iCloud-account, so one
    /// fixed name per app is unambiguous. (In the sharing milestone this moves into a custom
    /// shared zone with a per-person name.)
    static let myRecordName = "member-self"

    /// Custom zone that holds the (eventually shared) community's member records.
    /// The default zone can't be shared or change-tracked, so sharing *requires* a custom zone —
    /// this is the foundation `CKShare` is built on. For now it's one fixed zone in the owner's
    /// private DB; per-community zones arrive when real sharing lands.
    static let groupZoneID = CKRecordZone.ID(zoneName: "GroupZone", ownerName: CKCurrentUserDefaultName)

    private let container: CKContainer
    private let database: CKDatabase

    init(container: CKContainer = .default()) {
        // `.default()` resolves to the first container in the entitlements — iCloud.com.bpjsr.skibidi.
        self.container = container
        self.database = container.privateCloudDatabase
    }

    // MARK: - Public API

    /// High-level entry point called from the ViewModel: confirm iCloud is available, upsert
    /// the owner's record from their live `User`, then read it back to prove the round-trip.
    /// Never throws — failures are logged, because a sync hiccup shouldn't crash the app.
    func syncMyData(_ user: User) async {
        do {
            let status = try await CKContainer.default().accountStatus()
            guard status == .available else {
                print("☁️ [CloudKit] iCloud not available (status \(status.rawValue)). Sign in via Settings.")
                return
            }

            try await ensureZoneExists()
            try await upsertMyMemberRecord(from: user)
            print("☁️ [CloudKit] WRITE ok — \(Self.myRecordName) in zone \(Self.groupZoneID.zoneName)")

            if let record = try await fetchMyMemberRecord() {
                let steps = record["steps"] as? Int ?? -1
                let name = record["displayName"] as? String ?? "(none)"
                print("☁️ [CloudKit] READ ok — displayName=\(name), steps=\(steps)")
                print("🎉 [CloudKit] round-trip complete. Check Console → Data → Private DB.")
            }
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

    /// Save the owner's data to their stable record. Fetches the existing record first (so we
    /// hold the correct change tag), or creates a fresh one if none exists — i.e. an upsert.
    private func upsertMyMemberRecord(from user: User) async throws {
        let recordID = CKRecord.ID(recordName: Self.myRecordName, zoneID: Self.groupZoneID)

        let record: CKRecord
        do {
            record = try await database.record(for: recordID)        // exists → update it
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.memberRecordType, recordID: recordID)  // new
        }

        Self.encode(user, into: record)
        try await database.save(record)
    }

    // MARK: - Read

    /// Fetch the owner's record, or `nil` if it doesn't exist yet.
    private func fetchMyMemberRecord() async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: Self.myRecordName, zoneID: Self.groupZoneID)
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Mapping  (User / HealthSnapshot  ⟷  CKRecord)

    /// Translate a `User` into CloudKit fields. A `CKRecord` is dictionary-like; Swift `Int`,
    /// `Double`, and `String` bridge to CloudKit number/string types automatically. Enums are
    /// stored as their raw `String` so they survive the round-trip unambiguously.
    static func encode(_ user: User, into record: CKRecord) {
        record["userUUID"]        = user.id.uuidString          // keep the app-side identity
        record["displayName"]     = user.name
        record["emoji"]           = user.emoji
        record["status"]          = user.status.rawValue
        record["ringColor"]       = user.ringColor.rawValue
        record["latitude"]        = user.latitude
        record["longitude"]       = user.longitude
        record["locationSharing"] = user.locationSharing.rawValue
        record["healthSharing"]   = user.healthSharing.rawValue
        record["fitnessSharing"]  = user.fitnessSharing.rawValue

        let h = user.healthSnapshot
        record["steps"]            = h.steps
        record["stepsDistanceKm"]  = h.stepsDistanceKm
        record["sleepHours"]       = h.sleepHours
        record["restingHeartRate"] = h.restingHeartRate
        record["hydrationPercent"] = h.hydrationPercent
        record["moveCalories"]     = h.moveCalories
        record["moveGoal"]         = h.moveGoal
        record["exerciseMinutes"]  = h.exerciseMinutes
        record["exerciseGoal"]     = h.exerciseGoal
        record["standHours"]       = h.standHours
        record["standGoal"]        = h.standGoal
        record["activeCalories"]   = h.activeCalories
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
