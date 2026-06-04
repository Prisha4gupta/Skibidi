import SwiftUI

/// Small pill shown next to paused (frozen) data, signalling it's a last-known snapshot, not live.
struct StaleBadge: View {
    var text: String = "Paused · last known"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.circle.fill")
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(Color.energyLow)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.energyLow.opacity(0.15), in: Capsule())
    }
}

/// Placeholder shown in place of a data section a member has never shared (`.never`).
struct NotSharedCard: View {
    /// e.g. "health" or "fitness".
    let kind: String
    var icon: String = "eye.slash.fill"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("\(kind.capitalized) not shared")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This member hasn't enabled \(kind) sharing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    /// Dims and de-emphasizes a view when its underlying data is a frozen (paused) snapshot.
    @ViewBuilder
    func staleStyle(_ isStale: Bool) -> some View {
        if isStale {
            self.opacity(0.7).saturation(0.6)
        } else {
            self
        }
    }
}

#Preview("Sharing components") {
    VStack(spacing: 20) {
        StaleBadge()
        NotSharedCard(kind: "health")
        NotSharedCard(kind: "fitness", icon: "figure.run")
    }
    .padding()
}
