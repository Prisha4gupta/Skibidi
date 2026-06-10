import SwiftUI

/// Screen 5 — "Express your vibe". Profile setup on the blue gradient: a tappable circular
/// emoji avatar, a full-name field, and a "Next" pill that advances to permissions.
///
/// All state lives in `OnboardingViewModel` (the draft) — nothing is persisted here; the name +
/// emoji are committed onto `User` at the end of onboarding (Phase 4).
struct ProfileSetupView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var showingEmojiPicker = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Color.skibidiBlueGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                AppLogoView(width: 110)
                    .padding(.top, 24)

                Text("Express your vibe")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 16)

                avatarButton
                    .padding(.top, 32)

                nameField
                    .padding(.top, 36)
                    .padding(.horizontal, 28)

                Spacer()

                nextButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(selectedEmoji: $viewModel.selectedEmoji)
        }
        // Dismiss the keyboard when tapping the background.
        .contentShape(Rectangle())
        .onTapGesture { nameFocused = false }
    }

    // MARK: - Avatar

    private var avatarButton: some View {
        Button {
            nameFocused = false
            showingEmojiPicker = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                EmojiAvatarView(
                    emoji: viewModel.selectedEmoji,
                    size: 120,
                    backgroundColor: .white
                )
                // Small edit affordance so it reads as tappable.
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.skibidiBlue)
                    .frame(width: 32, height: 32)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.skibidiBlue.opacity(0.15), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose avatar emoji")
    }

    // MARK: - Name field

    private var nameField: some View {
        HStack {
            Text("Full Name")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            TextField(
                "",
                text: $viewModel.fullName,
                prompt: Text("Your Name").foregroundStyle(.white.opacity(0.7))
            )
            .focused($nameFocused)
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.white)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { nameFocused = false }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Next

    private var nextButton: some View {
        Button {
            viewModel.advanceToPermissions()
        } label: {
            Text("Next")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.black, in: Capsule())
        }
        .opacity(viewModel.canProceedFromProfile ? 1 : 0.5)
        .disabled(!viewModel.canProceedFromProfile)
    }
}

/// Wrapper so previews can configure the draft before rendering.
private struct ProfileSetupPreview: View {
    @State private var viewModel: OnboardingViewModel

    init(name: String = "", emoji: String = "😀") {
        let model = OnboardingViewModel(authService: MockAuthService())
        model.fullName = name
        model.selectedEmoji = emoji
        _viewModel = State(initialValue: model)
    }

    var body: some View { ProfileSetupView(viewModel: viewModel) }
}

#Preview("Empty") {
    ProfileSetupPreview()
}

#Preview("Prefilled") {
    ProfileSetupPreview(name: "Sammy", emoji: "🦄")
}
