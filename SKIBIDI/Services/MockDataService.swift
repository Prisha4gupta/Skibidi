import Foundation
import CoreLocation

/// Provides mock data for all screens matching the exact values from hi-fi designs.
///
/// Conforms to `DataService` — it already exposed `currentUser`, `communities`,
/// `notifications`, and `mapCenter`, so satisfying the contract needs nothing new.
@MainActor
class MockDataService: DataService {
    static let shared = MockDataService()
    
    // MARK: - Bali Area Coordinates
    private let baliCenter = CLLocationCoordinate2D(latitude: -8.4095, longitude: 115.1889)
    
    // MARK: - Mock Users
    lazy var currentUser: User = {
        User(
            id: UUID(),
            name: "Your Name",
            emoji: "👻",
            isCurrentUser: true,
            status: .active,
            healthSnapshot: HealthSnapshot(
                steps: 31143,
                stepsDistanceKm: 11.1,
                sleepHours: 6.5,
                restingHeartRate: 71,
                hydrationPercent: 87,
                moveCalories: 125,
                moveGoal: 500,
                exerciseMinutes: 15,
                exerciseGoal: 30,
                standHours: 5,
                standGoal: 12,
                activeCalories: 125
            ),
            latitude: -8.5069,
            longitude: 115.2625,
            ringColor: .pink
        )
    }()
    
    lazy var member1: User = {
        User(
            id: UUID(),
            name: "Member 1",
            emoji: "😍",
            isCurrentUser: false,
            status: .active,
            healthSnapshot: HealthSnapshot(
                steps: 31143,
                stepsDistanceKm: 11.1,
                sleepHours: 6.5,
                restingHeartRate: 71,
                hydrationPercent: 87,
                moveCalories: 125,
                moveGoal: 500,
                exerciseMinutes: 15,
                exerciseGoal: 30,
                standHours: 5,
                standGoal: 12,
                activeCalories: 125
            ),
            latitude: -8.4800,
            longitude: 115.2400,
            ringColor: .green
        )
    }()
    
    lazy var member2: User = {
        User(
            id: UUID(),
            name: "Member 2",
            emoji: "🤪",
            isCurrentUser: false,
            status: .active,
            healthSnapshot: HealthSnapshot(
                steps: 18420,
                stepsDistanceKm: 7.8,
                sleepHours: 7.2,
                restingHeartRate: 68,
                hydrationPercent: 92,
                moveCalories: 280,
                moveGoal: 500,
                exerciseMinutes: 22,
                exerciseGoal: 30,
                standHours: 8,
                standGoal: 12,
                activeCalories: 280
            ),
            latitude: -8.5200,
            longitude: 115.2800,
            locationSharing: .active,
            healthSharing: .paused,   // on the map, but health frozen at last reading
            fitnessSharing: .active,
            ringColor: .purple
        )
    }()
    
    lazy var member3: User = {
        User(
            id: UUID(),
            name: "Member 3",
            emoji: "😎",
            isCurrentUser: false,
            status: .active,
            healthSnapshot: HealthSnapshot(
                steps: 8500,
                stepsDistanceKm: 4.2,
                sleepHours: 8.0,
                restingHeartRate: 62,
                hydrationPercent: 75,
                moveCalories: 350,
                moveGoal: 500,
                exerciseMinutes: 28,
                exerciseGoal: 30,
                standHours: 10,
                standGoal: 12,
                activeCalories: 350
            ),
            latitude: -8.4600,
            longitude: 115.2200,
            locationSharing: .paused,   // frozen on the map at last known spot
            healthSharing: .active,
            fitnessSharing: .never,     // never shared fitness → no rings
            ringColor: .orange
        )
    }()
    
    lazy var member4: User = {
        User(
            id: UUID(),
            name: "Member 4",
            emoji: "🥳",
            isCurrentUser: false,
            status: .normal,
            healthSnapshot: HealthSnapshot(
                steps: 5200,
                stepsDistanceKm: 2.5,
                sleepHours: 5.5,
                restingHeartRate: 78,
                hydrationPercent: 60,
                moveCalories: 100,
                moveGoal: 500,
                exerciseMinutes: 8,
                exerciseGoal: 30,
                standHours: 3,
                standGoal: 12,
                activeCalories: 100
            ),
            latitude: -8.5400,
            longitude: 115.3000,
            locationSharing: .never,    // never shared location → off the map entirely
            healthSharing: .never,      // never shared health → no health data
            fitnessSharing: .never,
            ringColor: .cyan
        )
    }()
    
    // MARK: - Mock Communities
    lazy var communities: [Community] = {
        [
            Community(
                id: UUID(),
                name: "Group 16 BPJS-R",
                type: .detail,
                imageData: nil,
                members: [currentUser, member1, member2, member3, member4],
                dateActive: Date(),
                memberCount: 5,
                isLocationSharing: true,
                isHealthSharing: true,
                isFitnessSharing: true,
                hasNotification: true,
                notificationMessage: "You have a new notification"
            ),
            Community(
                id: UUID(),
                name: "Ubud Trip",
                type: .travel,
                imageData: nil,
                members: [currentUser, member1, member2],
                dateActive: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!,
                memberCount: 3,
                isLocationSharing: true,
                isHealthSharing: true,
                isFitnessSharing: true,
                hasNotification: false,
                notificationMessage: nil
            ),
            Community(
                id: UUID(),
                name: "Bedugul Holiday",
                type: .travel,
                imageData: nil,
                members: [currentUser, member3, member4],
                dateActive: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!,
                memberCount: 3,
                isLocationSharing: true,
                isHealthSharing: false,
                isFitnessSharing: true,
                hasNotification: false,
                notificationMessage: nil
            )
        ]
    }()
    
    // MARK: - Mock Notifications
    lazy var notifications: [AppNotification] = {
        [
            AppNotification(
                id: UUID(),
                communityName: "Group 16 BPJS-R",
                communityEmoji: "👥",
                message: "New member joined the community",
                timestamp: Date().addingTimeInterval(-3600),
                isRead: false
            ),
            AppNotification(
                id: UUID(),
                communityName: "Ubud Trip",
                communityEmoji: "🌴",
                message: "Trip date is approaching!",
                timestamp: Date().addingTimeInterval(-7200),
                isRead: false
            ),
            AppNotification(
                id: UUID(),
                communityName: "Bedugul Holiday",
                communityEmoji: "⛰️",
                message: "Location sharing enabled",
                timestamp: Date().addingTimeInterval(-86400),
                isRead: true
            )
        ]
    }()
    
    // MARK: - Map Center
    var mapCenter: CLLocationCoordinate2D {
        baliCenter
    }
}
