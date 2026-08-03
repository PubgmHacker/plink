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
                                       diameter: size))
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

    /// Подсветка под аватаркой. Цвета — из единой системы уровней; раньше
    /// админ светился `Cinema2026.danger`, а Plink+ — мятным акцентом, из-за
    /// чего свечение расходилось с цветом самого кольца.
    private var shadowColor: Color {
        switch PlinkIdentityLevel(isAdmin: isAdmin, isPremium: isPremium) {
        case .admin:   return PlinkIdentityRing.adminColor.opacity(0.34)
        case .plus:    return PlinkIdentityRing.plusGlow.opacity(0.34)
        case .regular: return .clear
        }
    }

    // MARK: - Badge

    private var shouldShowBadge: Bool {
        (isPremium || isAdmin) && size >= 48
    }

    /// Бейдж уровня. Логика «кто получает бейдж» совпадает с кольцом:
    /// у подписчика-администратора кольцо золотое, поэтому бейдж — щит.
    private var badgeView: some View {
        PlinkIdentityBadge(
            kind: (isPremium && isAdmin) ? .admin : (isPremium ? .plus : .admin),
            diameter: size
        )
    }
}

// MARK: - Ring Modifier (выбирает Premium или Admin обводку)

/// Internal (not private) so PlinkStableAvatar in DMChatView can reuse it
/// for admin/Plink+ rings on chat avatars.
///
/// Теперь это тонкая обёртка над `PlinkIdentityRing` — единой системой
/// колец (Plink/Design/Identity). Раньше здесь была своя реализация с
/// цветами Cinema2026, расходившаяся с V4Avatar по цвету и толщине.
struct RingModifier: ViewModifier {
    let isPremium: Bool
    let isAdmin: Bool
    /// Диаметр аватарки: от него система колец считает толщину и канавку.
    let diameter: CGFloat

    func body(content: Content) -> some View {
        content.plinkIdentityRing(
            isAdmin: isAdmin,
            isPremium: isPremium,
            diameter: diameter
        )
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
// Маленький чип-бейдж «Админ» рядом с именем пользователя в Settings,
// Profile, EditProfile — не только в чате.
//
// Теперь это обёртка над `PlinkIdentityChip` из единой системы бейджей
// (Plink/Design/Identity). Раньше здесь была капсула с заливкой на 15 %,
// обводкой 0.5 pt и красным текстом, которому для читаемости подкладывали
// четыре тени по сторонам — именно это и выглядело дешёвым.
struct AdminBadgeChip: View {
    var compact: Bool = false    // true = только иконка (для tight layouts)

    var body: some View {
        PlinkIdentityChip(kind: .admin, compact: compact)
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
