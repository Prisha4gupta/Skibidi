import Foundation
import Combine

/// Backs the Settings tab: permission toggles and preference flags.
/// `@MainActor` — `@Published` mutations occur on the main thread.
@MainActor
final class SettingsViewModel: ObservableObject {
    /// Bound to the Notifications toggle. // REVIEW: local state only — not persisted or wired to any service.
    @Published var notificationsEnabled: Bool = true
    /// Bound to the Share-location toggle. // REVIEW: local state only — does not gate `locationService`.
    @Published var shareLocation: Bool = true
    /// Reflects the result of `requestHealthKitAccess`; drives the HealthKit status label.
    @Published var healthKitAuthorized: Bool = false

    private let healthService: HealthService
    private let locationService: LocationService

    init(healthService: HealthService, locationService: LocationService) {
        self.healthService = healthService
        self.locationService = locationService
    }

    /// "Connect HealthKit" intent: requests authorization and stores the result in `healthKitAuthorized`.
    func requestHealthKitAccess() async {
        do {
            // TODO: Surface real authorization status (granted/denied/notDetermined).
            healthKitAuthorized = try await healthService.requestAuthorization()
        } catch {
            healthKitAuthorized = false
        }
    }

    /// "Allow Location" intent: triggers the system authorization prompt. Synchronous — no state mutated here.
    func requestLocationAccess() {
        locationService.requestAuthorization()
    }
}
