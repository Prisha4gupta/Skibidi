import SwiftUI

/// Detail screen for one member: condition, energy score, and latest health metrics.
struct MemberDetailView: View {
    // `@StateObject` — this View owns the detail VM. // REVIEW: the VM is constructed by the
    // parent (CommunitiesSheetView) and injected; with @StateObject a list re-render that rebuilds
    // the VM is ignored, so it's effectively pinned to the first member. Acceptable per-NavigationLink
    // instance, but note the ownership/creation split.
    @StateObject private var viewModel: MemberDetailViewModel

    init(viewModel: MemberDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: viewModel.member.avatar)
                        .resizable().scaledToFit().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text(viewModel.member.name).font(.title2.bold())
                        Text(viewModel.member.conditionStatus.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Energy") {
                if let score = viewModel.energyScore {
                    LabeledContent("Score", value: "\(score.value)")
                    LabeledContent("Condition", value: score.condition.displayName)
                } else {
                    Text("No data yet").foregroundStyle(.secondary)
                }
            }

            Section("Latest Metrics") {
                if let m = viewModel.latestMetric {
                    LabeledContent("Steps", value: "\(m.steps)")
                    LabeledContent("Sleep", value: String(format: "%.1f h", m.sleepHours))
                    LabeledContent("Heart rate", value: "\(m.heartRate) bpm")
                } else {
                    Text("Pull to refresh").foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .navigationTitle(viewModel.member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
