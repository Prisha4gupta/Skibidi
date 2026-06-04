# SKIBIDI — CloudKit Architecture

Find My + Health/Fitness with group-based sharing: multi-user, real-time, with a per-member sharing toggle.

---

## A. Layered Stack

```mermaid
flowchart TB
    subgraph UI["Presentation · SwiftUI"]
        V1[PeopleMapView]
        V2[CommunityDetailViews]
        V3["HealthComponents / ActivityRingView"]
    end
    subgraph VM["State · ViewModels (ObservableObject)"]
        VMx["Bind UI ↔ data<br/>compute energyScore, progress"]
    end
    subgraph DATA["Data Layer · protocol DataService"]
        MOCK["MockDataService<br/>(hardcoded, current)"]
        CK["CloudKitService<br/>(target)"]
    end
    subgraph DEV["Device Frameworks"]
        HK[HealthKit]
        CL[CoreLocation]
        MK[MapKit]
    end
    SYNC["CloudKit Sync<br/>CKSyncEngine + CKSubscription"]
    CLOUD["☁️ iCloud · Private DB + Shared DB<br/>🔒 requires Apple Developer Program"]

    UI --> VM --> DATA
    MOCK -. "swap, UI unchanged" .-> CK
    CK --> HK
    CK --> CL
    UI --> MK
    HK --> SYNC
    CL --> SYNC
    SYNC --> CLOUD
    CLOUD -. "APNs silent push" .-> SYNC
```

The key seam is `protocol DataService`. Because the UI only talks to that protocol, swapping `MockDataService` for `CloudKitService` requires no changes to any View.

---

## B. Sharing Topology (Privacy Model)

```mermaid
flowchart TB
    subgraph ZONE["🔗 Shared Zone: Group 16 — one zone, shared with all three"]
        G[Group record]
        ML["Member[me]"]
        MJ["Member[jason]"]
        MR["Member[rania]"]
    end

    ME["📱 ME"] -->|writes own| ML
    JASON["📱 JASON"] -->|writes own| MJ
    RANIA["📱 RANIA"] -->|writes own| MR

    ZONE -->|everyone READS all| ME
    ZONE -->|everyone READS all| JASON
    ZONE -->|everyone READS all| RANIA

    RANIA -.->|"sharesHealth = 0 → health fields DELETED from zone"| MR
```

Each person **writes** only their own `Member` record but **reads** all of them. Turning a toggle off deletes the data from the cloud entirely — it is not merely hidden in the UI. That makes the privacy story real and demoable.

---

## C. Real-Time Data Flow (single update)

```mermaid
sequenceDiagram
    participant HK as HealthKit (Jason's phone)
    participant CK as CloudKitService
    participant IC as iCloud
    participant AP as APNs
    participant ME as My phone + Rania's
    participant UI as SwiftUI

    HK->>CK: observer query (walked 500 steps)
    CK->>IC: update Member[jason].steps
    IC->>AP: trigger subscription
    AP-->>ME: silent push
    ME->>IC: fetch zone changes (CKSyncEngine)
    IC-->>ME: only the changed records
    ME->>UI: update @Published
    UI->>UI: Jason's ActivityRingView re-renders ✨
```

---

## Schema Summary

**Group** (from `Community`): `name`, `type`, `dateActive`, `coverImage: Asset?`, `defaultLocationSharing / defaultHealthSharing / defaultFitnessSharing: Int64`

**Member** (from `User` + `HealthSnapshot`): `userRecordName`, `displayName`, `emoji`, `ringColor`, `status`, `sharesLocation / sharesHealth / sharesFitness: Int64`, `location: CLLocation?`, `locationUpdatedAt`, plus the health fields (`steps`, `stepsDistanceKm`, `sleepHours`, `restingHeartRate`, `hydrationPercent`, `moveCalories`, `moveGoal`, `exerciseMinutes`, `exerciseGoal`, `standHours`, `standGoal`, `activeCalories`, `healthUpdatedAt`).

> `energyScore`, `moveProgress`, and `memberCount` are computed on the client — do **not** store them.
> `AppNotification` is generated on the client from sync events — no record type needed.

---

## CloudKit Primer

**Five core objects:**
- `CKContainer` — your app's iCloud container (`CKContainer.default()`).
- `CKDatabase` — `.privateCloudDatabase` / `.sharedCloudDatabase` / `.publicCloudDatabase`.
- `CKRecord` — one row of data. Dictionary-like: `record["steps"] = 31143`. Has a `recordType` and a `recordID`.
- `CKRecordZone` — a "folder". A custom zone is required for sharing and change tracking.
- `CKShare` — the object that makes a zone/record shareable with other iCloud users.

**Hello world — write & read (private DB; experiment here before touching sharing):**
```swift
import CloudKit

let db = CKContainer.default().privateCloudDatabase

// WRITE
let rec = CKRecord(recordType: "Member")
rec["displayName"] = "Your Name"
rec["steps"] = 31143
let saved = try await db.save(rec)

// READ
let fetched = try await db.record(for: saved.recordID)
print(fetched["displayName"] as? String ?? "")
```

**Three beginner gotchas:**
1. **Fields are auto-typed on first write.** CloudKit infers a field's type the first time you save a value to it; a wrong type sticks. Prefer defining the schema in the CloudKit Dashboard first.
2. **The default zone can't be shared and has no change tracking.** For sharing/sync you must create a custom `CKRecordZone`.
3. **Development and Production schemas are separate.** Once stable, "Deploy to Production" in the Dashboard, or your released build will error.

**Further learning:**
- Apple docs: *CloudKit*, *Sharing CloudKit Data with Other iCloud Users*.
- WWDC: "Get the most out of CloudKit Sharing", "Sync to iCloud with CKSyncEngine" (2023).
