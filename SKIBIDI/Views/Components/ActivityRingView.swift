import SwiftUI

struct ActivityRingView: View {
    let moveProgress: Double
    let exerciseProgress: Double
    let standProgress: Double
    var size: CGFloat = 100
    var lineWidth: CGFloat = 12
    
    @State private var animatedMove: Double = 0
    @State private var animatedExercise: Double = 0
    @State private var animatedStand: Double = 0
    
    var body: some View {
        ZStack {
            ringBackground(radius: ringRadius(for: 0))
            ringBackground(radius: ringRadius(for: 1))
            ringBackground(radius: ringRadius(for: 2))
            
            ringProgress(
                progress: animatedMove,
                radius: ringRadius(for: 0),
                gradient: [.moveRing, .moveRingLight]
            )
            ringProgress(
                progress: animatedExercise,
                radius: ringRadius(for: 1),
                gradient: [.exerciseRing, .exerciseRingLight]
            )
            
            ringProgress(
                progress: animatedStand,
                radius: ringRadius(for: 2),
                gradient: [.standRing, .standRingLight]
            )
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8)) {
                animatedMove = moveProgress
                animatedExercise = exerciseProgress
                animatedStand = standProgress
            }
        }
    }
    
    private func ringRadius(for index: Int) -> CGFloat {
        let gap = lineWidth + 4
        return (size / 2) - (CGFloat(index) * gap) - (lineWidth / 2)
    }
    
    private func ringBackground(radius: CGFloat) -> some View {
        Circle()
            .stroke(lineWidth: lineWidth)
            .foregroundStyle(Color(.systemGray5))
            .frame(width: radius * 2, height: radius * 2)
    }
    
    private func ringProgress(progress: Double, radius: CGFloat, gradient: [Color]) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: gradient),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360 * progress)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(-90))
            .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 4, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 40) {
        ActivityRingView(
            moveProgress: 0.25,
            exerciseProgress: 0.50,
            standProgress: 0.42,
            size: 150,
            lineWidth: 16
        )
        
        ActivityRingView(
            moveProgress: 0.6,
            exerciseProgress: 0.75,
            standProgress: 0.8,
            size: 80,
            lineWidth: 10
        )
    }
    .padding()
}
