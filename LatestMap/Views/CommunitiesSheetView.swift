import SwiftUI

/// Bottom sheet for the Communities tab: lists the user's communities (tap one to focus the map
/// on its members) and, under the focused community, its members as drill-downs to detail.
struct CommunitiesSheetView: View {
    /// `@ObservedObject` — owned by `CommunitiesMapView`; selecting a community here drives the map.
    @ObservedObject var viewModel: CommunitiesViewModel
    /// Threaded through to each `MemberDetailViewModel`. // REVIEW: View constructing VMs and
    /// holding a service — a VM factory would keep this out of the View layer.
    let healthService: HealthService

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.communities) { community in
                    Section {
                        // Tappable header — selecting focuses the map on this community's members.
                        Button {
                            viewModel.select(community)
                        } label: {
                            CommunityRow(
                                community: community,
                                isSelected: community.id == viewModel.selectedCommunityID
                            )
                        }
                        .buttonStyle(.plain)

                        // Only the focused community expands to its members (each opens detail).
                        if community.id == viewModel.selectedCommunityID {
                            ForEach(community.members) { member in
                                NavigationLink {
                                    MemberDetailView(
                                        viewModel: MemberDetailViewModel(
                                            member: member,
                                            healthService: healthService
                                        )
                                    )
                                } label: {
                                    MemberRowView(member: member)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.communities.isEmpty {
                    Text("No communities yet").foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Selectable community summary row: name, subtitle, member count, and a focus checkmark.
private struct CommunityRow: View {
    let community: Community
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(community.name).font(.headline)
                Text(community.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(community.members.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle()) // make the whole row tappable, not just the text
    }
}
