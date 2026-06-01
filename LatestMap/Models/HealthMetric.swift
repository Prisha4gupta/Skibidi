import Foundation

/// A point-in-time health sample (the raw input to `EnergyScore.compute`).
/// Domain model mirroring HealthKit reads; no UI dependencies.
struct HealthMetric: Codable, Hashable {
    /// Step count for the sampled period.
    var steps: Int
    /// Sleep duration in hours.
    var sleepHours: Double
    /// Resting heart rate in bpm; lower is better for scoring.
    var heartRate: Int
    /// When the sample was taken.
    var timestamp: Date
}
