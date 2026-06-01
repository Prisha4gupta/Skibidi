import SwiftUI
import MapKit

struct PeopleMapView: View {
    @StateObject private var viewModel: PeopleMapViewModel

    init(viewModel: PeopleMapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Map(
            coordinateRegion: $viewModel.region,
            annotationItems: viewModel.members
        ) { member in
            MapAnnotation(coordinate: member.location.coordinate) {
                MemberPin(member: member)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { viewModel.onAppear() }
    }
}

private struct MemberPin: View {
    let member: Member

    // 0...1 fraction of the ring to fill
    private var energyFraction: CGFloat {
        CGFloat(min(max(member.energyScore, 0), 100)) / 100
    }

    private var ringColor: Color {
        switch EnergyScore.condition(for: member.energyScore) {
        case .energetic: return .green
        case .normal:    return .blue
        case .tired:     return .orange
        case .exhausted: return .red
        }
    }

    var body: some View {
        ZStack {
            // Avatar
            Image(systemName: member.avatar)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .padding(7)
                .background(.white, in: Circle())

            // Faint full-circle track behind the progress arc
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 4)
                .frame(width: 48, height: 48)

            // Energy progress arc
            Circle()
                .trim(from: 0, to: energyFraction)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [ringColor.opacity(0.7), ringColor]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(-90)) // start at top, fill clockwise
                .shadow(color: ringColor.opacity(0.6), radius: 3)
        }
        .background(
            // little pointer tail under the pin
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 8)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .offset(y: 28)
        )
        .animation(.easeInOut, value: energyFraction)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY)) // bottom tip
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
