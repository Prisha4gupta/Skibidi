import SwiftUI

extension View {
    // MARK: - Glass Card Modifier
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Floating Card
    func floatingCard(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
    }
    
    // MARK: - Metric Card Style
    func metricCard() -> some View {
        self
            .padding(16)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Sheet Header Style
    func sheetHeader() -> some View {
        self
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
