import SwiftUI
import MapKit

struct SettingsView: View {
    @Bindable var settingsVM: SettingsViewModel
    @Bindable var communityVM: CommunityViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Mini map preview
                Map {
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .allowsHitTesting(false)
                
                VStack(spacing: 24) {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Account")
                                .font(.headline)
                                .padding(.bottom, 16)
                            
                            
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                Text("Permissions")
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.bottom, 12)
                            
                            Text("The app will read data from the following apps on your iPhone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)
                            
                            
                            settingsToggle(
                                title: "Fitness",
                                isOn: $settingsVM.isFitnessEnabled
                            )
                            
                            Divider().padding(.vertical, 8)
                            
                           
                            settingsToggle(
                                title: "Health",
                                isOn: $settingsVM.isHealthEnabled
                            )
                            
                            Divider().padding(.vertical, 8)
                            
                            settingsToggle(
                                title: "Weather",
                                isOn: $settingsVM.isWeatherEnabled
                            )
                        }
                    }
                    
                    sectionCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .font(.body)
                                    .foregroundStyle(.blue)
                                Text("My Location")
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.bottom, 12)
                            
                            settingsToggle(
                                title: "Share My Location",
                                isOn: $settingsVM.isLocationSharingEnabled
                            )
                        }
                    }
                    

                    sectionCard {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("Communities")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                            }
                            .padding(.bottom, 12)
                            
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(.systemGray5))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "bell.fill")
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Notification")
                                        .font(.subheadline.weight(.medium))
                                    Text("You have a new notification")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Text("View")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiaryText)
                                }
                            }
                            .padding(.vertical, 6)
                            
                            Divider().padding(.vertical, 6)
                            
                            if communityVM.communities.isEmpty {
                                Text("No communities")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(communityVM.communities) { community in
                                    SwipeToDeleteCommunityRow(community: community) {
                                        communityVM.leaveCommunity(community)
                                    }

                                    if community.id != communityVM.communities.last?.id {
                                        Divider().padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }

                    sectionCard {
                        Button {
                            settingsVM.confirmLeaveAllCommunities()
                        } label: {
                            HStack {
                                Text("Leave All Communities")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                        .disabled(communityVM.communities.isEmpty)
                    }
                    
        
                }
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert("Leave All Communities", isPresented: $settingsVM.showingLeaveCommunity) {
            Button("Cancel", role: .cancel) {
                settingsVM.showingLeaveCommunity = false
            }
            Button("Leave", role: .destructive) {
                communityVM.leaveAllCommunities()
                settingsVM.showingLeaveCommunity = false
            }
        } message: {
            Text("Are you sure you want to leave all the communities? This action cannot be undone.")
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading) {
            content()
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }
    
    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.body)
        }
        .tint(.blue)
    }
}

struct SwipeToDeleteCommunityRow: View {
    let community: Community
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let deleteThreshold: CGFloat = 90

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Delete")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(dragOffset > 8 ? 1 : 0)

            communityContent
                .offset(x: max(dragOffset, 0))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = max(value.translation.width, 0)
                        }
                        .onEnded { value in
                            if value.translation.width > deleteThreshold {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dragOffset = 420
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                    onDelete()
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
        }
        .frame(height: 48)
        .clipped()
    }

    private var communityContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(community.name)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text("Active")
                .font(.caption.weight(.medium))
                .foregroundStyle(.activeGreen)
        }
        .padding(.vertical, 6)
        .background(Color.cardBackground)
    }
}

#Preview {
    SettingsView(settingsVM: SettingsViewModel(), communityVM: CommunityViewModel())
}
