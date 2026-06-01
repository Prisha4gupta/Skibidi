import Foundation

// MARK: - Tunable thresholds
// TODO: Tune these once real score data is in.
enum EnergyScoreThresholds {
    static let exhaustedUpperBound: Int = 35  // 0..<35
    static let tiredUpperBound: Int = 60      // 35..<60
    static let normalUpperBound: Int = 80     // 60..<80
                                              // 80..100 → energetic
}

struct EnergyScore {
    /// Maps a raw 0–100 score to a condition band.
    static func condition(for score: Int) -> ConditionStatus {
        switch score {
        case ..<EnergyScoreThresholds.exhaustedUpperBound: return .exhausted
        case ..<EnergyScoreThresholds.tiredUpperBound:     return .tired
        case ..<EnergyScoreThresholds.normalUpperBound:    return .normal
        default:                                           return .energetic
        }
    }
}
