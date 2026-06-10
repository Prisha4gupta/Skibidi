import SwiftUI
struct MemberProfileView: View {
    let member: User
    @Bindable var viewModel: CommunityViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            
            HStack {
                EmojiAvatarView(
                    emoji: member.emoji,
                    size: 30,
                    ringColor: member.displayedEnergyScore.map { Color.energyColor(for: $0) } ?? Color(.systemGray3),
                    ringWidth: 2,
                    backgroundColor: Color(.systemGray6)
                )
                Text(member.name)
                    .font(.title2.bold())
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.dismissProfile()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 16) {


                    if member.healthSharing == .never {
                        // Never shared → no data at all.
                        NotSharedCard(kind: "health")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                    } else {
                        // Paused → show last-known data, flagged as stale.
                        if member.healthSharing.isStale {
                            StaleBadge()
                        }

                        SuggestionBanner(text: member.healthSnapshot.suggestion)
                            .padding(.horizontal, 20)

                        HStack(alignment: .top, spacing: 12) {
                            EnergyScoreView(
                                score: member.healthSnapshot.energyScore,
                                size: 130
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            MetricCardView(
                                icon: "figure.walk",
                                title: "Steps",
                                value: "\(member.healthSnapshot.steps)",
                                subtitle: "\(String(format: "%.1f", member.healthSnapshot.stepsDistanceKm)) km",
                                iconColor: .metricSteps
                            )

                            MetricCardView(
                                icon: "moon.fill",
                                title: "Sleep",
                                value: "\(String(format: "%.1f", member.healthSnapshot.sleepHours))h",
                                subtitle: "Last Night",
                                iconColor: .metricSleep
                            )

                            MetricCardView(
                                icon: "heart.fill",
                                title: "Resting HR",
                                value: "\(member.healthSnapshot.restingHeartRate)",
                                subtitle: "bpm",
                                iconColor: .metricHeart
                            )

                            MetricCardView(
                                icon: "drop.fill",
                                title: "Hydration",
                                value: "\(member.healthSnapshot.hydrationPercent)%",
                                subtitle: "Today",
                                iconColor: .metricHydration
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                        .staleStyle(member.healthSharing.isStale)
                    }
                }
                .padding(.top, 4)
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
        .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
    }
}
struct YourProfileView: View {
    @Bindable var viewModel: CommunityViewModel
    @State private var showingMenu = false
    @State private var showingNameEditor = false
    @State private var draftName = ""
    
    private var user: User {
        viewModel.currentUser
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            

            HStack {
                EmojiAvatarView(
                    emoji: user.emoji,
                    size: 30,
                    ringColor: Color.energyColor(for: user.healthSnapshot.energyScore),
                    ringWidth: 2,
                    backgroundColor: Color(.systemGray6)
                )
                
                Text(user.name)
                    .font(.title2.bold())

                Button {
                    draftName = user.name
                    showingNameEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }

                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.dismissProfile()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 16) {

                    
                    SuggestionBanner(text: user.healthSnapshot.suggestion)
                        .padding(.horizontal, 20)

                    // Shown only while an SOS is active. Standing it down clears the broadcast so
                    // the map pin drops its red override and returns to the energy color.
                    if viewModel.isCurrentUserSOSActive {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.cancelSOS()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Cancel SOS")
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.energyCritical, in: Capsule())
                        }
                        .padding(.horizontal, 20)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        EnergyScoreView(
                            score: user.healthSnapshot.energyScore,
                            size: 130
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        MetricCardView(
                            icon: "figure.walk",
                            title: "Steps",
                            value: "\(user.healthSnapshot.steps)",
                            subtitle: "\(String(format: "%.1f", user.healthSnapshot.stepsDistanceKm)) km",
                            iconColor: .metricSteps
                        )
                        
                        MetricCardView(
                            icon: "moon.fill",
                            title: "Sleep",
                            value: "\(String(format: "%.1f", user.healthSnapshot.sleepHours))h",
                            subtitle: "Last Night",
                            iconColor: .metricSleep
                        )
                        
                        MetricCardView(
                            icon: "heart.fill",
                            title: "Resting HR",
                            value: "\(user.healthSnapshot.restingHeartRate)",
                            subtitle: "bpm",
                            iconColor: .metricHeart
                        )
                        
                        MetricCardView(
                            icon: "drop.fill",
                            title: "Hydration",
                            value: "\(user.healthSnapshot.hydrationPercent)%",
                            subtitle: "Today",
                            iconColor: .metricHydration
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .padding(.top, 4)
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
        .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
        .alert("Your name", isPresented: $showingNameEditor) {
            TextField("Name", text: $draftName)
            Button("Save") { viewModel.updateDisplayName(draftName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown to others in your communities.")
        }
    }
}

#Preview("Member Profile") {
    ZStack {
        Color(.systemGray4).ignoresSafeArea()
        VStack {
            Spacer()
            MemberProfileView(
                member: MockDataService.shared.member1,
                viewModel: CommunityViewModel()
            )
        }
    }
}

#Preview("Your Profile") {
    ZStack {
        Color(.systemGray4).ignoresSafeArea()
        VStack {
            Spacer()
            YourProfileView(viewModel: CommunityViewModel())
        }
    }
}
