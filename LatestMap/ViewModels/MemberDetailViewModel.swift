import Foundation
import Combine  

/// Backs the member detail screen: holds the selected member and its freshly fetched health
/// metric + derived energy score. `@MainActor` — `@Published` mutations occur on the main thread.
@MainActor
final class MemberDetailViewModel: ObservableObject {
    /// The member being viewed; `private(set)` as the View only reads it.
    @Published private(set) var member: Member
    /// Latest fetched metric, nil until `refresh` succeeds.
    @Published var latestMetric: HealthMetric?
    /// Energy score derived from `latestMetric` via `EnergyScore.compute`.
    @Published var energyScore: EnergyScore?
    /// Drives a loading indicator during `refresh`.
    @Published var isLoading: Bool = false
    /// Non-nil surfaces a fetch error to the View.
    @Published var errorMessage: String?

    private let healthService: HealthService

    init(member: Member, healthService: HealthService) {
        self.member = member
        self.healthService = healthService
    }

    /// Fetch intent (`.task`/pull-to-refresh): authorizes, fetches the latest metric, recomputes score.
    /// Toggles `isLoading`; sets `errorMessage` on failure.
    /// - Note: `fetchLatestMetric()` is not member-scoped — see HealthService REVIEW; the score shown
    ///   reflects the device owner, not `member`.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // TODO: Real HealthKit auth flow gating — for now we assume granted.
            _ = try await healthService.requestAuthorization()
            let metric = try await healthService.fetchLatestMetric()
            latestMetric = metric
            energyScore = EnergyScore.compute(from: metric)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
