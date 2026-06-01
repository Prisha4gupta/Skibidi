import Foundation
import CoreLocation

/// Coarse wellbeing band derived from a member's energy score; the app's shared
/// vocabulary for condition across Models, ViewModels, and Views.
/// Raw `String` values are the stable Codable representation.
enum ConditionStatus: String, Codable, CaseIterable {
    case energetic
    case normal
    case tired
    case exhausted

    /// Human-facing label for UI; decoupled from the raw Codable value.
    var displayName: String {
        switch self {
        case .energetic: return "Energetic"
        case .normal:    return "Normal"
        case .tired:     return "Tired"
        case .exhausted: return "Exhausted"
        }
    }
}

/// Codable-friendly latitude/longitude pair. Exists because `CLLocationCoordinate2D`
/// is not `Codable`/`Hashable`; `coordinate` bridges to MapKit/CoreLocation at the View layer.
struct GeoPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A person rendered on the map and in member lists. Domain model — no UI dependencies.
/// `Identifiable` via a stable `UUID` so SwiftUI can diff annotations/rows across reloads.
struct Member: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// SF Symbol name used as the avatar glyph (e.g. "person.circle.fill").
    var avatar: String
    var location: GeoPoint
    /// Stored condition band. // REVIEW: duplicates `energyScore` as a second source of
    /// truth — can drift from `EnergyScore.condition(for: energyScore)` (see MemberPin).
    var conditionStatus: ConditionStatus
    var isActive: Bool
    /// Latest composite energy score, 0...100. Pre-computed snapshot; not recomputed from metrics here.
    var energyScore: Int
}
