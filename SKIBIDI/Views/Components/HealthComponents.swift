import SwiftUI
struct EnergyScoreView: View {
    let score: Int
    var size: CGFloat = 120
    
    @State private var animatedProgress: Double = 0
    
    private var progress: Double {
        Double(score) / 100.0
    }
    
    private var statusColor: Color {
        Color.energyColor(for: score)
    }
    
    private var statusText: String {
        Color.energyStatusText(for: score)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color(.systemGray5),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(135))
                
                Circle()
                    .trim(from: 0.0, to: animatedProgress * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [statusColor, statusColor.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(135))
                    .shadow(color: statusColor.opacity(0.3), radius: 4, x: 0, y: 2)
                
                VStack(spacing: 2) {
                    Text("Energy")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Text("\(score)/100")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                }
                .offset(y: -4)
            }
            
            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .offset(y: -16)
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                animatedProgress = progress
            }
        }
    }
}

struct MetricCardView: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    var iconColor: Color = .metricBlue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .metricCard()
    }
}

struct WellnessRingCard: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ActivityRingView(
                    moveProgress: user.healthSnapshot.moveProgress,
                    exerciseProgress: user.healthSnapshot.exerciseProgress,
                    standProgress: user.healthSnapshot.standProgress,
                    size: 100,
                    lineWidth: 10
                )
                
                EmojiAvatarView(
                    emoji: user.emoji,
                    size: 40,
                    ringColor: Color.energyColor(for: user.healthSnapshot.energyScore),
                    ringWidth: 2.5,
                    backgroundColor: Color(.systemGray6)
                )
            }
            VStack(alignment: .leading, spacing: 8) {
                metricRow(
                    label: "Move",
                    value: "\(user.healthSnapshot.moveCalories)/\(user.healthSnapshot.moveGoal) CAL",
                    color: .moveRing
                )
                
                metricRow(
                    label: "Exercise",
                    value: "\(user.healthSnapshot.exerciseMinutes)/\(user.healthSnapshot.exerciseGoal) MIN",
                    color: .exerciseRing
                )
                
                metricRow(
                    label: "Stand",
                    value: "\(user.healthSnapshot.standHours)/\(user.healthSnapshot.standGoal) HR",
                    color: .standRing
                )
            }
        }
        .padding(18)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private func metricRow(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
        }
    }
}

#Preview("Energy Score") {
    VStack(spacing: 30) {
        EnergyScoreView(score: 26, size: 140)
        EnergyScoreView(score: 75, size: 140)
        
        HStack(spacing: 12) {
            MetricCardView(icon: "figure.walk", title: "Steps", value: "31143", subtitle: "11.1 km", iconColor: .metricSteps)
            MetricCardView(icon: "moon.fill", title: "Sleep", value: "6.5h", subtitle: "Last Night", iconColor: .metricSleep)
        }
    }
    .padding()
}
