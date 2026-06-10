import Foundation
import CoreLocation
import UserNotifications

// MARK: - Onboarding permission policy
//
// The onboarding toggles are the SINGLE source of truth. On "Done", `OnboardingViewModel`
// `requestEnabledPermissions()` calls `request()` below for each toggle the user left on — that's
// the one and only place the system prompt fires. The map then *uses* the granted capabilities
// gated on the same saved intents (`CommunityViewModel.onAppear`) and never re-prompts, so the
// user isn't asked twice. The toggles are also persisted (`StoredProfile`) so the gate survives
// relaunches. Each service still exposes `request()` as the prompt seam; mocks stub it for tests.
//
// All three follow the project's DI shape (à la `AuthServiceProtocol`): a `@MainActor protocol`
// with a `Real…` conformer for devices and a `Mock…` conformer for previews/tests.

// MARK: - Location

@MainActor
protocol LocationPermissionServiceProtocol {
    /// Whether the capability exists on this device.
    var isAvailable: Bool { get }
    /// Point-of-use system prompt. NOT called during onboarding. Returns whether granted.
    @discardableResult
    func request() async -> Bool
}

/// Real location permission via `CLLocationManager`. Only the request seam is implemented here;
/// live location updates remain in the existing `LocationManager`.
@MainActor
final class RealLocationPermissionService: NSObject, LocationPermissionServiceProtocol, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Bool, Never>?

    var isAvailable: Bool { CLLocationManager.locationServicesEnabled() }

    @discardableResult
    func request() async -> Bool {
        let status = manager.authorizationStatus
        // Already decided — report the existing answer without re-prompting.
        if status != .notDetermined { return Self.isGranted(status) }

        manager.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return } // ignore the initial callback
        Task { @MainActor in
            self.continuation?.resume(returning: Self.isGranted(status))
            self.continuation = nil
        }
    }

    private static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

/// Canned location permission for previews/tests — never touches the system.
@MainActor
final class MockLocationPermissionService: LocationPermissionServiceProtocol {
    var isAvailable: Bool
    var stubbedGranted: Bool
    init(isAvailable: Bool = true, granted: Bool = true) {
        self.isAvailable = isAvailable
        self.stubbedGranted = granted
    }
    @discardableResult
    func request() async -> Bool { stubbedGranted }
}

// MARK: - Notifications

@MainActor
protocol NotificationPermissionServiceProtocol {
    var isAvailable: Bool { get }
    /// Point-of-use system prompt. NOT called during onboarding. Returns whether granted.
    @discardableResult
    func request() async -> Bool
}

/// Real notification permission via `UNUserNotificationCenter`.
@MainActor
final class RealNotificationPermissionService: NotificationPermissionServiceProtocol {
    var isAvailable: Bool { true }

    @discardableResult
    func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }
}

/// Canned notification permission for previews/tests.
@MainActor
final class MockNotificationPermissionService: NotificationPermissionServiceProtocol {
    var isAvailable: Bool
    var stubbedGranted: Bool
    init(isAvailable: Bool = true, granted: Bool = true) {
        self.isAvailable = isAvailable
        self.stubbedGranted = granted
    }
    @discardableResult
    func request() async -> Bool { stubbedGranted }
}

// MARK: - Health

@MainActor
protocol HealthPermissionServiceProtocol {
    var isAvailable: Bool { get }
    /// Point-of-use system prompt. NOT called during onboarding. Returns whether the prompt
    /// completed (HealthKit never reveals actual read-grant).
    @discardableResult
    func request() async -> Bool
}

/// Real health permission. Reuses the existing `HealthKitService` rather than duplicating any
/// HealthKit code — it owns the store, read types, and the authorization call (which presents
/// Apple's system health sheet). That request fires later, when the map first reads health.
@MainActor
final class RealHealthPermissionService: HealthPermissionServiceProtocol {
    private let healthKit: HealthKitService
    init(healthKit: HealthKitService = HealthKitService()) { self.healthKit = healthKit }

    var isAvailable: Bool { healthKit.isAvailable }

    @discardableResult
    func request() async -> Bool { await healthKit.requestAuthorization() }
}

/// Canned health permission for previews/tests.
@MainActor
final class MockHealthPermissionService: HealthPermissionServiceProtocol {
    var isAvailable: Bool
    var stubbedGranted: Bool
    init(isAvailable: Bool = true, granted: Bool = true) {
        self.isAvailable = isAvailable
        self.stubbedGranted = granted
    }
    @discardableResult
    func request() async -> Bool { stubbedGranted }
}
