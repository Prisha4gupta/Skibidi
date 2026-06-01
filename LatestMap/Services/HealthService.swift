import Foundation

/// Boundary for health-data access (HealthKit in production). ViewModels depend on this
/// abstraction so the backing store can swap from mock to real `HKHealthStore`.
protocol HealthService {
    /// Requests read authorization.
    /// - Returns: `true` if granted. Throws if the underlying store errors.
    func requestAuthorization() async throws -> Bool
    /// - Returns: the most recent `HealthMetric`. Throws on read failure.
    /// - Note: no member parameter — only ever returns the current device user's data. // REVIEW:
    ///   MemberDetailViewModel uses this for an arbitrary member, so detail screens show
    ///   the device owner's metrics, not the selected member's.
    func fetchLatestMetric() async throws -> HealthMetric
}

/// Stub `HealthService` returning randomized metrics for development/previews.
/// Always grants authorization; never actually throws.
final class MockHealthService: HealthService {
    func requestAuthorization() async throws -> Bool {
        // TODO: Replace with real HKHealthStore.requestAuthorization(toShare:read:)
        return true
    }

    /// - Returns: a freshly randomized metric timestamped `now`; values are not member-specific.
    func fetchLatestMetric() async throws -> HealthMetric {
        // TODO: Replace with real HKStatisticsQuery / HKSampleQuery reads.
        HealthMetric(
            steps: Int.random(in: 2_000...12_000),
            sleepHours: Double.random(in: 4.0...8.5),
            heartRate: Int.random(in: 55...90),
            timestamp: Date()
        )
    }
}
