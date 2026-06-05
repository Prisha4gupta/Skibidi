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
    var steps: Int
    var stepsDistanceKm: Double
    var sleepHours: Double
    var restingHeartRate: Int
    var hydrationPercent: Int
    var moveCalories: Int
    var moveGoal: Int
    var exerciseMinutes: Int
    var exerciseGoal: Int
    var standHours: Int
    var standGoal: Int
    var activeCalories: Int
    
    var energyScore: Int {
        // Weighted formula: steps 40%, sleep 20%, heartRate 20%, activeCalories 20%
        let stepsScore = min(Double(steps) / 10000.0, 1.0) * 40.0
        let sleepScore = min(sleepHours / 8.0, 1.0) * 20.0
        let hrScore = (restingHeartRate >= 50 && restingHeartRate <= 80)
            ? 20.0 * (1.0 - abs(Double(restingHeartRate) - 65.0) / 35.0)
            : 5.0
        let calScore = min(Double(activeCalories) / 500.0, 1.0) * 20.0
        return Int(stepsScore + sleepScore + hrScore + calScore)
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
        } else if hydrationPercent < 50 {
            return "Suggestion: Hydration is low. Drink more water today."
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
