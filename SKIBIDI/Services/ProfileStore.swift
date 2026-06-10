import Foundation

/// The onboarding result, persisted locally. A small Codable DTO that maps onto the `User` model
/// (`fullName → User.name`, `selectedEmoji → User.emoji`, `appleUserID → User.appleUserID`) plus
/// the recorded permission intents. Kept separate from `User` because `User` carries map/health
/// state that doesn't exist yet at onboarding time; `CommunityViewModel` folds these fields onto
/// `currentUser` at launch.
struct StoredProfile: Codable, Equatable {
    var appleUserID: String?
    var fullName: String
    var selectedEmoji: String
    var locationIntent: Bool
    var healthIntent: Bool
    var notificationsIntent: Bool
}

/// Local-first persistence for the onboarding profile. Synchronous and offline — it must never
/// block on the network or iCloud sign-in state, so onboarding can finish regardless. CloudKit
/// sync is a separate, best-effort step (`ProfileSyncServiceProtocol`).
///
/// Follows the project DI shape: a protocol with a real (`UserDefaults`) conformer and a `Mock`.
@MainActor
protocol ProfileStoreProtocol {
    /// Persist the profile locally. Throws only on an encoding failure (effectively never).
    func save(_ profile: StoredProfile) throws
    /// The last saved profile, or `nil` if onboarding hasn't completed.
    func load() -> StoredProfile?
    /// Whether the saved profile still needs to be pushed to CloudKit.
    var needsCloudSync: Bool { get set }
}

/// Real local store backed by `UserDefaults` (matching the existing `userDisplayName` precedent).
/// Stores the profile as JSON and mirrors the name into the legacy `userDisplayName` key so the
/// existing rename path stays coherent.
@MainActor
final class UserDefaultsProfileStore: ProfileStoreProtocol {
    private let defaults: UserDefaults
    private let profileKey = "onboardingProfile"
    private let needsSyncKey = "onboardingProfileNeedsCloudSync"
    private let legacyDisplayNameKey = "userDisplayName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ profile: StoredProfile) throws {
        let data = try JSONEncoder().encode(profile)
        defaults.set(data, forKey: profileKey)
        // Keep the legacy display-name key in sync so `CommunityViewModel`/`updateDisplayName`
        // continue to work without onboarding-awareness.
        defaults.set(profile.fullName, forKey: legacyDisplayNameKey)
    }

    func load() -> StoredProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(StoredProfile.self, from: data)
    }

    var needsCloudSync: Bool {
        get { defaults.bool(forKey: needsSyncKey) }
        set { defaults.set(newValue, forKey: needsSyncKey) }
    }
}

/// In-memory store for previews/tests.
@MainActor
final class MockProfileStore: ProfileStoreProtocol {
    private(set) var saved: StoredProfile?
    var saveError: Error?
    var needsCloudSync: Bool = false

    init(initial: StoredProfile? = nil) { self.saved = initial }

    func save(_ profile: StoredProfile) throws {
        if let saveError { throw saveError }
        saved = profile
    }

    func load() -> StoredProfile? { saved }
}
