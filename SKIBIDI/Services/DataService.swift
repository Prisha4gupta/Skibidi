import Foundation
import CoreLocation

/// The data-source contract every ViewModel depends on.
///
/// Think of this like a Clojure `defprotocol`: it declares *what* data the app needs,
/// not *where* it comes from. Today `MockDataService` satisfies it; later
/// `CloudKitService` will satisfy the exact same contract. Because ViewModels only
/// ever talk to this protocol (never to a concrete class), swapping the mock backend
/// for the real CloudKit one requires zero changes to any ViewModel or View.
///
/// `@MainActor` guarantees conformers are reached on the main thread — the app's
/// UI state (and the eventual CloudKit sync) all live there.
@MainActor
protocol DataService {
    /// The device owner. Their health + location get folded in live by the ViewModel.
    var currentUser: User { get }

    /// Every community the current user belongs to.
    var communities: [Community] { get }

    /// In-app notifications feed.
    var notifications: [AppNotification] { get }

    /// Where the map should center on first launch.
    var mapCenter: CLLocationCoordinate2D { get }
}
