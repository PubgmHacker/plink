// Plink/V4/V4Components.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4Avatar: View {
    let letter: String
    /// Ключ личности: идентификатор или @ник владельца буквы. Пусто — цвет
    /// выводится из самой буквы. Тема приложения здесь не участвует: один
    /// человек — один цвет во всех списках, у любого смотрящего.
    var seed: String = ""
    var size: CGFloat = 43
    var isPremium: Bool = false
    var isAdmin: Bool = false
    /// Optional remote photo — falls back to letter gradient when missing/failed.
    var imageURL: URL? = nil
    var body: some View {
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letterFallback
                    }
                }
            } else {
                letterFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Кольцо роли — из единой системы (Plink/Design/Identity). Раньше
        // здесь была своя реализация: жёстко заданный красный RGB вместо
        // токена, толщина 2.5 pt против 2 pt в AvatarView и вращение за 4 с
        // против 3.2 с. Premium-кольцо к тому же красилось акцентом темы,
        // поэтому у подписчика цвет статуса менялся вместе с оформлением.
        .plinkIdentityRing(isAdmin: isAdmin, isPremium: isPremium, diameter: size)
    }

    /// Градиент личности вместо градиента темы: до 25.08.2026 буква красилась
    /// парой из V4Theme.colors, поэтому все люди в списке были одного цвета,
    /// и этот цвет менялся вместе с оформлением приложения.
    private var letterFallback: some View {
        ZStack {
            Circle()
                .fill(PlinkAvatarPalette.gradient(for: seed.isEmpty ? letter : seed))
            Text(letter)
                // Буква растёт вместе с кругом: фиксированные 14–16 pt в
                // аватаре 96 pt (хиро профиля) выглядели горошиной.
                .font(.system(size: max(14, size * 0.375), weight: .black))
                .foregroundStyle(V4.ink)
        }
    }
}

/// Resolves avatar URL from stored field or always-available `/users/:id/avatar` endpoint.
///
/// Realtime friend updates: server puts `?v=<avatarUpdatedAt ms>` on avatarURL.
/// When `v` changes we drop the memory cache and notify UI — no global flash.
enum PlinkAvatarURL {
    static let apiBase = PlinkConfig.baseURLString

    /// Bumped when friends list / profiles reload so AsyncImage refetches immediately.
    static var sessionBust: Int {
        get { UserDefaults.standard.integer(forKey: "plink.avatarSessionBust") }
        set { UserDefaults.standard.set(newValue, forKey: "plink.avatarSessionBust") }
    }

    /// Per-user avatar version (from server `?v=` / avatarVersion). Survives list reloads.
    private static var versionByUserId: [String: String] = [:]

    static func bumpSessionBust() {
        sessionBust &+= 1
        NotificationCenter.default.post(name: .plinkAvatarsDidChange, object: sessionBust)
    }

    /// Record server avatar revision for a user. Returns true if version changed.
    /// First seed (prev empty → non-empty) does NOT notify (avoids flash on cold load).
    @discardableResult
    static func noteAvatar(userId: String, storedURL: String?, version: String? = nil) -> Bool {
        guard !userId.isEmpty else { return false }
        let extracted = (version ?? extractVersion(from: storedURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prev = versionByUserId[userId] ?? ""
        // Same version — no-op
        if extracted == prev { return false }
        let isFirstSeed = prev.isEmpty && !extracted.isEmpty
        versionByUserId[userId] = extracted
        // Drop any cached image for this user (old and new URL keys)
        if !isFirstSeed {
            PlinkAvatarImageCache.shared.removeAll(matchingUserId: userId)
            NotificationCenter.default.post(
                name: .plinkUserAvatarDidChange,
                object: userId,
                userInfo: ["version": extracted, "url": storedURL as Any]
            )
            // Nudge list observers that use session bust (not on first seed)
            bumpSessionBust()
        }
        return !isFirstSeed
    }

    static func currentVersion(for userId: String) -> String? {
        versionByUserId[userId]
    }

    private static func extractVersion(from raw: String?) -> String? {
        guard let raw, !raw.isEmpty,
              let comps = URLComponents(string: raw),
              let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
              !v.isEmpty else { return nil }
        return v
    }

    /// Always bind avatar to a concrete userId so one person's photo/letter
    /// never leaks onto another friend's row or chat bubble.
    static func resolve(userId: String?, stored: String?, cacheBust: Bool = true) -> URL? {
        let uid = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
        var raw = ""

        // Prefer server-provided URL when it already carries ?v= (realtime revision)
        let storedTrim = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedTrim.isEmpty, storedTrim.contains("/avatar") {
            raw = storedTrim.hasPrefix("/") ? apiBase + storedTrim : storedTrim
        } else if let uid, !uid.isEmpty {
            raw = "\(apiBase)/api/users/\(uid)/avatar"
        } else if !storedTrim.isEmpty {
            raw = storedTrim.hasPrefix("/") ? apiBase + storedTrim : storedTrim
        }

        guard !raw.isEmpty, var components = URLComponents(string: raw) else { return nil }
        var items = components.queryItems ?? []

        // Prefer known per-user version over stale query / session bust
        if let uid, let ver = versionByUserId[uid], !ver.isEmpty {
            items.removeAll { $0.name == "v" || $0.name == "b" || $0.name == "t" }
            items.append(URLQueryItem(name: "v", value: ver))
        } else if cacheBust {
            // Session bust only when we have no per-user version yet
            if items.first(where: { $0.name == "v" }) == nil {
                items.removeAll { $0.name == "b" || $0.name == "t" }
                items.append(URLQueryItem(name: "b", value: "\(sessionBust)"))
            }
        }

        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// URL for chat / list — uses per-user `?v=` so a friend photo update swaps immediately
    /// without thrashing every poll (version only changes on real avatar upload).
    static func stable(userId: String?, stored: String?) -> URL? {
        if let userId, !userId.isEmpty {
            // Keep version map warm from stored URL
            if let v = extractVersion(from: stored) {
                if versionByUserId[userId] != v {
                    versionByUserId[userId] = v
                }
            }
        }
        return resolve(userId: userId, stored: stored, cacheBust: false)
    }

    /// Letter for placeholder: strip @, use first unicode scalar uppercased.
    static func letter(from name: String?) -> String {
        var t = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") { t = String(t.dropFirst()) }
        guard let ch = t.first else { return "?" }
        return String(ch).uppercased()
    }
}

extension Notification.Name {
    static let plinkAvatarsDidChange = Notification.Name("plink.avatarsDidChange")
    /// object = userId (String)
    static let plinkUserAvatarDidChange = Notification.Name("plink.userAvatarDidChange")
    /// object = friendId, userInfo["at"] = Date — DM activity for presence
    static let plinkFriendActivity = Notification.Name("plink.friendActivity")
    /// object = groupId (String) — аватар беседы сменили в настройках
    static let plinkGroupAvatarDidChange = Notification.Name("plink.groupAvatarDidChange")
}

struct V4RoundButton: View {
    let symbol: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) { Text(symbol) }
            .buttonStyle(PlinkGlassIconButtonStyle(diameter: 44))
    }
}

struct V4Heading: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 10.88, weight: .heavy))
                .tracking(1.1968)
                // Надзаголовок — служебная микро-метка, а не акцент: ярко-синие
                // капс-строки над каждым титулом складывались с акцентными
                // кнопками ниже в «три синих пятна подряд» и дешевили экран.
                .foregroundStyle(V4.muted)
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-1.6)
                .lineSpacing(1.28)
                .foregroundStyle(V4.ink)
            if let subtitle { Text(subtitle).font(.system(size: 13.12)).foregroundStyle(V4.muted) }
        }
    }
}

private struct V4CardGradient: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(
                colors: [V4.cardBG, V4.cardBG.opacity(0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
    }
}

struct V4Hero: View {
    let title: String
    let meta: String
    let button: String
    let height: CGFloat
    let theme: V4Theme
    let action: () -> Void
    var liveThemeIndex: Int = 0
    /// Сервис, где идёт контент («Иви», «Netflix», «YouTube»). Рисуется
    /// заметным бейджем над заголовком: похороненный первым сегментом
    /// мелкой меты источник было не разглядеть — а «чей это фильм и где
    /// показывается» для витрины агрегатора главный вопрос.
    var provider: String? = nil
    /// Кадр контента. Без него герой — пустой градиент, который ничего не
    /// говорит о видео; градиенты ниже остаются фоном на время загрузки.
    var artworkURL: URL? = nil
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c1, Color.oklch(0.10,0.02,190)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [c2, .clear], center: UnitPoint(x: 0.72, y: 0.22), startRadius: 0, endRadius: height * 0.42)
            if let artworkURL {
                // Кадр — оверлеем над Color.clear: сам scaledToFill-имидж
                // отчитывается layout-шириной больше экрана (16:9 при заданной
                // высоте) и распирал бы ZStack за края.
                Color.clear
                    .frame(height: height)
                    .overlay {
                        AsyncImage(url: artworkURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                    }
                    .clipped()
            }
            // Скрим поверх кадра — иначе заголовок и мета тонут в артворке.
            LinearGradient(colors: [.clear, Color.oklch(0.06,0.01,190,alpha:0.95)], startPoint: UnitPoint(x:0.5,y:0.28), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                if let provider, !provider.isEmpty {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(brandColor(provider))
                            .frame(width: 7, height: 7)
                        Text(provider.uppercased())
                            .font(.system(size: 12.5, weight: .heavy))
                            .tracking(2.0)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    .accessibilityLabel("Сервис: \(provider)")
                }
                // Названия с YouTube бывают в пять строк — такой заголовок
                // съедает весь кадр героя целиком.
                Text(title).font(.system(size: 26.4, weight: .bold)).foregroundStyle(V4.ink)
                    .lineLimit(2)
                Text(meta).font(.system(size: 13.12)).foregroundStyle(V4.muted)
                    .lineLimit(1)
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                        Text(button)
                    }
                }
                // Белая, как Play у Apple TV и Netflix: главная CTA статична
                // и не зависит от темы — тема живёт в фоне героя (градиенты
                // выше). Акцентная заливка перекрашивала кнопку с каждой
                // палитрой и терялась на пёстрых кадрах.
                .buttonStyle(
                    PlinkProminentButtonStyle(
                        tint: .white,
                        textColor: .black,
                        height: 48,
                        cornerRadius: 16,
                        fillsWidth: false
                    )
                )
            }.padding(.horizontal, 19).padding(.bottom, 18)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .shadow(color: .black.opacity(0.40), radius: 27, y: 25)
    }

    /// Фирменный цвет точки в бейдже сервиса. Неизвестный сервис получает
    /// нейтральную белую точку — бейдж остаётся читаемым без словаря брендов.
    private func brandColor(_ name: String) -> Color {
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "иви", "ivi":     return Color(red: 0.92, green: 0.00, blue: 0.24)
        case "netflix":        return Color(red: 0.90, green: 0.03, blue: 0.08)
        case "youtube":        return Color(red: 1.00, green: 0.00, blue: 0.00)
        case "кинопоиск":      return Color(red: 1.00, green: 0.40, blue: 0.00)
        // Второй каталог витрины (26.08.2026): без своей строки точка героя
        // была белой заглушкой — единственный кинотеатр без цвета бренда.
        case "premier":        return Color(red: 0.94, green: 0.27, blue: 0.27)
        case "окко", "okko":   return Color(red: 1.00, green: 0.00, blue: 0.20)
        case "смотрим":        return Color(red: 0.00, green: 0.63, blue: 0.69)
        default:               return .white.opacity(0.75)
        }
    }
}

// MARK: - Кнопка закрытия шита

/// Единая кнопка закрытия модальных экранов: круглый стеклянный крестик
/// в правом верхнем углу — как у нативных шитов Apple (Music, App Store).
///
/// 22.08.2026: заменила текстовую «Закрыть» в
/// ToolbarItem(placement: .cancellationAction) во всех шитах. Синий текст
/// слева — паттерн iOS 13: красился системным tint вместо темы и выбивался
/// из Liquid Glass-языка V4. Крестик всегда справа — закрытие в одном и том
/// же месте на каждом экране; вторичные действия шита живут слева.
struct V4SheetCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.light)
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(V4.ink)
                .frame(width: 32, height: 32)
                .plinkGlass(.control, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Закрыть")
        .accessibilityIdentifier("sheet.close")
    }
}

/// Крестик закрытия для системного тулбара. На iOS 26 навигационная панель
/// сама оборачивает каждый элемент в собственную стеклянную капсулу — поверх
/// нашего 32-пт стекла вырастал второй серый круг, чужой всему UI. Скрываем
/// системную подложку: остаётся единый V4-крестик, тот же, что в инлайновых
/// шапках шитов.
struct V4SheetCloseToolbarItem: ToolbarContent {
    var action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) {
                V4SheetCloseButton(action: action)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                V4SheetCloseButton(action: action)
            }
        }
    }
}

