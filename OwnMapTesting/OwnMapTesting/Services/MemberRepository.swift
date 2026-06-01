import Foundation

protocol MemberRepository {
    func fetchMembers() async throws -> [Member]
}

final class MockMemberRepository: MemberRepository {
    func fetchMembers() async throws -> [Member] {
        Self.sampleMembers
    }

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
