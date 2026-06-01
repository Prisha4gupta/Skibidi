import Foundation
import CoreLocation

enum ConditionStatus: String, Codable, CaseIterable {
    case energetic
    case normal
    case tired
    case exhausted

    var displayName: String {
        switch self {
        case .energetic: return "Energetic"
        case .normal:    return "Normal"
        case .tired:     return "Tired"
        case .exhausted: return "Exhausted"
        }
    }
}

struct GeoPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct Member: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var avatar: String
    var location: GeoPoint
    var conditionStatus: ConditionStatus
    var isActive: Bool
    var energyScore: Int
}
