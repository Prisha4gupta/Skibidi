import SwiftUI
import MapKit

/// Communities tab: a map showing the selected community's members as `MemberPin` annotations,
/// with a persistent bottom sheet (`CommunitiesSheetView`) for picking which community to focus on.
struct CommunitiesMapView: View {
    /// `@StateObject` — this View owns the Communities tab VM's lifecycle.
    @StateObject private var viewModel: CommunitiesViewModel
    /// Passed through to `MemberDetailViewModel`s built in the sheet. // REVIEW: service threaded
    /// through the View layer — consider a VM factory or environment injection instead.
    let healthService: HealthService

    /// Sheet starts presented and is dismissal-disabled, so it acts as a permanent bottom panel.
    @State private var isSheetPresented: Bool = true

    init(viewModel: CommunitiesViewModel, healthService: HealthService) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.healthService = healthService
    }

    var body: some View {
        Map(
            coordinateRegion: $viewModel.region,
            annotationItems: viewModel.displayedMembers
        ) { member in
            MapAnnotation(coordinate: member.location.coordinate) {
                MemberPin(member: member)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { viewModel.onAppear() }
        .sheet(isPresented: $isSheetPresented) {
            CommunitiesSheetView(viewModel: viewModel, healthService: healthService)
                .presentationDetents([.height(120), .medium, .large])
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
        }
    }
}

/// Map annotation: avatar inside an energy-progress ring, color-coded by condition.
private struct MemberPin: View {
    let member: Member

    // 0...1 fraction of the ring to fill
    private var energyFraction: CGFloat {
        CGFloat(min(max(member.energyScore, 0), 100)) / 100
    }

    // REVIEW: re-derives condition from `energyScore` instead of using `member.conditionStatus`;
    // if the two fields disagree, the pin color won't match `MemberRowView`'s color.
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

/// Downward-pointing pin tail drawn behind `MemberPin`.
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
