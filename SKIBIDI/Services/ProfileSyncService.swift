import Foundation
import CloudKit

/// Pushes the locally-saved onboarding profile up to CloudKit. This is the **non-blocking** half
/// of local-first persistence: onboarding completes the moment the local save succeeds, and this
/// sync runs in the background (and is retried on next launch) without ever gating the flow.
///
/// NOTE: The real CloudKit path requires a **paid Apple Developer account** and the app's iCloud
/// container (iCloud.com.bpjsr.skibidi) — only the container owner can write on a real device.
/// Everywhere else (Simulator, teammates, no iCloud sign-in) this simply fails quietly and the
/// local profile remains the source of truth.
///
/// Follows the project DI shape: a protocol with a real (CloudKit) conformer and a `Mock`.
@MainActor
protocol ProfileSyncServiceProtocol {
    /// Upsert the profile to CloudKit. Throws on failure so the caller can keep `needsCloudSync`
    /// set and retry later. Must not be awaited on the critical onboarding-completion path.
    func sync(_ profile: StoredProfile) async throws
    /// Best-effort read of the previously-synced profile, for pre-filling onboarding on a
    /// reinstall/new device (Apple returns the name only on the first-ever authorization).
    /// `nil` when nothing was ever synced or iCloud isn't available — never throws, never blocks
    /// the flow.
    func fetch() async -> StoredProfile?
}

/// Real sync into the owner's **private** CloudKit database (default zone — a personal profile
/// doesn't need the shared `GroupZone`). Idempotent: it upserts a single `Profile` record.
@MainActor
final class CloudKitProfileSyncService: ProfileSyncServiceProtocol {
    static let profileRecordType = "Profile"

    private let container: CKContainer
    private let database: CKDatabase
    // Explicit container — `.default()` would resolve to iCloud.<bundle-id> (com.bpjsr.tim) and
    // miss the real container kept through the rename (see CloudKitService.containerID).
    init(container: CKContainer = CKContainer(identifier: CloudKitService.containerID)) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    func sync(_ profile: StoredProfile) async throws {
        // Bail early (throwing) if iCloud isn't usable, so the caller leaves `needsCloudSync` on.
        let status = try await container.accountStatus()
        guard status == .available else {
            throw CKError(.notAuthenticated)
        }

        // One stable record per device user. Fixed name is fine: it's the owner's own private DB.
        let recordID = CKRecord.ID(recordName: "myProfile")
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.profileRecordType, recordID: recordID)
        }

        record["appleUserID"] = profile.appleUserID as CKRecordValue?
        record["fullName"] = profile.fullName as CKRecordValue
        record["selectedEmoji"] = profile.selectedEmoji as CKRecordValue
        record["locationIntent"] = profile.locationIntent as CKRecordValue
        record["healthIntent"] = profile.healthIntent as CKRecordValue
        record["notificationsIntent"] = profile.notificationsIntent as CKRecordValue

        _ = try await database.save(record)
        print("☁️ [CloudKit] profile synced")
    }

    func fetch() async -> StoredProfile? {
        guard let status = try? await container.accountStatus(), status == .available else {
            return nil
        }
        let recordID = CKRecord.ID(recordName: "myProfile")
        guard let record = try? await database.record(for: recordID),
              let fullName = record["fullName"] as? String else {
            return nil
        }
        return StoredProfile(
            appleUserID: record["appleUserID"] as? String,
            fullName: fullName,
            selectedEmoji: record["selectedEmoji"] as? String ?? "",
            locationIntent: record["locationIntent"] as? Bool ?? true,
            healthIntent: record["healthIntent"] as? Bool ?? true,
            notificationsIntent: record["notificationsIntent"] as? Bool ?? true
        )
    }
}

/// In-memory sync for previews/tests. Records the last synced profile and can simulate failure.
@MainActor
final class MockProfileSyncService: ProfileSyncServiceProtocol {
    private(set) var lastSynced: StoredProfile?
    var syncError: Error?
    /// What `fetch()` returns — set this to exercise the onboarding pre-fill path in previews.
    var stubbedFetchResult: StoredProfile?

    init(error: Error? = nil) { self.syncError = error }

    func sync(_ profile: StoredProfile) async throws {
        if let syncError { throw syncError }
        lastSynced = profile
    }

    func fetch() async -> StoredProfile? { stubbedFetchResult }
}
