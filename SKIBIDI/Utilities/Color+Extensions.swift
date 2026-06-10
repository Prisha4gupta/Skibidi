import SwiftUI

extension Color {
    // MARK: - Brand
    static let skibidiPurple = Color(red: 0.75, green: 0.52, blue: 0.99)
    static let skibidiPink = Color(red: 0.94, green: 0.67, blue: 0.98)
    /// Solid onboarding/splash background blue (~#3B82F6). The brand blue used full-bleed
    /// behind the splash, profile, and permissions screens.
    static let skibidiBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    /// Lighter top stop for the onboarding background gradient.
    static let skibidiBlueLight = Color(red: 0.39, green: 0.62, blue: 0.98)

    /// Full-bleed blue gradient behind the onboarding screens (light top → brand blue bottom).
    static var skibidiBlueGradient: LinearGradient {
        LinearGradient(
            colors: [.skibidiBlueLight, .skibidiBlue],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Activity Ring Colors (Apple Fitness inspired)
    static let moveRing = Color(red: 0.98, green: 0.24, blue: 0.40)        // Pink-red
    static let moveRingLight = Color(red: 0.99, green: 0.55, blue: 0.62)   // Lighter pink
    static let exerciseRing = Color(red: 0.30, green: 0.85, blue: 0.15)    // Bright green
    static let exerciseRingLight = Color(red: 0.60, green: 0.92, blue: 0.45)
    static let standRing = Color(red: 0.0, green: 0.80, blue: 0.85)        // Cyan/teal
    static let standRingLight = Color(red: 0.40, green: 0.90, blue: 0.92)
    
    // MARK: - Energy Score Status
    static let energyCritical = Color(red: 0.90, green: 0.20, blue: 0.20)
    static let energyLow = Color(red: 1.00, green: 0.62, blue: 0.12)
    static let energyGood = Color(red: 0.30, green: 0.78, blue: 0.35)
    static let energyExcellent = Color(red: 0.30, green: 0.78, blue: 0.35)
    
    // MARK: - UI Elements
    static let activeGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let badgeRed = Color(red: 0.95, green: 0.30, blue: 0.30)
    static let accentCoral = Color(red: 0.95, green: 0.40, blue: 0.35)
    
    // MARK: - Backgrounds
    static let cardBackground = Color(.systemBackground)
    static let sheetBackground = Color(.systemGroupedBackground)
    static let secondaryCardBackground = Color(.secondarySystemGroupedBackground)
    
    // MARK: - Text
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)
    
    // MARK: - Tab Bar
    static let tabBarSelected = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let tabBarUnselected = Color(.tertiaryLabel)
    
    // MARK: - Metric Card Icons
    static let metricBlue = Color(red: 0.25, green: 0.55, blue: 0.95)
    static let metricSteps = Color(red: 0.25, green: 0.55, blue: 0.95)
    static let metricSleep = Color(red: 0.45, green: 0.40, blue: 0.85)
    static let metricHeart = Color(red: 0.90, green: 0.30, blue: 0.35)
    static let metricHydration = Color(red: 0.20, green: 0.65, blue: 0.90)
    
    // MARK: - Helpers
    static func energyColor(for score: Int) -> Color {
        switch score {
        case 0...40: return .energyCritical
        case 41...70: return .energyLow
        default: return .energyGood
        }
    }
    
    static func energyStatusText(for score: Int) -> String {
        switch score {
        case 0...40: return "Low"
        case 41...70: return "Moderate"
        default: return "High"
        }
    }
}

extension ShapeStyle where Self == Color {
    static var skibidiPurple: Color { .skibidiPurple }
    static var skibidiPink: Color { .skibidiPink }
    static var skibidiBlue: Color { .skibidiBlue }
    static var moveRing: Color { .moveRing }
    static var moveRingLight: Color { .moveRingLight }
    static var exerciseRing: Color { .exerciseRing }
    static var exerciseRingLight: Color { .exerciseRingLight }
    static var standRing: Color { .standRing }
    static var standRingLight: Color { .standRingLight }
    static var energyCritical: Color { .energyCritical }
    static var energyLow: Color { .energyLow }
    static var energyGood: Color { .energyGood }
    static var energyExcellent: Color { .energyExcellent }
    static var activeGreen: Color { .activeGreen }
    static var badgeRed: Color { .badgeRed }
    static var accentCoral: Color { .accentCoral }
    static var cardBackground: Color { .cardBackground }
    static var sheetBackground: Color { .sheetBackground }
    static var secondaryCardBackground: Color { .secondaryCardBackground }
    static var primaryText: Color { .primaryText }
    static var secondaryText: Color { .secondaryText }
    static var tertiaryText: Color { .tertiaryText }
    static var tabBarSelected: Color { .tabBarSelected }
    static var tabBarUnselected: Color { .tabBarUnselected }
    static var metricBlue: Color { .metricBlue }
    static var metricSteps: Color { .metricSteps }
    static var metricSleep: Color { .metricSleep }
    static var metricHeart: Color { .metricHeart }
    static var metricHydration: Color { .metricHydration }
}
