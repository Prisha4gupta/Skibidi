import SwiftUI

/// Settings tab: permission actions and preference toggles.
struct SettingsView: View {
    /// `@StateObject` — this View owns the settings VM for its lifetime.
    @StateObject private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    Button("Connect HealthKit") {
                        Task { await viewModel.requestHealthKitAccess() }
                    }
                    LabeledContent(
                        "HealthKit",
                        value: viewModel.healthKitAuthorized ? "Authorized" : "Not connected"
                    )
                    Button("Allow Location") {
                        viewModel.requestLocationAccess()
                    }
                }

                Section("Preferences") {
                    Toggle("Notifications", isOn: $viewModel.notificationsEnabled)
                    Toggle("Share my location", isOn: $viewModel.shareLocation)
                }

                Section("About") {
                    LabeledContent("App", value: "Skibidi")
                    LabeledContent("Version", value: "0.1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
