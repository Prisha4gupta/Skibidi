import SwiftUI

struct CommunitiesSheetView: View {
    @Bindable var viewModel: CommunityViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            

            HStack(spacing: 12) {
                Text("Teams")
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.showingCommunitySheet = false
                        viewModel.showingNotifications = true
                    }
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if viewModel.notifications.contains(where: { !$0.isRead }) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                }
                .accessibilityLabel("Notifications")

                Button {
                    viewModel.showingCreateCommunity = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("New team")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 20)
            

            ScrollView {
                VStack(spacing: 4) {

                    ForEach(viewModel.communities) { community in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectCommunity(community)
                            }
                        } label: {
                            CommunityRowView(community: community)
                        }
                        .buttonStyle(.plain)
                        
                        if community.id != viewModel.communities.last?.id {
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
        .frame(maxHeight: UIScreen.main.bounds.height * 0.42)
    }
}
struct NotificationSheetView: View {
    @Bindable var viewModel: CommunityViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("Notifications")
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.showingNotifications = false
                        viewModel.showingCommunitySheet = true
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
                    ForEach(viewModel.notifications) { notification in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 42, height: 42)
                                
                                Text(notification.communityEmoji)
                                    .font(.title3)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notification.communityName)
                                    .font(.body.weight(.medium))
                                
                                Text(notification.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if !notification.isRead {
                                Circle()
                                    .fill(Color.tabBarSelected)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
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
        .frame(maxHeight: UIScreen.main.bounds.height * 0.50)
        // Closing the sheet clears the bell dot and row badges — the dots stay visible while
        // the user is actually reading the list.
        .onDisappear { viewModel.markNotificationsRead() }
    }
}

#Preview {
    ZStack {
        Color(.systemGray4).ignoresSafeArea()
        VStack {
            Spacer()
            CommunitiesSheetView(viewModel: CommunityViewModel())
        }
    }
}
