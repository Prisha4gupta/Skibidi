import SwiftUI
import MapKit

/// Manages community data, member selection, and navigation state for the People tab.
@MainActor
@Observable
class CommunityViewModel {
    // MARK: - Data
    var communities: [Community]
    var notifications: [AppNotification]
    var currentUser: User
    var activeSOSMessages: [UUID: String] = [:]
    
    // MARK: - Navigation State
    var selectedCommunity: Community?
    var selectedMember: User?
    var showingCommunitySheet = true
    var showingPeopleList = false
    var showingDashboard = false
    var showingMemberProfile = false
    var showingYourProfile = false
    var showingCreateCommunity = false
    var showingNotifications = false
    var showingEmergencySOS = false
    
    // MARK: - Map State
    var mapCameraPosition: MapCameraPosition
    
    init() {
        let mock = MockDataService.shared
        self.communities = mock.communities
        self.notifications = mock.notifications
        self.currentUser = mock.currentUser
        self.mapCameraPosition = .region(
            MKCoordinateRegion(
                center: mock.mapCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )
    }
    
    // MARK: - Map pins
    var visibleMapMembers: [User] {
        if let selectedCommunity {
            return selectedCommunity.members
        }

        return allMapMembers
    }

    var allMapMembers: [User] {
        var seen = Set<UUID>()
        var result: [User] = []
        for community in communities {
            for member in community.members {
                if !seen.contains(member.id) {
                    seen.insert(member.id)
                    result.append(member)
                }
            }
        }
        return result
    }

    func sosMessage(for user: User) -> String? {
        activeSOSMessages[user.id]
    }
    
    // MARK: - Actions
    func selectCommunity(_ community: Community) {
        selectedCommunity = community
        showingPeopleList = true
        showingCommunitySheet = false
    }
    
    func openDashboard() {
        showingPeopleList = false
        showingDashboard = true
    }
    
    func selectMember(_ member: User) {
        selectedMember = member
        if member.isCurrentUser {
            showingYourProfile = true
        } else {
            showingMemberProfile = true
        }
        showingPeopleList = false
        showingDashboard = false
    }
    
    func goBackToCommunities() {
        selectedCommunity = nil
        selectedMember = nil
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }
    
    func goBackToPeopleList() {
        selectedMember = nil
        showingMemberProfile = false
        showingYourProfile = false
        showingDashboard = false
        showingPeopleList = true
    }
    
    func dismissProfile() {
        selectedMember = nil
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }
    
    func createCommunity(name: String, type: CommunityType, memberCount: Int,
                         locationSharing: Bool, healthSharing: Bool, fitnessSharing: Bool,
                         dateActive: Date) {
        let newCommunity = Community(
            id: UUID(),
            name: name,
            type: type,
            imageData: nil,
            members: [currentUser],
            dateActive: dateActive,
            memberCount: memberCount,
            isLocationSharing: locationSharing,
            isHealthSharing: healthSharing,
            isFitnessSharing: fitnessSharing,
            hasNotification: false,
            notificationMessage: nil
        )
        communities.append(newCommunity)
        showingCreateCommunity = false
    }

    func leaveCommunity(_ community: Community) {
        communities.removeAll { $0.id == community.id }

        if selectedCommunity?.id == community.id {
            selectedCommunity = nil
            selectedMember = nil
            showingPeopleList = false
            showingDashboard = false
            showingMemberProfile = false
            showingYourProfile = false
            showingCommunitySheet = true
        }
    }

    func leaveAllCommunities() {
        communities.removeAll()
        selectedCommunity = nil
        selectedMember = nil
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = true
    }

    func sendEmergencySOS(message: String, communityID: UUID?) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        let targetCommunities = communities.filter { community in
            communityID == nil || community.id == communityID
        }

        for community in targetCommunities {
            notifications.insert(
                AppNotification(
                    id: UUID(),
                    communityName: community.name,
                    communityEmoji: "🚨",
                    message: "SOS from You: \(trimmedMessage)",
                    timestamp: Date(),
                    isRead: false
                ),
                at: 0
            )
        }

        activeSOSMessages[currentUser.id] = trimmedMessage

        for index in communities.indices {
            if communityID == nil || communities[index].id == communityID {
                communities[index].hasNotification = true
            }
        }

        showingEmergencySOS = false
        showingPeopleList = false
        showingDashboard = false
        showingMemberProfile = false
        showingYourProfile = false
        showingCommunitySheet = false
        showingNotifications = false
    }
}

/// Manages settings state: permissions, privacy, and location sharing.
@MainActor
@Observable
class SettingsViewModel {
    // MARK: - Permissions
    var isFitnessEnabled = true
    var isHealthEnabled = false
    var isWeatherEnabled = false
    
    // MARK: - Location
    var isLocationSharingEnabled = true
    
    // MARK: - Privacy
    var privacyLevel: PrivacyLevel = .everyone
    var showingPrivacyMenu = false
    
    // MARK: - Community
    var showingLeaveCommunity = false
    var communityToLeave: Community?
    
    // MARK: - Communities Reference
    var communities: [Community]
    
    init() {
        self.communities = MockDataService.shared.communities
    }
    
    func leaveCommunity(_ community: Community) {
        communities.removeAll { $0.id == community.id }
        showingLeaveCommunity = false
        communityToLeave = nil
    }

    func leaveAllCommunities() {
        communities.removeAll()
        showingLeaveCommunity = false
        communityToLeave = nil
    }
    
    func confirmLeave(community: Community) {
        communityToLeave = community
        showingLeaveCommunity = true
    }

    func confirmLeaveAllCommunities() {
        communityToLeave = nil
        showingLeaveCommunity = true
    }
}
