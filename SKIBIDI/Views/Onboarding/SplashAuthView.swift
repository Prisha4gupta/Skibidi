import SwiftUI
import AuthenticationServices

/// Splash screens 1–4 as one continuous screen: a full-bleed blue background with the centered
/// waveform logo throughout. What changes is the *top glyph* and *bottom control*, driven by the
/// real Sign in with Apple state — not timers:
///   • Screen 1 → 2: logo only, then the "Sign in with Apple" button fades in.
///   • Screen 3 (`.authenticating`): progress spinner at the bottom.
///   • Screen 4 (`.succeeded`): checkmark glyph on top and bottom, then advance to profile.
struct SplashAuthView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Drives the screen 1 → 2 reveal of the sign-in button (a brief launch splash, the only
    /// timed transition here; the auth screens 3 & 4 are state-driven).
    @State private var showSignInButton = false

    var body: some View {
        ZStack {
            Color.skibidiBlueGradient
                .ignoresSafeArea()

            // Top glyph reflects auth progress (screens 3 & 4); absent on screens 1 & 2.
            VStack {
                topGlyph
                    .padding(.top, 8)
                Spacer()
            }

            // The logo stays centered across all four screens.
            AppLogoView()

            // Bottom control: sign-in button (1/2), spinner (3), or checkmark (4).
            VStack {
                Spacer()
                bottomControl
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            // Screen 1 → 2: reveal the button shortly after launch.
            guard !showSignInButton, viewModel.authState == .idle else { return }
            withAnimation(.easeOut(duration: 0.5).delay(1.0)) {
                showSignInButton = true
            }
        }
        .onChange(of: viewModel.authState) { _, newState in
            // Screen 4: once Apple returns the credential, hold the checkmark briefly so it
            // registers, then advance to profile. This delay is cosmetic confirmation of a real
            // completed state — not a stand-in for the auth itself.
            if newState == .succeeded {
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    viewModel.advanceToProfile()
                }
            }
        }
    }

    // MARK: - Top glyph (screens 3 & 4)

    @ViewBuilder
    private var topGlyph: some View {
        switch viewModel.authState {
        case .succeeded:
            glyphBadge(systemName: "checkmark")
        case .idle, .failed, .authenticating:
            // No glyph while idle or authenticating (the system sheet is confirmation enough);
            // reserve the space so the logo doesn't shift when the checkmark appears.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// The rounded black badge that frames the checkmark glyph at the top.
    private func glyphBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Bottom control

    @ViewBuilder
    private var bottomControl: some View {
        switch viewModel.authState {
        case .idle, .failed, .authenticating:
            // The button stays mounted across `.idle`/`.failed`/`.authenticating`. We must NOT
            // remove `SignInWithAppleButton` from the hierarchy while authorization is in flight:
            // it owns the `ASAuthorizationController`, and tearing the button down cancels the
            // request so `onCompletion` never fires — which left the spinner stuck forever.
            // Instead, during `.authenticating` we hide the button and overlay the spinner on top.
            VStack(spacing: 12) {
                if let error = viewModel.signInErrorMessage {
                    Text(error)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                if showSignInButton {
                    ZStack {
                        SignInWithAppleButton(.signIn) { request in
                            viewModel.configureSignInRequest(request)
                        } onCompletion: { result in
                            viewModel.handleSignInResult(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .clipShape(Capsule())
                        // Screen 3: hide the button but keep it alive so its completion still fires.
                        .opacity(viewModel.authState == .authenticating ? 0 : 1)
                        .allowsHitTesting(viewModel.authState != .authenticating)

                        if viewModel.authState == .authenticating {
                            // Small progress indicator while the system sheet is up.
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(height: 50)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

        case .succeeded:
            // Screen 4: confirmation checkmark at the bottom.
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(height: 50)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Preview helper: builds a `SplashAuthView` pinned to a given auth state, so each screen
/// (3 and 4) can be previewed without driving the real Apple flow.
private struct SplashAuthPreview: View {
    @State private var viewModel: OnboardingViewModel

    init(state: OnboardingViewModel.AuthState) {
        let model = OnboardingViewModel(authService: MockAuthService())
        model.authState = state
        _viewModel = State(initialValue: model)
    }

    var body: some View { SplashAuthView(viewModel: viewModel) }
}

#Preview("Splash → Sign in") {
    SplashAuthView(viewModel: OnboardingViewModel(authService: MockAuthService()))
}

#Preview("Authenticating (Face ID)") {
    SplashAuthPreview(state: .authenticating)
}

#Preview("Auth success") {
    SplashAuthPreview(state: .succeeded)
}
