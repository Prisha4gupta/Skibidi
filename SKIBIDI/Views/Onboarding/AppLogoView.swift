import SwiftUI

/// The centered "tim" waveform logo ("AppLogo" in `Assets.xcassets`) used across the
/// splash/onboarding screens.
struct AppLogoView: View {
    var width: CGFloat = 180

    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .accessibilityLabel("SKIBIDI")
    }
}

#Preview {
    ZStack {
        Color.skibidiBlueGradient.ignoresSafeArea()
        AppLogoView()
    }
}
