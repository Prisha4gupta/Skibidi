import Foundation

/// An in-app notification/activity item. Domain model — no UI dependencies.
/// `Identifiable` via a stable `UUID` for SwiftUI list diffing.
struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    var message: String
    /// When the event occurred; used for ordering/relative display.
    var timestamp: Date
    /// Read/unread flag driving badge and styling.
    var isRead: Bool
}
