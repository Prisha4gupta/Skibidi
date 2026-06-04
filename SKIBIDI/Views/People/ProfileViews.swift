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
                    EmojiAvatarView(
                        emoji: member.emoji,
                        size: 70,
                        ringColor: Color.energyColor(for: member.healthSnapshot.energyScore),
                        ringWidth: 4,
                        backgroundColor: Color(.systemGray6)
                    )
                    
                   
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
                Text(user.name)
                    .font(.title2.bold())
                
                Menu {
                    Button("Account", action: {})
                    Button("Hide activity", action: {})
                    Button("Private mode", action: {})
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
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
                    EmojiAvatarView(
                        emoji: user.emoji,
                        size: 70,
                        ringColor: Color.energyColor(for: user.healthSnapshot.energyScore),
                        ringWidth: 4,
                        backgroundColor: Color(.systemGray6)
                    )
                    
                    SuggestionBanner(text: user.healthSnapshot.suggestion)
                        .padding(.horizontal, 20)

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
