import Foundation
import CoreLocation
import Observation

/// Live device-location source backed by `CLLocationManager`, exposed in SKIBIDI's
/// `@Observable` style so the map/ViewModel can react to the current user's real position.
///
/// Adapted from LatestMap's `RealLocationService` (Combine) to the Observation framework:
/// instead of a publisher, callers read `currentLocation` directly or set `onLocationUpdate`
/// to be notified on each new fix. All mutations happen on the main actor.
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// Most recent device coordinate; `nil` until authorized and a first fix arrives.
    var currentLocation: CLLocationCoordinate2D?
    /// Latest authorization decision; drives whether updates are flowing.
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Optional hook fired on the main actor with each new fix. The ViewModel sets this to
    /// move the current user's pin / recenter the map. Ignored by Observation (not UI state).
    @ObservationIgnored var onLocationUpdate: ((CLLocationCoordinate2D) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25 // metres of movement before a new update fires
        authorizationStatus = manager.authorizationStatus
    }

    /// Prompts for when-in-use authorization (no-op once decided). Side effect: system dialog.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Begins updates only when already authorized; otherwise the authorization callback
    /// starts them once permission is granted.
    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    // MARK: - CLLocationManagerDelegate
    // Delegate callbacks hop onto the main actor before touching observable state.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized {
                self.manager.startUpdatingLocation()
            } else {
                self.manager.stopUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.currentLocation = coord
            self.onLocationUpdate?(coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last good fix; surface to UI here if you want explicit error feedback.
        print("LocationManager error: \(error.localizedDescription)")
    }
}
