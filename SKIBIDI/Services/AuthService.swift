import AuthenticationServices
import Foundation

/// The credential we keep from a successful Sign in with Apple.
///
/// `appleUserID` is Apple's stable per-account identifier (always present). `fullName` and
/// `email` are only handed back by Apple on the **first** authorization for this Apple ID +
/// app — on every later sign-in they come back `nil`, so a real app caches them on first grant.
struct AuthCredential: Equatable {
    let appleUserID: String
    let fullName: String?
    let email: String?
}

/// Why a sign-in didn't complete, so screen 2 can show a recoverable message.
enum AuthError: LocalizedError {
    case canceled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .canceled: return "Sign in was canceled. Tap to try again."
        case .failed(let message): return message
        }
    }
}

/// Sign-in contract the onboarding flow depends on. Mirrors the `DataService` DI shape:
/// a `@MainActor protocol` with a real conformer (`AppleAuthService`) for devices and a
/// `MockAuthService` for previews/simulator — the ViewModel only ever talks to this protocol.
///
/// We split the Apple flow into two seams so it composes with SwiftUI's `SignInWithAppleButton`:
/// `configureRequest` sets the scopes when the button is tapped, and `makeCredential` turns the
/// button's completion result into our `AuthCredential` (or throws an `AuthError`).
@MainActor
protocol AuthServiceProtocol {
    /// Set the scopes we ask Apple for (name + email, only granted on first sign-in).
    func configureRequest(_ request: ASAuthorizationAppleIDRequest)
    /// Translate the `SignInWithAppleButton` completion into a credential, or throw `AuthError`.
    func makeCredential(from result: Result<ASAuthorization, Error>) throws -> AuthCredential
}

/// Real Apple sign-in. No network of our own — Apple's button presents the system sheet
/// (Face ID / passcode) and hands back an `ASAuthorizationAppleIDCredential` we unpack here.
@MainActor
final class AppleAuthService: AuthServiceProtocol {
    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func makeCredential(from result: Result<ASAuthorization, Error>) throws -> AuthCredential {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.failed("Unexpected credential type from Apple.")
            }
            // `fullName` is a PersonNameComponents; format to a display string when present.
            let name = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                return formatted.isEmpty ? nil : formatted
            }
            return AuthCredential(
                appleUserID: credential.user,
                fullName: name,
                email: credential.email
            )
        case .failure(let error):
            // The user dismissing the sheet surfaces as ASAuthorizationError.canceled.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                throw AuthError.canceled
            }
            throw AuthError.failed(error.localizedDescription)
        }
    }
}

/// Canned sign-in for previews, the Simulator, and tests — no entitlement or real Apple ID
/// needed. Ignores the button result and returns a fixed credential so the whole onboarding
/// flow is exercisable without a provisioned device. Configurable to simulate cancel/failure.
@MainActor
final class MockAuthService: AuthServiceProtocol {
    var stubbedCredential: AuthCredential
    var stubbedError: AuthError?

    init(
        credential: AuthCredential = AuthCredential(
            appleUserID: "mock-apple-user-id",
            fullName: "Sammy Skibidi",
            email: "sammy@example.com"
        ),
        error: AuthError? = nil
    ) {
        self.stubbedCredential = credential
        self.stubbedError = error
    }

    func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func makeCredential(from result: Result<ASAuthorization, Error>) throws -> AuthCredential {
        if let stubbedError { throw stubbedError }
        return stubbedCredential
    }
}
