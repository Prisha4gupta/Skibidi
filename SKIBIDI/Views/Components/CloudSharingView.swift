import SwiftUI
import CloudKit
import UIKit

/// Bundles the share + container so they can drive a SwiftUI `.sheet(item:)`.
/// (`CKShare`/`CKContainer` aren't `Identifiable`, so we wrap them.)
struct ShareSheetData: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Bridges UIKit's `UICloudSharingController` — the system "invite people" sheet (Messages,
/// Mail, copy link, manage participants) — into SwiftUI via `UIViewControllerRepresentable`.
/// Present it with `.sheet(item:)` using a `ShareSheetData`.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Required by `UICloudSharingController` to report save/stop/failure and supply a title.
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? { "SKIBIDI Group" }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            print("❌ [Share] failed to save:", error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("✅ [Share] saved — invite link is live")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("ℹ️ [Share] stopped sharing")
        }
    }
}
