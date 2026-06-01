import Foundation

// MARK: - Tunable thresholds
// TODO: Tune these with real data — they're first-pass defaults.
/// Namespaced scoring constants for `EnergyScore.compute`: per-component floors/targets,
/// component weights (must sum to 1.0), and the score→condition band boundaries.
enum EnergyScoreThresholds {
    // Steps (per day): floor → 0, target → 100 (linear in between)
    static let stepsFloor: Double = 1_000
    static let stepsTarget: Double = 10_000

    // Sleep (hours): floor → 0, target → 100
    static let sleepFloorHours: Double = 4.0
    static let sleepTargetHours: Double = 8.0

    // Resting heart rate (bpm): best (low) → 100, worst (high) → 0
    static let heartRateBest: Double = 55
    static let heartRateWorst: Double = 95

    // Component weights (must sum to 1.0)
    static let stepsWeight: Double = 0.4
    static let sleepWeight: Double = 0.4
    static let heartRateWeight: Double = 0.2

    // Condition bands by composite score (0–100)
    static let exhaustedUpperBound: Int = 35  // 0..<35
    static let tiredUpperBound: Int = 60      // 35..<60
    static let normalUpperBound: Int = 80     // 60..<80
                                              // 80..100 → energetic
}

/// Composite wellbeing score and its derived condition band. Pure value type holding the
/// domain scoring logic (a Model-layer calculation, intentionally free of UI/service deps).
struct EnergyScore: Codable, Hashable {
    let value: Int            // 0..100
    let condition: ConditionStatus

    /// Weighted blend of normalized steps, sleep, and (inverted) heart-rate components.
    /// - Parameter metric: raw health sample to score.
    /// - Returns: score clamped to 0...100 with its matching `ConditionStatus` band.
    static func compute(from metric: HealthMetric) -> EnergyScore {
        let stepsComponent = normalize(
            value: Double(metric.steps),
            floor: EnergyScoreThresholds.stepsFloor,
            target: EnergyScoreThresholds.stepsTarget
        )
        let sleepComponent = normalize(
            value: metric.sleepHours,
            floor: EnergyScoreThresholds.sleepFloorHours,
            target: EnergyScoreThresholds.sleepTargetHours
        )
        let heartComponent = normalizeInverse(
            value: Double(metric.heartRate),
            best: EnergyScoreThresholds.heartRateBest,
            worst: EnergyScoreThresholds.heartRateWorst
        )

        let composite =
            stepsComponent * EnergyScoreThresholds.stepsWeight +
            sleepComponent * EnergyScoreThresholds.sleepWeight +
            heartComponent * EnergyScoreThresholds.heartRateWeight

        let scoreInt = Int(composite.rounded())
        return EnergyScore(value: scoreInt, condition: condition(for: scoreInt))
    }

    /// Maps a 0...100 score to its `ConditionStatus` band per `EnergyScoreThresholds`.
    /// Shared by Views (e.g. MemberPin) so band logic stays in one place.
    static func condition(for score: Int) -> ConditionStatus {
        switch score {
        case ..<EnergyScoreThresholds.exhaustedUpperBound: return .exhausted
        case ..<EnergyScoreThresholds.tiredUpperBound:     return .tired
        case ..<EnergyScoreThresholds.normalUpperBound:    return .normal
        default:                                           return .energetic
        }
    }

    /// Linear 0→100 ramp: `floor` and below → 0, `target` and above → 100. Higher is better.
    private static func normalize(value: Double, floor: Double, target: Double) -> Double {
        guard target > floor else { return 0 }
        let clamped = max(floor, min(target, value))
        return ((clamped - floor) / (target - floor)) * 100
    }

    /// Inverted ramp for metrics where lower is better (heart rate): `best` → 100, `worst` → 0.
    private static func normalizeInverse(value: Double, best: Double, worst: Double) -> Double {
        guard worst > best else { return 0 }
        let clamped = max(best, min(worst, value))
        return (1 - (clamped - best) / (worst - best)) * 100
    }
}
