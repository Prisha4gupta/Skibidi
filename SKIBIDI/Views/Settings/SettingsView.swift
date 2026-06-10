import SwiftUI

struct SettingsView: View {
    @Bindable var communityVM: CommunityViewModel

    /// Swiping past the threshold only *requests* removal; nothing happens until the user
    /// confirms in the alert this drives.
    @State private var communityToRemove: Community?
    /// Transient top banner ("You left …") shown once a removal finishes.
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                            
                            Text("Choose what the app reads and shares with your teams.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 12)


                            settingsToggle(
                                title: "Fitness",
                                isOn: Binding(
                                    get: { communityVM.currentUser.fitnessSharing.hasData },
                                    set: { communityVM.setFitnessSharing($0) }
                                )
                            )

                            Divider().padding(.vertical, 8)


                            settingsToggle(
                                title: "Health",
                                isOn: Binding(
                                    get: { communityVM.currentUser.healthSharing.hasData },
                                    set: { communityVM.setHealthSharing($0) }
                                )
                            )

                            Divider().padding(.vertical, 8)

                            settingsToggle(
                                title: "Share My Location",
                                isOn: Binding(
                                    get: { communityVM.currentUser.locationSharing.hasData },
                                    set: { communityVM.setLocationSharing($0) }
                                )
                            )
                        }
                    }

                    sectionCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Teams")
                                .font(.headline)
                                .padding(.bottom, 12)

                            if communityVM.communities.isEmpty {
                                Text("No teams")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(communityVM.communities) { community in
                                    SwipeToDeleteCommunityRow(
                                        community: community,
                                        // Owner deletes the group for everyone; a participant
                                        // just leaves — make the swipe action say which.
                                        actionLabel: communityVM.ownsCommunity(community) == false ? "Leave" : "Delete"
                                    ) {
                                        communityToRemove = community
                                    }

                                    if community.id != communityVM.communities.last?.id {
                                        Divider().padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }

                }
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
        }
        .background(Color(.systemGroupedBackground))
        .alert(
            communityToRemove.map(removalTitle) ?? "",
            isPresented: Binding(
                get: { communityToRemove != nil },
                set: { if !$0 { communityToRemove = nil } }
            ),
            presenting: communityToRemove
        ) { community in
            Button("Cancel", role: .cancel) {}
            Button(actionLabel(for: community), role: .destructive) {
                Task { await remove(community) }
            }
        } message: { community in
            Text(ownsTeam(community)
                 ? "This will delete \"\(community.name)\" for everyone in it. This action cannot be undone."
                 : "You'll leave \"\(community.name)\". You can rejoin later with an invite link.")
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func ownsTeam(_ community: Community) -> Bool {
        communityVM.ownsCommunity(community) ?? true
    }

    private func actionLabel(for community: Community) -> String {
        ownsTeam(community) ? "Delete" : "Leave"
    }

    private func removalTitle(_ community: Community) -> String {
        ownsTeam(community) ? "Delete Team" : "Leave Team"
    }

    /// Run the confirmed removal and report the outcome via a short top banner.
    private func remove(_ community: Community) async {
        let owned = ownsTeam(community)
        let success = await communityVM.leaveCommunity(community)
        let text: String
        if success {
            text = owned ? "\"\(community.name)\" deleted" : "You left \"\(community.name)\""
        } else {
            text = "Couldn't \(owned ? "delete" : "leave") \"\(community.name)\" — try again"
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toastMessage = text }
        try? await Task.sleep(for: .seconds(2.2))
        if toastMessage == text {
            withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
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
    /// "Delete" for communities I own (removal dissolves them for everyone), "Leave" for ones
    /// I joined.
    var actionLabel: String = "Delete"
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    private let deleteThreshold: CGFloat = 90

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 10) {
                Image(systemName: actionLabel == "Leave" ? "rectangle.portrait.and.arrow.right" : "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(actionLabel)
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
                            // The row always springs back: passing the threshold only asks the
                            // caller for confirmation — the row actually disappears via the data
                            // change once the user confirms and the removal succeeds.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                dragOffset = 0
                            }
                            if value.translation.width > deleteThreshold {
                                onDelete()
                            }
                        }
                )
        }
        .frame(height: 48)
        .clipped()
    }

    private var communityContent: some View {
        HStack(spacing: 12) {
            CommunityAvatarView(imageData: community.imageData, size: 36)

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
    SettingsView(communityVM: CommunityViewModel())
}
