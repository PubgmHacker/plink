import SwiftUI
import UIKit

// MARK: - Share Manager (Блок 5 — мгновенный Share-Link)
/// Управляет потоком «поделиться комнатой»:
/// 1. Генерирует ссылку `https://yourdomain.com/<roomId>`.
/// 2. Копирует её в буфер обмена (`UIPasteboard`).
/// 3. Вызывает нативный `UIActivityViewController` (Share Sheet).
/// 4. Триггерит Toast «Ссылка скопирована!» через callback.
@MainActor
final class ShareManager {

    /// Базовый домен приложения (deep-link base).
    /// В продакшене — реальный домен App Store / Universal Links.
    static let shareBaseURL = "https://plink.app"

    /// Генерирует share-link для комнаты.
    static func shareURL(for roomID: String, code: String? = nil) -> URL {
        // Используем короткий код если есть — удобнее для ручного ввода.
        if let code, !code.isEmpty {
            return URL(string: "\(shareBaseURL)/r/\(code)")!
        }
        return URL(string: "\(shareBaseURL)/r/\(roomID)")!
    }

    /// Полный share-flow: копирует ссылку + показывает Share Sheet.
    /// `onCopied` — callback для показа Toast в UI-слое.
    static func shareRoom(
        roomID: String,
        code: String?,
        roomName: String,
        onCopied: @escaping () -> Void
    ) {
        let url = shareURL(for: roomID, code: code)
        let shareText = "Присоединяйся к «\(roomName)» в Плинк! 🎬\n\(url.absoluteString)"

        // 1. Копируем в буфер обмена
        UIPasteboard.general.string = url.absoluteString

        // 2. Toast-уведомление
        HapticManager.notification(.success)
        onCopied()

        // 3. Нативный Share Sheet
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )

        // На iPad нужен popoverAnchor
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
