import SwiftUI

/// Container that swaps between onboarding screens based on `OnboardingViewModel.step`.
/// Owns the single `OnboardingViewModel` for the flow and injects the auth backend.
///
/// `SKIBIDIApp` shows this whenever `hasOnboarded` is false; it animates between steps so the
/// splash → profile → permissions progression feels like one flow rather than hard cuts.
struct OnboardingFlowView: View {
    @State private var viewModel: OnboardingViewModel
    /// Called when onboarding finishes ("Done!"). The app flips `hasOnboarded` here.
    private let onComplete: () -> Void

    /// Inject the auth service so previews/tests can pass a mock; defaults to real Apple sign-in.
    init(authService: AuthServiceProtocol = AppleAuthService(), onComplete: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: OnboardingViewModel(authService: authService))
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            switch viewModel.step {
            case .splash:
                SplashAuthView(viewModel: viewModel)
            case .profile:
                // Screen 5 — "Express your vibe".
                ProfileSetupView(viewModel: viewModel)
            case .permissions:
                // Screen 6 — "Let's set up your access".
                PermissionsView(viewModel: viewModel, onDone: onComplete)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.step)
    }
}

#Preview {
    OnboardingFlowView(authService: MockAuthService())
}
