import Foundation
import CoreLocation

// MARK: - Member Status
enum MemberStatus: String, Codable, CaseIterable {
    case active = "Active"
    case normal = "Normal"
    case inactive = "Inactive"
}

// MARK: - Community Type
enum CommunityType: String, Codable, CaseIterable {
    case detail = "Detail"
    case travel = "Travel"
}

// MARK: - Privacy Level
enum PrivacyLevel: String, Codable, CaseIterable {
    case nobody = "Nobody"
    case contactsOnly = "Contacts Only"
    case everyone = "Everyone"
}

// MARK: - Sharing State
/// Per-category sharing consent for a member's location / health / fitness data.
/// Three states, because "off" means two different things:
/// - `.never`: never enabled — there is **no data at all** to show.
/// - `.paused`: was enabled, then paused — show the **last received data, frozen** (stale).
/// - `.active`: sharing live; data updates normally.
enum SharingState: String, Codable, Hashable, CaseIterable {
    case never
    case paused
    case active

    /// Whether any data is available to display (paused keeps the last snapshot; never has none).
    var hasData: Bool { self != .never }
    /// Whether the shown data is the live, updating value.
    var isLive: Bool { self == .active }
    /// Whether the shown data is a frozen last-known snapshot.
    var isStale: Bool { self == .paused }

    var label: String {
        switch self {
        case .never: return "Not shared"
        case .paused: return "Paused · last known"
        case .active: return "Live"
        }
    }
}

// MARK: - User Model
struct User: Identifiable, Hashable {
    let id: UUID
    /// Apple's stable Sign in with Apple identifier (`ASAuthorizationAppleIDCredential.user`).
    /// Durable across launches/devices for the same Apple account — unlike `id`, which is a
    /// transient app-local UUID. `nil` until the user signs in during onboarding. This is the
    /// key we sync to CloudKit and use to recognize a returning user.
    var appleUserID: String? = nil
    var name: String
    var emoji: String
    var isCurrentUser: Bool
    var status: MemberStatus
    var healthSnapshot: HealthSnapshot
    var latitude: Double
    var longitude: Double

    // MARK: - Data-sharing consent
    // What this member shares, per category. The app enforces these automatically (no settings
    // UI): a `.never` location keeps them off the map entirely; `.paused` freezes them at their
    // last spot; health/fitness gate the same way in profiles. Defaulted so initializers that
    // don't specify them get a live member.
    var locationSharing: SharingState = .active
    var healthSharing: SharingState = .active
    var fitnessSharing: SharingState = .active

    /// Active emergency SOS message broadcast by this member, or `nil` when none. Synced to
    /// CloudKit per-community: the audience the sender picked in "Send to" is enforced by *which*
    /// community zones this field gets written into (see `CloudKitService.syncMyData`), so the
    /// chosen people read the red pin + message and everyone else sees `nil`.
    var sosMessage: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Energy score to display, or `nil` when health isn't shared at all (`.never`).
    /// `.paused` still returns the last-known score (rendered as stale by the UI).
    var displayedEnergyScore: Int? {
        healthSharing.hasData ? healthSnapshot.energyScore : nil
    }
    
    // Ring color for map pins
    var ringColor: RingColor
    
    enum RingColor: String, CaseIterable {
        case pink, green, purple, orange, cyan
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Community Model
struct Community: Identifiable {
    let id: UUID
    var name: String
    var type: CommunityType
    var imageData: Data?
    var members: [User]
    var dateActive: Date
    var memberCount: Int
    var isLocationSharing: Bool
    var isHealthSharing: Bool
    var isFitnessSharing: Bool
    var hasNotification: Bool
    var notificationMessage: String?
    
    var activeMembers: [User] {
        members.filter { $0.status == .active }
    }
}

// MARK: - Health Snapshot
struct HealthSnapshot: Hashable {
    /// Pre-HealthKit placeholder: every metric zero, but ring goals at Apple's defaults —
    /// HealthKit supplies no goals, so zeroed goals would pin ring progress at 0 forever.
    static let empty = HealthSnapshot(
        steps: 0, stepsDistanceKm: 0, sleepHours: 0, restingHeartRate: 0, hrv: 0, respiratoryRate: 0,
        moveCalories: 0, moveGoal: 500, exerciseMinutes: 0, exerciseGoal: 30,
        standHours: 0, standGoal: 12, activeCalories: 0
    )

    var steps: Int
    var stepsDistanceKm: Double
    var sleepHours: Double
    var restingHeartRate: Int
    var hrv: Double            // HRV (SDNN) in ms; 0 = unavailable
    var respiratoryRate: Double // breaths/min; 0 = unavailable
    var moveCalories: Int
    var moveGoal: Int
    var exerciseMinutes: Int
    var exerciseGoal: Int
    var standHours: Int
    var standGoal: Int
    var activeCalories: Int
    
    var energyScore: Int {
        // Option 3 — "readiness minus exertion" fatigue model. Energy = how tired a traveler is:
        // it starts high after good rest (readiness) and drains as they walk/exert through the day
        // (fatigue). Low score = tired. Result is clamped to 0...100 so the existing
        // `energyColor` / `energyStatusText` thresholds still apply.
        //
        // Tuning: the reference numbers below (the divisors like 15000.0) set how fast each input
        // saturates. LOWERING a reference number makes people tire faster / recover quicker on that
        // axis (it takes less to reach the cap); RAISING it makes people tire slower / recover more
        // gradually (it takes more to reach the cap). The trailing multipliers are each axis's max
        // point contribution.

        // Readiness — how recovered they are (max 100). Recovery (HRV + respiratory) joins
        // sleep and resting HR when the hardware supplies it; without any recovery data its
        // 30 points are redistributed to sleep/HR so the scale stays 0...100.
        let recovery = recoveryComponent
        let hasRecovery = recovery >= 0

        // Readiness weights: with recovery -> sleep 50 / HR 20 / recovery 30
        //                    without       -> sleep 70 / HR 30 (recovery dropped, points redistributed)
        let sleepWeight = hasRecovery ? 50.0 : 70.0
        let hrWeight    = hasRecovery ? 20.0 : 30.0

        let sleepReadiness = min(sleepHours / 8.0, 1.0) * sleepWeight   // 8h sleep = full recovery
        let hrDeviation = min(abs(Double(restingHeartRate) - 65.0) / 35.0, 1.0) // calm ~65 bpm = best
        let hrReadiness = hrWeight * (1.0 - hrDeviation)
        let recoveryReadiness = hasRecovery ? recovery * 30.0 : 0.0
        let readiness = sleepReadiness + hrReadiness + recoveryReadiness

        // Fatigue — how much they've exerted today (max ~100 at a hard day of travel).
        let stepsFatigue = min(Double(steps) / 15000.0, 1.0) * 50.0      // walking drains most
        let calorieFatigue = min(Double(activeCalories) / 600.0, 1.0) * 30.0 // effort burned
        let exerciseFatigue = min(Double(exerciseMinutes) / 90.0, 1.0) * 20.0 // sustained activity
        let fatigue = stepsFatigue + calorieFatigue + exerciseFatigue

        return Int(min(max(readiness - fatigue, 0.0), 100.0))
    }

    /// Recovery composite (x) — autonomic recovery, blends HRV + respiratory stability.
    /// Sub-inputs collapse gracefully when hardware data is missing (iPhone-only / partial
    /// Watch). Returns 0...1, or -1 when no recovery data exists at all.
    private var recoveryComponent: Double {
        let hasHRV  = hrv > 0
        let hasResp = respiratoryRate > 0

        let hrvComponent = min(hrv / 60.0, 1.0)                          // ~60ms SDNN = full credit
        let respDeviation = min(abs(respiratoryRate - 14.0) / 6.0, 1.0)  // calm ~14 br/min
        let respComponent = 1.0 - respDeviation

        switch (hasHRV, hasResp) {
        case (true, true):   return hrvComponent * 0.7 + respComponent * 0.3
        case (true, false):  return hrvComponent
        case (false, true):  return respComponent
        case (false, false): return -1
        }
    }

    /// Recovery on a 0–100 scale for display; nil when neither HRV nor respiratory data exists.
    var recoveryScore: Int? {
        let component = recoveryComponent
        guard component >= 0 else { return nil }
        return Int((component * 100).rounded())
    }

    /// Soft status word for the Recovery tile subtitle (never shows raw HRV ms).
    var recoveryStatusText: String {
        guard let score = recoveryScore else { return "No data" }
        switch score {
        case ..<34: return "Low"
        case ..<67: return "Fair"
        default:    return "Good"
        }
    }


    var moveProgress: Double {
        guard moveGoal > 0 else { return 0 }
        return min(Double(moveCalories) / Double(moveGoal), 1.0)
    }
    
    var exerciseProgress: Double {
        guard exerciseGoal > 0 else { return 0 }
        return min(Double(exerciseMinutes) / Double(exerciseGoal), 1.0)
    }
    
    var standProgress: Double {
        guard standGoal > 0 else { return 0 }
        return min(Double(standHours) / Double(standGoal), 1.0)
    }
    
    var suggestion: String {
        if steps > 30000 {
            return "Suggestion: \(steps) steps already, consider a long break."
        } else if sleepHours < 6 {
            return "Suggestion: You slept less than 6 hours. Try resting early tonight."
        } else if let recovery = recoveryScore, recovery < 34 {
            return "Suggestion: Recovery is low. Take it easy today."
        } else {
            return "Suggestion: Looking good! Keep up the healthy habits."
        }
    }
}

// MARK: - App Notification
struct AppNotification: Identifiable {
    let id: UUID
    var communityName: String
    var communityEmoji: String
    var message: String
    var timestamp: Date
    var isRead: Bool
}
