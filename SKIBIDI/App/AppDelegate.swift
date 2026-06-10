import SwiftUI
import CloudKit

/// Installs `SceneDelegate` so CloudKit share invites actually reach us. In a SwiftUI
/// scene-based app, `application(_:userDidAcceptCloudKitShareWith:)` on the app delegate is
/// NEVER called — iOS delivers share acceptance to the window-scene delegate instead, so one
/// must be wired in explicitly. (This was the bug behind "tap the invite link, nothing
/// happens": the app launched, but the accept callback had no delegate to land on.)
///
/// Requires `CKSharingSupported = YES` in Info.plist so the system offers this app for the link.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // CloudKit change subscriptions deliver via silent push, which needs a device token
        // but no user-facing permission prompt — safe to register unconditionally.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [Push] remote-notification registration failed:", error.localizedDescription)
    }

    /// A CloudKit database subscription fired: something changed server-side. Hand it to the
    /// ViewModel as "refresh now" — the snapshot diff there works out what actually happened.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // UIKit hands the payload over as [AnyHashable: Any]; CKNotification wants [String: Any].
        guard let payload = userInfo as? [String: Any],
              CKNotification(fromRemoteNotificationDictionary: payload) != nil else {
            completionHandler(.noData)
            return
        }
        NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil)
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// Accepts incoming CloudKit share invites. Two delivery paths, same handling:
/// - app already running or suspended → `windowScene(_:userDidAcceptCloudKitShareWith:)`
/// - cold-launched by tapping the link → the metadata rides in on `connectionOptions`
///
/// Accepting adds the owner's community zone to this user's Shared database; the regular ~12s
/// poll (`CommunityViewModel.refreshCloudCommunities`) then discovers the new community via
/// `CloudKitService.fetchCommunities()` — no relaunch needed.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])

        operation.perShareResultBlock = { _, result in
            switch result {
            case .success:
                print("✅ [Share] accepted — community zone is now in your Shared DB.")
                // Tell the ViewModel right away so it writes my record into the new zone and
                // refreshes — joining feels instant instead of waiting for the ~12s poll.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cloudKitShareAccepted, object: nil)
                }
            case .failure(let error):
                print("❌ [Share] accept failed:", error)
            }
        }
        operation.acceptSharesResultBlock = { result in
            if case .failure(let error) = result {
                print("❌ [Share] accept operation failed:", error)
            }
        }

        container.add(operation)
    }
}

extension Notification.Name {
    /// Posted by `SceneDelegate` once a share invite is accepted, so `CommunityViewModel` can
    /// sync my record into the just-joined zone and refresh immediately.
    static let cloudKitShareAccepted = Notification.Name("cloudKitShareAccepted")

    /// Posted when a CloudKit silent push reports server-side changes, so `CommunityViewModel`
    /// refreshes right away instead of waiting for the next poll tick.
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}
