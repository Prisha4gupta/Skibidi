import SwiftUI
import MapKit

struct PeopleMapView: View {
    @Bindable var viewModel: CommunityViewModel
    @State private var settingsVM = SettingsViewModel()
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            Map(position: $viewModel.mapCameraPosition) {

                ForEach(viewModel.visibleMapMembers) { member in
                    Annotation("", coordinate: member.coordinate) {
                        CommunityPinView(
                            user: member,
                            sosMessage: viewModel.sosMessage(for: member)
                        )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    viewModel.selectMember(member)
                                }
                            }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea()
            .onAppear { viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
 
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        emergencySOSButton {
                            viewModel.showingEmergencySOS = true
                        }

                        mapButton(icon: "gearshape.fill") {
                            showingSettings = true
                        }

                        mapButton(icon: "location.fill") {
                            withAnimation {
                                viewModel.recenterOnCurrentUser()
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                
                Spacer()
            }

            VStack {
                Spacer()
                
                if viewModel.showingYourProfile {
                    YourProfileView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingMemberProfile, let member = viewModel.selectedMember {
                    MemberProfileView(member: member, viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingDashboard, let community = viewModel.selectedCommunity {
                    CommunityDashboardView(community: community, viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingPeopleList, let community = viewModel.selectedCommunity {
                    PeopleListView(community: community, viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingNotifications {
                    NotificationSheetView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.showingCommunitySheet {
                    CommunitiesSheetView(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingCommunitySheet)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingPeopleList)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingDashboard)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingMemberProfile)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingYourProfile)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showingNotifications)
        }
        .sheet(isPresented: $viewModel.showingCreateCommunity) {
            CreateCommunityView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingEmergencySOS) {
            EmergencySOSView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(settingsVM: settingsVM, communityVM: viewModel)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
    }
    
    private func mapButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        }
    }

    private func emergencySOSButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.energyCritical)
                .clipShape(Circle())
                .shadow(color: Color.energyCritical.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel("Emergency SOS")
    }
}

struct CommunityPinView: View {
    let user: User
    let sosMessage: String?
    @State private var isAnimating = false

    /// Location frozen at last-known spot — render the pin dimmed and static.
    private var isLocationPaused: Bool { user.locationSharing.isStale }

    /// Ring reflects health: live/last-known energy color, or grey when health is never shared.
    private var pinColor: Color {
        user.displayedEnergyScore.map { Color.energyColor(for: $0) } ?? Color(.systemGray3)
    }

    private var ringColor: Color {
        sosMessage == nil ? pinColor : Color.energyCritical
    }

    var body: some View {
        VStack(spacing: 6) {
            if let sosMessage {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.bold))

                    Text(sosMessage)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 170, alignment: .leading)
                .background(Color.energyCritical)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.energyCritical.opacity(0.3), radius: 8, x: 0, y: 3)
            }

            EmojiAvatarView(
                emoji: user.emoji,
                size: 36,
                ringColor: ringColor,
                ringWidth: 2.5,
                backgroundColor: .white
            )
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .shadow(color: ringColor.opacity(0.3), radius: 6, x: 0, y: 3)
            // A paused member appears greyed-out and carries a small "frozen" badge.
            .opacity(isLocationPaused ? 0.55 : 1.0)
            .overlay(alignment: .topTrailing) {
                if isLocationPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, Color(.systemGray))
                        .background(Circle().fill(.white).padding(2))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .onAppear {
            // Only live locations pulse; paused pins stay still to read as "not updating".
            guard !isLocationPaused else { return }
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

struct EmergencySOSView: View {
    @Bindable var viewModel: CommunityViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCommunityID: UUID?
    @State private var message = ""

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedMessage.isEmpty
    }

    private var targetTitle: String {
        guard let selectedCommunityID,
              let community = viewModel.communities.first(where: { $0.id == selectedCommunityID }) else {
            return "All groups & people"
        }

        return community.name
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Emergency SOS")
                        .font(.title2.bold())
                    

                    Text("Send an urgent message to a group or everyone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Send to")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Menu {
                        Button {
                            selectedCommunityID = nil
                        } label: {
                            Label("All groups & people", systemImage: selectedCommunityID == nil ? "checkmark" : "person.3.fill")
                        }

                        ForEach(viewModel.communities) { community in
                            Button {
                                selectedCommunityID = community.id
                            } label: {
                                if selectedCommunityID == community.id {
                                    Label(community.name, systemImage: "checkmark")
                                } else {
                                    Text(community.name)
                                }
                            }
                            
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .foregroundStyle(Color.energyCritical)

                            Text(targetTitle)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Message")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $message)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .textInputAutocapitalization(.sentences)

                        if message.isEmpty {
                            Text("Example: I have been robbed, I am not feeling well, I need help.")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                }

                quickMessages

                Spacer(minLength: 0)

                Button {
                    viewModel.sendEmergencySOS(message: message, communityID: selectedCommunityID)
                    dismiss()
                } label: {
                    Label("Send SOS", systemImage: "paperplane.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSend ? Color.energyCritical : Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canSend)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var quickMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick messages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickMessageButton("I have been robbed")
                quickMessageButton("I am not feeling well")
            }

            quickMessageButton("I need help now")
        }
    }

    private func quickMessageButton(_ text: String) -> some View {
        Button {
            message = text
        } label: {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.energyCritical)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.energyCritical.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PeopleMapView(viewModel: CommunityViewModel())
}
