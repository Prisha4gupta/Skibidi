import Foundation

/// Data-access boundary for roster, communities, and notifications. ViewModels depend on this
/// abstraction (not a concrete type) so the backing store can swap from mock to network/DB.
protocol MemberRepository {
    /// - Returns: the full member roster. Async to allow a future network/DB backing; throws on fetch failure.
    func fetchMembers() async throws -> [Member]
    /// - Returns: all communities with their member snapshots. Throws on fetch failure.
    func fetchCommunities() async throws -> [Community]
    /// - Returns: activity-feed notifications. Throws on fetch failure.
    func fetchNotifications() async throws -> [AppNotification]
}

/// In-memory `MemberRepository` returning static sample data for development/previews.
/// No real I/O — never actually throws; `async` only to satisfy the protocol contract.
final class MockMemberRepository: MemberRepository {
    func fetchMembers() async throws -> [Member] {
        Self.sampleMembers
    }

    /// Builds three sample communities from slices of `sampleMembers`.
    func fetchCommunities() async throws -> [Community] {
        [
            Community(
                id: UUID(),
                name: "Morning Joggers",
                subtitle: "Daily 6am run group",
                members: Array(Self.sampleMembers.prefix(3)),
                isActive: true
            ),
            Community(
                id: UUID(),
                name: "Office Buddies",
                subtitle: "Workplace wellness",
                members: Array(Self.sampleMembers.suffix(2)),
                isActive: true
            ),
            Community(
                id: UUID(),
                name: "Weekend Hikers",
                subtitle: "Trail outings",
                members: Self.sampleMembers,
                isActive: false
            )
        ]
    }

    func fetchNotifications() async throws -> [AppNotification] {
        [
            AppNotification(id: UUID(), message: "Alex is feeling tired today.",
                            timestamp: Date().addingTimeInterval(-3_600), isRead: false),
            AppNotification(id: UUID(), message: "Morning Joggers meet at 6am tomorrow.",
                            timestamp: Date().addingTimeInterval(-7_200), isRead: false),
            AppNotification(id: UUID(), message: "Your energy score updated.",
                            timestamp: Date().addingTimeInterval(-86_400), isRead: true)
        ]
    }

    // MARK: - Sample data
    /// Fixed roster (Jakarta-area coordinates) reused across mock fetches and previews.
    static let sampleMembers: [Member] = [
        Member(id: UUID(), name: "Alex Chen",
               avatar: "person.circle.fill",
               location: GeoPoint(latitude: -6.2088, longitude: 106.8456),
               conditionStatus: .tired,
               isActive: true,
               energyScore: 42),
        Member(id: UUID(), name: "Bella Rivera",
               avatar: "person.circle.fill",
               location: GeoPoint(latitude: -6.2150, longitude: 106.8500),
               conditionStatus: .energetic,
               isActive: true,
               energyScore: 88),
        Member(id: UUID(), name: "Chen Wei",
               avatar: "person.circle.fill",
               location: GeoPoint(latitude: -6.2000, longitude: 106.8200),
               conditionStatus: .normal,
               isActive: true,
               energyScore: 67),
        Member(id: UUID(), name: "Dani Kovac",
               avatar: "person.circle.fill",
               location: GeoPoint(latitude: -6.1900, longitude: 106.8600),
               conditionStatus: .exhausted,
               isActive: false,
               energyScore: 22),
        Member(id: UUID(), name: "Evan Park",
               avatar: "person.circle.fill",
               location: GeoPoint(latitude: -6.2300, longitude: 106.8300),
               conditionStatus: .normal,
               isActive: true,
               energyScore: 71)
    ]
}
