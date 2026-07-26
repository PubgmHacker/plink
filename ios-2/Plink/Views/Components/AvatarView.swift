import SwiftUI
import UIKit

// MARK: - AvatarView — переиспользуемый аватар с Premium/Admin кольцами
//
// Единый компонент для всех экранов (Profile, Settings, Friends, Room participants).
// Гарантирует синхронный вид аватара везде + анимированные кольца для Premium/Admin.
//
// Использование:
//   AvatarView(imageURL: user.avatarURL, username: user.username, size: 96,
//              isPremium: user.isPremium, isAdmin: user.isAdmin)
//
// Логика:
//   • Admin → adminStroke (scarlet→maroon rotating) — приоритет над Premium
//   • Premium/Plink+ → premiumStroke (gold→bronze rotating)
//   • Бейдж внизу справа: crown для Premium, shield для Admin
//   • Если есть изображение — показывает его, иначе инициалы

struct AvatarView: View {
    let imageURL: String?
    let image: UIImage?
    let username: String
    let size: CGFloat
    let isPremium: Bool
    let isAdmin: Bool

    /// Convenience init без UIImage (только URL)
    init(imageURL: String?, username: String, size: CGFloat,
         isPremium: Bool = false, isAdmin: Bool = false) {
        self.imageURL = imageURL
        self.image = nil
        self.username = username
        self.size = size
        self.isPremium = isPremium
        self.isAdmin = isAdmin
    }

    /// Convenience init с UIImage (для локально загруженного аватара)
    init(image: UIImage?, imageURL: String?, username: String, size: CGFloat,
         isPremium: Bool = false, isAdmin: Bool = false) {
        self.image = image
        self.imageURL = imageURL
        self.username = username
        self.size = size
        self.isPremium = isPremium
        self.isAdmin = isAdmin
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ── Аватар ──
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                .modifier(RingModifier(isPremium: isPremium, isAdmin: isAdmin,
                                       lineWidth: ringWidth))
                .shadow(color: shadowColor, radius: size * 0.15, y: size * 0.06)

            // ── Бейдж (только для Premium/Admin, минимум size 48) ──
            if shouldShowBadge {
                badgeView
                    .offset(x: size * 0.02, y: size * 0.02)
            }
        }
    }

    // MARK: - Avatar Content

    @ViewBuilder
    private var avatarContent: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let imageURL, let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    fallback
                case .empty:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Cinema2026.accent, Cinema2026.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var initials: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        return String(trimmed.prefix(2)).uppercased()
    }

    // MARK: - Ring

    private var ringWidth: CGFloat {
        max(2, size * 0.035)
    }

    private var shadowColor: Color {
        if isAdmin {
            return Cinema2026.danger.opacity(0.4)
        } else if isPremium {
            return Cinema2026.accent.opacity(0.4)
        }
        return .clear
    }

    // MARK: - Badge

    private var shouldShowBadge: Bool {
        (isPremium || isAdmin) && size >= 48
    }

    private var badgeView: some View {
        let badgeSize = size * 0.32

        return ZStack {
            Circle()
                .fill(Cinema2026.background)
            Circle()
                .stroke(isAdmin ? Cinema2026.danger : Cinema2026.accent, lineWidth: 1)

            if isAdmin {
                // 🔧 FIX: user's custom admin icon (was SF Symbol 'shield.fill')
                Image("AdminBadge")
                    .resizable()
                    .scaledToFit()
                    .padding(badgeSize * 0.15)
                    .foregroundColor(Cinema2026.danger)
            } else {
                Image(systemName: "crown.fill")
                    .font(.system(size: badgeSize * 0.5, weight: .semibold))
                    .foregroundColor(Cinema2026.amber)
            }
        }
        .frame(width: badgeSize, height: badgeSize)
    }
}

// MARK: - Ring Modifier (выбирает Premium или Admin обводку)

/// Internal (not private) so PlinkStableAvatar in DMChatView can reuse it
/// for admin/Plink+ rings on chat avatars.
struct RingModifier: ViewModifier {
    let isPremium: Bool
    let isAdmin: Bool
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        if isAdmin {
            // Admin — приоритет над Premium
            content
                .adminStroke(lineWidth: lineWidth)
        } else if isPremium {
            content
                .premiumStroke(lineWidth: lineWidth)
        } else {
            // Обычный пользователь — тонкая статичная обводка
            content
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Default User") {
    AvatarView(imageURL: nil, username: "Alexander", size: 96,
               isPremium: false, isAdmin: false)
    .padding()
    .background(Cinema2026.background)
}

#Preview("Premium User") {
    AvatarView(imageURL: nil, username: "Premium", size: 96,
               isPremium: true, isAdmin: false)
    .padding()
    .background(Cinema2026.background)
}

#Preview("Admin User") {
    AvatarView(imageURL: nil, username: "Admin", size: 96,
               isPremium: false, isAdmin: true)
    .padding()
    .background(Cinema2026.background)
}
#endif

// MARK: - AdminBadgeChip
//
// 🔧 NEW: Маленький чип-бейдж «Админ» для размещения рядом с именем пользователя
// в Settings, Profile, EditProfile — не только в чате.
//
// 🔧 FIX: Uses Image('AdminBadge') — user's custom admin icon (uploaded PNG,
// 512×512 RGBA). Was using SF Symbol 'shield.fill' which user didn't want.
struct AdminBadgeChip: View {
    var compact: Bool = false    // true = только иконка (для tight layouts)

    var body: some View {
        HStack(spacing: 4) {
            Image("AdminBadge")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
            if !compact {
                Text("АДМИН")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    // 🔧 TEXT STROKE: тонкая чёрная обводка для читаемости красного текста
                    .shadow(color: .black.opacity(0.7), radius: 0.4, x: 0.4, y: 0)
                    .shadow(color: .black.opacity(0.7), radius: 0.4, x: -0.4, y: 0)
                    .shadow(color: .black.opacity(0.7), radius: 0.4, x: 0, y: 0.4)
                    .shadow(color: .black.opacity(0.7), radius: 0.4, x: 0, y: -0.4)
            }
        }
        .foregroundColor(Cinema2026.danger)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Cinema2026.danger.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(Cinema2026.danger.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Cinema2026.danger.opacity(0.4), radius: 4, y: 1)
    }
}

#Preview("Admin Badge Chip") {
    VStack(spacing: 12) {
        AdminBadgeChip()
        AdminBadgeChip(compact: true)
    }
    .padding()
    .background(Cinema2026.background)
}
