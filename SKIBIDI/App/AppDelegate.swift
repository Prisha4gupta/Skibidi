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
