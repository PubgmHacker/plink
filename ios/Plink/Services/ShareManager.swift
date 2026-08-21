import SwiftUI
import UIKit

// MARK: - Share Manager (block 5 — instant share link)
/// Drives the "share this room" flow:
/// 1. Builds `<share-origin>/r/<code>` (see `PlinkURLs`).
/// 2. Copies it to the clipboard (`UIPasteboard`).
/// 3. Presents the native `UIActivityViewController` (share sheet).
/// 4. Fires the "link copied" toast through a callback.
@MainActor
final class ShareManager {

    /// Origin of the links a user hands to other people. The value, and the
    /// reason it is that value, live in `PlinkURLs.shareOrigin`.
    static var shareBaseURL: String { PlinkURLs.shareOrigin }

    /// Builds the share link for a room.
    static func shareURL(for roomID: String, code: String? = nil) -> URL {
        // Prefer the short code when there is one: it can be typed by hand.
        if let code, !code.isEmpty, let url = PlinkURLs.roomLink(code: code) {
            return url
        }
        return PlinkURLs.roomLink(code: roomID) ?? PlinkURLs.shareHome
    }

    /// Full share flow: copies the link and presents the share sheet.
    /// `onCopied` lets the UI layer show its toast.
    static func shareRoom(
        roomID: String,
        code: String?,
        roomName: String,
        onCopied: @escaping () -> Void
    ) {
        let url = shareURL(for: roomID, code: code)
        let shareText = "Присоединяйся к «\(roomName)» в Плинк! 🎬\n\(url.absoluteString)"

        // 1. Clipboard
        UIPasteboard.general.string = url.absoluteString
        AnalyticsService.shared.shareRoom()
        AnalyticsService.shared.funnelInvite()

        // 2. Toast
        HapticManager.notification(.success)
        onCopied()

        // 3. Native share sheet
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        // iPad needs a popover anchor.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let root = scene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = root.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 0,
                height: 0
            )
            root.present(activityVC, animated: true)
        }
    }
}
