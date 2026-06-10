import SwiftUI

struct PeopleListView: View {
    let community: Community
    @Bindable var viewModel: CommunityViewModel
    @State private var shareData: ShareSheetData?

    var body: some View {
        VStack(spacing: 0) {
            

            HStack {
                Text(viewModel.selectedCommunity?.name ?? "Teams")
                    .font(.title2.bold())

                Spacer()

                Button {
                    Task { shareData = await viewModel.prepareGroupShare(for: community) }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Invite people")

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.goBackToCommunities()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 20)
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(community.members) { member in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectMember(member)
                            }
                        } label: {
                            MemberRowView(user: member)
                        }
                        .buttonStyle(.plain)
                        
                        if member.id != community.members.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .background(Color.cardBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -5)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .sheet(item: $shareData) { data in
            CloudSharingView(share: data.share, container: data.container)
                .ignoresSafeArea()
        }
    }
}


struct CommunityDashboardView: View {
    let community: Community
    @Bindable var viewModel: CommunityViewModel
    @State private var shareData: ShareSheetData?

    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Menu {
                    ForEach(viewModel.communities) { option in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedCommunity = option
                            }
                        } label: {
                            if option.id == community.id {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(community.name)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(.systemGray3), Color(.systemGray6))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { shareData = await viewModel.prepareGroupShare(for: community) }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Invite people")

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.goBackToCommunities()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(viewModel.membersForDashboard(in: community)) { member in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectMember(member)
                            }
                        } label: {
                            WellnessRingCard(user: member)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .background(Color.cardBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -5)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.65)
        .sheet(item: $shareData) { data in
            CloudSharingView(share: data.share, container: data.container)
                .ignoresSafeArea()
        }
    }
}

/// Empty sample team for previews (real data only exists in CloudKit at runtime).
private func previewCommunity() -> Community {
    Community(
        id: UUID(),
        name: "Preview Team",
        type: .detail,
        imageData: nil,
        members: [],
        dateActive: Date(),
        memberCount: 0,
        isLocationSharing: true,
        isHealthSharing: true,
        isFitnessSharing: true,
        hasNotification: false,
        notificationMessage: nil
    )
}

#Preview("People List") {
    ZStack {
        Color(.systemGray4).ignoresSafeArea()
        VStack {
            Spacer()
            PeopleListView(
                community: previewCommunity(),
                viewModel: CommunityViewModel()
            )
        }
    }
}

#Preview("Dashboard") {
    ZStack {
        Color(.systemGray4).ignoresSafeArea()
        VStack {
            Spacer()
            CommunityDashboardView(
                community: previewCommunity(),
                viewModel: CommunityViewModel()
            )
        }
    }
}
