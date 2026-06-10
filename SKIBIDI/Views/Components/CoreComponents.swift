import SwiftUI

struct EmojiAvatarView: View {
    let emoji: String
    var size: CGFloat = 48
    var ringColor: Color? = nil
    var ringWidth: CGFloat = 3
    var backgroundColor: Color = Color(.systemGray6)
    
    var body: some View {
        ZStack {
            if let ringColor {
                Circle()
                    .fill(ringColor.opacity(0.2))
                    .frame(width: size + ringWidth * 2 + 4, height: size + ringWidth * 2 + 4)
                
                Circle()
                    .stroke(ringColor, lineWidth: ringWidth)
                    .frame(width: size + ringWidth * 2, height: size + ringWidth * 2)
            }
            
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)
            
            Text(emoji)
                .font(.system(size: size * 0.5))
        }
    }
}

struct StatusBadge: View {
    let status: MemberStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(statusColor)
    }
    
    private var statusColor: Color {
        switch status {
        case .active: return .activeGreen
        case .normal: return .secondaryText
        case .inactive: return .tertiaryText
        }
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}
struct SuggestionBanner: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.body)
                .foregroundStyle(.blue)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MemberRowView: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 14) {
            EmojiAvatarView(
                emoji: user.emoji,
                size: 42,
                ringColor: user.displayedEnergyScore.map { Color.energyColor(for: $0) } ?? Color(.systemGray3)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user.isCurrentUser ? "You" : user.name)
                    .font(.body.weight(.semibold))
                
                if !user.isCurrentUser {
                    Text(user.status == .active ? "Normal" : user.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            StatusBadge(status: user.status)
        }
        .padding(.vertical, 6)
    }
    
}

/// Round team avatar: the uploaded photo when the team has one, otherwise the generic
/// person-group glyph on gray.
struct CommunityAvatarView: View {
    let imageData: Data?
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)

                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CommunityRowView: View {
    let community: Community
    var showChevron: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            CommunityAvatarView(imageData: community.imageData, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name)
                    .font(.body.weight(.medium))
            }
            
            Spacer()
            
            if community.hasNotification && showChevron {
                HStack(spacing: 4) {
                    Text("View")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiaryText)
                }
            } else {
                Text("Active")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.activeGreen)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: 20) {
            EmojiAvatarView(emoji: "👻", size: 60, ringColor: .moveRing)
            EmojiAvatarView(emoji: "😍", size: 60, ringColor: .exerciseRing)
            
            StatusBadge(status: .active)
            StatusBadge(status: .normal)
            
            SuggestionBanner(text: "Suggestion: 31143 steps already, consider a long break.")
        }
        .padding()
    }
}
