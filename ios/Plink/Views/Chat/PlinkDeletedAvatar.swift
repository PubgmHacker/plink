// Telegram-style avatar for soft-deleted accounts.
import SwiftUI

struct PlinkDeletedAvatar: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.28),
                            Color(white: 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Ghost / person-slash silhouette
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityLabel("Удалённый аккаунт")
    }
}
