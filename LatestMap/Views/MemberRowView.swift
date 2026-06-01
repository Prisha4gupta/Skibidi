import SwiftUI

/// Reusable list row: avatar, name, condition label, and energy score. Stateless — pure render of `member`.
struct MemberRowView: View {
    let member: Member

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.avatar)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.headline)
                Text(member.conditionStatus.displayName)
                    .font(.subheadline)
                    .foregroundStyle(color(for: member.conditionStatus))
            }

            Spacer()

            Text("\(member.energyScore)")
                .font(.title3.bold())
                .foregroundStyle(color(for: member.conditionStatus))
        }
        .padding(.vertical, 4)
    }

    // REVIEW: condition→color mapping duplicated in MemberPin; consider a shared
    // `ConditionStatus.color` to keep map pins and rows consistent.
    private func color(for status: ConditionStatus) -> Color {
        switch status {
        case .energetic: return .green
        case .normal:    return .blue
        case .tired:     return .orange
        case .exhausted: return .red
        }
    }
}
