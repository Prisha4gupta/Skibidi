import SwiftUI

@main
struct SKIBIDIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var communityVM = CommunityViewModel()

    /// Onboarding gate. There's no router in the app, so the root simply swaps between the
    /// onboarding flow and the map based on this flag. Flipped to `true` only after onboarding's
    /// local save succeeds (Phase 4); until then every launch starts at the splash.
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some Scene {
        WindowGroup {
            if hasOnboarded {
                PeopleMapView(viewModel: communityVM)
                    // Local-first retry: if a prior CloudKit profile sync didn't land, try again
                    // in the background on launch. Non-blocking — the app works either way.
                    .task { await retryPendingProfileSync() }
            } else {
                // `completeOnboarding()` saves the profile locally first; this flag flip (passed as
                // onComplete) runs only after that local save succeeds. `communityVM` was built at
                // launch (before the profile existed), so refresh the owner from the just-saved
                // profile before showing the map — otherwise it shows the mock default until relaunch.
                OnboardingFlowView(onComplete: {
                    communityVM.reloadProfileFromLocalStore()
                    hasOnboarded = true
                })
            }
        }
    }

    /// Push the locally-saved profile to CloudKit if a previous attempt was deferred. Best-effort.
    @MainActor
    private func retryPendingProfileSync() async {
        var store = UserDefaultsProfileStore()
        guard store.needsCloudSync, let profile = store.load() else { return }
        do {
            try await CloudKitProfileSyncService().sync(profile)
            store.needsCloudSync = false
            print("☁️ [Launch] pending profile synced")
        } catch {
            print("☁️ [Launch] profile sync still pending:", error.localizedDescription)
        }
    }
}

