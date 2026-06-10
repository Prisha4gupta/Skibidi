import SwiftUI

/// Screen 6 — "Let's set up your access". Three permission rows (Location, Health, Notifications),
/// each icon + label + toggle, plus a "Done!" pill that completes onboarding.
///
/// Tapping "Done!" fires the real system prompts for whichever toggles are on (the single place we
/// ask — see `OnboardingViewModel.requestEnabledPermissions`), then commits the profile. The map
/// later uses these grants gated on the saved intents and never re-prompts. `onDone` leaves
/// onboarding once the local save succeeds.
struct PermissionsView: View {
    @Bindable var viewModel: OnboardingViewModel
    /// Called when the user taps "Done!". The app uses this to leave onboarding.
    var onDone: () -> Void = {}

    var body: some View {
        ZStack {
            Color.skibidiBlueGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                AppLogoView(width: 110)
                    .padding(.top, 24)

                Text("Let's set up your access")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 24)
                    .padding(.horizontal, 28)

                VStack(spacing: 12) {
                    PermissionRow(
                        icon: "location.fill",
                        iconColor: .skibidiBlue,
                        title: "Allow Location",
                        isOn: $viewModel.locationIntent
                    )
                    PermissionRow(
                        icon: "heart.fill",
                        iconColor: .metricHeart,
                        title: "Connect Health",
                        isOn: $viewModel.healthIntent,
                        isEnabled: viewModel.healthPermission.isAvailable
                    )
                    PermissionRow(
                        icon: "bell.fill",
                        iconColor: .energyLow,
                        title: "Enable Notifications",
                        isOn: $viewModel.notificationsIntent
                    )
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)

                Spacer()

                Button {
                    // Ask the system for the enabled permissions HERE (the one place we prompt),
                    // then flip out of onboarding once the local save succeeds (local-first).
                    Task {
                        await viewModel.requestEnabledPermissions()
                        if viewModel.completeOnboarding() { onDone() }
                    }
                } label: {
                    Text("Done!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.black, in: Capsule())
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
    }
}

/// A single permission row: a colored icon chip, a label, and an intent toggle, on a translucent
/// rounded card — matching the mockup's three access rows.
private struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.activeGreen)
                .disabled(!isEnabled)
                // The visible label is the row's `Text(title)`, but `labelsHidden()` leaves the
                // toggle itself nameless to Voice Control / VoiceOver — name it after the row.
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Wrapper so previews can configure the VM (e.g. health unavailable) before rendering.
private struct PermissionsPreview: View {
    @State private var viewModel: OnboardingViewModel

    init(healthAvailable: Bool = true) {
        _viewModel = State(initialValue: OnboardingViewModel(
            authService: MockAuthService(),
            locationPermission: MockLocationPermissionService(),
            healthPermission: MockHealthPermissionService(isAvailable: healthAvailable),
            notificationPermission: MockNotificationPermissionService()
        ))
    }

    var body: some View { PermissionsView(viewModel: viewModel) }
}

#Preview("All available") {
    PermissionsPreview()
}

#Preview("Health unavailable") {
    PermissionsPreview(healthAvailable: false)
}
