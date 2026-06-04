import CloudKit

/// TEMPORARY connectivity check. Confirms signing + container + entitlements
/// are wired correctly by writing one record and reading it back.
/// Delete this file (and its call in SKIBIDIApp) once CloudKitService exists.
enum CloudKitSmokeTest {
    static func run() async {
        let container = CKContainer.default()      // resolves to iCloud.com.bpjsr.skibidi
        let db = container.privateCloudDatabase

        // 1. Is the device signed into iCloud?
        do {
            let status = try await container.accountStatus()
            print("☁️ iCloud account status:", status.rawValue, "(1 = available)")
            guard status == .available else {
                print("❌ iCloud not available on this device. Sign in via Settings first.")
                return
            }
        } catch {
            print("❌ accountStatus failed:", error)
            return
        }

        // 2. WRITE one Members record to the private database
        let record = CKRecord(recordType: "Members")
        record["displayName"] = "Smoke Test ✅"
        do {
            let saved = try await db.save(record)
            print("✅ WRITE ok. recordName =", saved.recordID.recordName)

            // 3. READ it back by ID
            let fetched = try await db.record(for: saved.recordID)
            let name = fetched["displayName"] as? String ?? "(empty)"
            print("✅ READ ok. displayName =", name)
            print("🎉 CloudKit is connected. Check it in Console → Data → Private DB.")
        } catch {
            print("❌ WRITE/READ failed:", error)
        }
    }
}
