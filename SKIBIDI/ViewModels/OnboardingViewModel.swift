import SwiftUI
import AuthenticationServices

/// Drives the 6-screen onboarding flow as a single state machine, in the app's `@Observable`
/// ViewModel style. There's no router/coordinator in the app yet, so this object *is* the
/// coordinator: views read `step` to decide what to show, and call the intent methods below to
/// advance. The `@AppStorage("hasOnboarded")` gate in `SKIBIDIApp` swaps the whole flow out for
/// the map once `finish()` runs (wired in Phase 4 once local save lands).
@MainActor
@Observable
final class OnboardingViewModel {
    /// The screens, in order. Splash screens 1–4 collapse into `.splash` + the `authState`
    /// below, because screens 3 (Face ID) and 4 (checkmark) are *auth states*, not separate
    /// navigation steps — they reflect the real Apple authorization, not timers.
    enum Step: Equatable {
        case splash       // screens 1 & 2: logo, then "Sign in with Apple" revealed
        case profile      // screen 5: name + emoji  (Phase 2)
        case permissions  // screen 6: location / health / notifications  (Phase 3)
    }

    /// Real Sign in with Apple progress. Screen 3 = `.authenticating`, screen 4 = `.succeeded`.
    enum AuthState: Equatable {
        case idle            // screen 2: button shown, waiting for a tap
        case authenticating  // screen 3: request issued, Apple sheet up — Face ID glyph
        case succeeded       // screen 4: credential received — checkmark glyph
        case failed(String)  // back to screen 2 with a recoverable message
    }

    var step: Step = .splash
    var authState: AuthState = .idle

    /// The signed-in identity, kept in memory through the flow. Becomes the device owner
    /// (`currentUser`) when onboarding commits — name/email may be `nil` after first sign-in.
    private(set) var credential: AuthCredential?

    // MARK: - Profile draft (screen 5)
    // Held in memory only through the flow; committed onto `User` at the end (Phase 4). These map
    // onto the existing model: `fullName` → `User.name`, `selectedEmoji` → `User.emoji`.

    /// The name shown on the map / profile. Pre-filled from Apple on first sign-in if granted.
    var fullName: String = ""
    /// The avatar emoji, stored as a plain `String` (matches `User.emoji`).
    var selectedEmoji: String = "😀"

    /// True once there's a non-empty name to proceed with (drives the "Next" button).
    var canProceedFromProfile: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Permission intents (screen 6)
    // We RECORD INTENT only — these booleans capture which permissions the user opted into.
    // The actual system prompts are deferred to point-of-use (see `PermissionServices`); nothing
    // here calls `request()`. Defaulted on to match the mockup (all toggles green).

    var locationIntent = true
    var healthIntent = true
    var notificationsIntent = true

    // MARK: - Services
    // Permission services are point-of-use only (not invoked during onboarding). The profile
    // store is local-first persistence; the sync service is the non-blocking CloudKit push.
    @ObservationIgnored private let authService: AuthServiceProtocol
    @ObservationIgnored let locationPermission: LocationPermissionServiceProtocol
    @ObservationIgnored let healthPermission: HealthPermissionServiceProtocol
    @ObservationIgnored let notificationPermission: NotificationPermissionServiceProtocol
    @ObservationIgnored private var profileStore: ProfileStoreProtocol
    @ObservationIgnored private let profileSync: ProfileSyncServiceProtocol

    /// Inject the backends. Defaults to the real services; previews/tests pass mocks.
    init(
        authService: AuthServiceProtocol = AppleAuthService(),
        locationPermission: LocationPermissionServiceProtocol = RealLocationPermissionService(),
        healthPermission: HealthPermissionServiceProtocol = RealHealthPermissionService(),
        notificationPermission: NotificationPermissionServiceProtocol = RealNotificationPermissionService(),
        profileStore: ProfileStoreProtocol = UserDefaultsProfileStore(),
        profileSync: ProfileSyncServiceProtocol = CloudKitProfileSyncService()
    ) {
        self.authService = authService
        self.locationPermission = locationPermission
        self.healthPermission = healthPermission
        self.notificationPermission = notificationPermission
        self.profileStore = profileStore
        self.profileSync = profileSync
        // Health may be unavailable (e.g. iPad) — don't record an intent we can never fulfill.
        if !healthPermission.isAvailable { healthIntent = false }
    }

    // MARK: - Sign in with Apple

    /// Called from `SignInWithAppleButton`'s `onRequest`: set scopes and flip to the
    /// in-progress (Face ID) state. This is a real state — the system sheet is now presenting.
    func configureSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        authState = .authenticating
        authService.configureRequest(request)
    }

    /// Called from `SignInWithAppleButton`'s `onCompletion`. On success we keep the credential
    /// and show the checkmark (screen 4); on cancel/failure we return to screen 2 with an error.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        do {
            let credential = try authService.makeCredential(from: result)
            self.credential = credential
            // Apple only returns the name on the *first* authorization — seed the field with it
            // when we have it and the user hasn't already typed something.
            if fullName.isEmpty, let name = credential.fullName, !name.isEmpty {
                fullName = name
            }
            authState = .succeeded
        } catch {
            let message = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            authState = .failed(message)
        }
    }

    /// Called once the success checkmark (screen 4) has been shown, to advance to profile setup.
    /// Driven by the view after the credential lands — not by an arbitrary timer.
    func advanceToProfile() {
        guard authState == .succeeded else { return }
        step = .profile
    }

    /// Screen 5 → 6 ("Next"). Trims the name and moves to permissions. No persistence yet —
    /// the draft stays in memory and is committed onto `User` at the end of onboarding (Phase 4).
    func advanceToPermissions() {
        guard canProceedFromProfile else { return }
        fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        step = .permissions
    }

    /// Screen 6 → "Done!". Local-first completion:
    /// 1. Save the profile + recorded intents **locally** (synchronous, offline — never blocks).
    /// 2. Kick off a **non-blocking** background CloudKit sync (best-effort; retried next launch).
    /// Returns `true` once the local save succeeds — the caller flips `hasOnboarded` only then, so
    /// onboarding finishes regardless of network/iCloud state. No system permission prompts fire.
    @discardableResult
    func completeOnboarding() -> Bool {
        let profile = StoredProfile(
            appleUserID: credential?.appleUserID,
            fullName: fullName,
            selectedEmoji: selectedEmoji,
            locationIntent: locationIntent,
            healthIntent: healthIntent,
            notificationsIntent: notificationsIntent
        )

        do {
            try profileStore.save(profile)
        } catch {
            // Local save is effectively infallible; if it ever fails we do NOT complete onboarding.
            print("❌ [Onboarding] local save failed:", error)
            return false
        }

        // Local save succeeded — onboarding is officially complete. Sync to CloudKit in the
        // background; mark the profile as needing sync so a failure here is retried on next launch.
        profileStore.needsCloudSync = true
        let sync = profileSync
        var store = profileStore
        Task {
            do {
                try await sync.sync(profile)
                store.needsCloudSync = false
            } catch {
                print("☁️ [Onboarding] CloudKit sync deferred (will retry):", error.localizedDescription)
            }
        }
        return true
    }

    /// The recoverable error text to show on screen 2 after a failed/canceled sign-in, if any.
    var signInErrorMessage: String? {
        if case .failed(let message) = authState { return message }
        return nil
    }
}
