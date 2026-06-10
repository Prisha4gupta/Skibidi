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

    /// Energy ring around the avatar reflects health sharing (grey when never shared).
    private var healthRingColor: Color {
        user.displayedEnergyScore.map { Color.energyColor(for: $0) } ?? Color(.systemGray3)
    }

    private var displayName: String {
        user.isCurrentUser ? "You" : user.name
    }

    private var energyLabel: String {
        guard let score = user.displayedEnergyScore else { return "Hidden" }
        return score > 70 ? "High" : "Low"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            activityRingSummary

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if user.healthSharing.hasData {
                    VStack(spacing: 10) {
                        summaryRow(
                            label: "Energy",
                            value: energyLabel,
                            color: healthRingColor
                        )

                        summaryRow(
                            label: "Steps",
                            value: "\(user.healthSnapshot.steps)",
                            color: .metricSteps
                        )
                    }
                    .staleStyle(user.healthSharing.isStale)
                } else {
                    unavailableSummary(title: "Not shared", subtitle: "This member hasn't enabled health sharing")
                }
            }
        }
        .padding(18)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private var activityRingSummary: some View {
        ZStack {
            if user.fitnessSharing.hasData {
                ActivityRingView(
                    moveProgress: user.healthSnapshot.moveProgress,
                    exerciseProgress: user.healthSnapshot.exerciseProgress,
                    standProgress: user.healthSnapshot.standProgress,
                    size: 104,
                    lineWidth: 10
                )
                .staleStyle(user.fitnessSharing.isStale)
            } else {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                    .frame(width: 104, height: 104)
            }

            EmojiAvatarView(
                emoji: user.emoji,
                size: 42,
                ringColor: healthRingColor,
                ringWidth: 2.5,
                backgroundColor: Color(.systemGray6)
            )
        }
        .frame(width: 110, height: 110)
    }

    private func summaryRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func unavailableSummary(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
