import SwiftUI
import CloudKit

/// Handles incoming CloudKit share invites. When someone taps the share link, iOS launches the
/// app and calls this with the share metadata; we accept it, which adds the owner's community zone
/// to this user's Shared database. After that, `CloudKitService.fetchCommunities()` finds it
/// and reads/writes there.
///
/// Requires `CKSharingSupported = YES` in Info.plist so the system offers this app for the link.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        let container = CKContainer(identifier: metadata.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])

        operation.perShareResultBlock = { _, result in
            switch result {
            case .success:
                print("✅ [Share] accepted — group zone is now in your Shared DB. Relaunch to see members.")
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
