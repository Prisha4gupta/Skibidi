import Foundation

/// A named group of `Member`s shown in the Communities tab. Domain model — no UI dependencies.
/// `Identifiable` via a stable `UUID` for SwiftUI list diffing.
struct Community: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// One-line descriptor shown under the name (e.g. "Daily 6am run group").
    var subtitle: String
    /// Members embedded by value — a snapshot, not a live reference to the global roster.
    var members: [Member]
    var isActive: Bool
}
