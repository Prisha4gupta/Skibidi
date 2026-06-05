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

    private let database: CKDatabase

    init(container: CKContainer = .default()) {
        // `.default()` resolves to the first container in the entitlements — iCloud.com.bpjsr.skibidi.
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

        let snapshot = HealthSnapshot(
            steps:            record["steps"] as? Int ?? 0,
            stepsDistanceKm:  record["stepsDistanceKm"] as? Double ?? 0,
            sleepHours:       record["sleepHours"] as? Double ?? 0,
            restingHeartRate: record["restingHeartRate"] as? Int ?? 0,
            hydrationPercent: record["hydrationPercent"] as? Int ?? 0,
            moveCalories:     record["moveCalories"] as? Int ?? 0,
            moveGoal:         record["moveGoal"] as? Int ?? 0,
            exerciseMinutes:  record["exerciseMinutes"] as? Int ?? 0,
            exerciseGoal:     record["exerciseGoal"] as? Int ?? 0,
            standHours:       record["standHours"] as? Int ?? 0,
            standGoal:        record["standGoal"] as? Int ?? 0,
            activeCalories:   record["activeCalories"] as? Int ?? 0
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
