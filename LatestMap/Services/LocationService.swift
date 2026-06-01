import Foundation
import CoreLocation
import Combine

/// Boundary for device location. Exposes coordinates as a Combine stream so ViewModels can
/// bind without touching CoreLocation. Class-bound (`AnyObject`) because the real impl is a
/// reference-type `CLLocationManagerDelegate`.
protocol LocationService: AnyObject {
    /// Stream of the latest coordinate; emits `nil` when unavailable/unauthorized. Never fails.
    var currentLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> { get }
    /// Prompts for when-in-use authorization (no-op if already decided). Side effect: system dialog.
    func requestAuthorization()
    /// Begins location updates (gated on authorization in the real impl).
    func startUpdating()
    /// Stops location updates.
    func stopUpdating()
}

/// Stub `LocationService` that emits a fixed Jakarta coordinate; authorization/update calls are no-ops.
final class MockLocationService: LocationService {
    private let subject = CurrentValueSubject<CLLocationCoordinate2D?, Never>(
        CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456) // Jakarta default
    )

    var currentLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> {
        subject.eraseToAnyPublisher()
    }

    func requestAuthorization() {}
    func startUpdating() {}
    func stopUpdating() {}
}

// MARK: - Real implementation
/// Production `LocationService` wrapping `CLLocationManager`. Delegate callbacks arrive on the
/// main thread and are republished through `subject`; subscribers (CommunitiesViewModel) still
/// hop to main explicitly. `CurrentValueSubject` replays the latest fix to new subscribers.
final class RealLocationService: NSObject, LocationService, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let subject = CurrentValueSubject<CLLocationCoordinate2D?, Never>(nil)

    var currentLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> {
        subject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25 // metres before a new update fires
    }

    func requestAuthorization() {
        // For "always" use `requestAlwaysAuthorization()` instead — requires the
        // NSLocationAlwaysAndWhenInUseUsageDescription key too.
        manager.requestWhenInUseAuthorization()
    }

    /// Starts updates only if already authorized; otherwise authorization callback starts them later.
    func startUpdating() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    // MARK: CLLocationManagerDelegate

    /// Reacts to authorization changes: start streaming when granted, else stop and emit `nil`.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isAuthorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            subject.send(nil)
        }
    }

    /// Publishes the newest fix (last element is most recent).
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        subject.send(coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Surface this if you want UI feedback; for now we keep the last good fix.
        print("LocationService error: \(error.localizedDescription)")
    }
}
