import Foundation
import CoreLocation
import Combine

protocol LocationService: AnyObject {
    var currentLocationPublisher: AnyPublisher<CLLocationCoordinate2D?, Never> { get }
    func requestAuthorization()
    func startUpdating()
    func stopUpdating()
}

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
        manager.distanceFilter = 25
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if isAuthorized {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            subject.send(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        subject.send(coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationService error: \(error.localizedDescription)")
    }
}
