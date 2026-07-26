import SwiftUI
import UIKit

// MARK: - Регион и метаданные сервисов (M15)

enum ServiceRegion: String {
    case russian
    case international
    case universal

    var badge: String {
        switch self {
        case .russian: return "🇷🇺"
        case .international: return "🌍"
        case .universal: return "🔗"
        }
    }
}

extension VideoService {
    /// Российский / зарубежный / универсальный — для фильтров карусели.
    var region: ServiceRegion {
        switch self {
        case .vk, .rutube, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion:
            return .russian
        case .youtube, .netflix, .disney:
            return .international
        case .browser, .customURL:
            return .universal
        }
    }

    var isFree: Bool { !requiresSubscription }

    /// Определяем сервис по ссылке (например, из буфера обмена).
    static func detect(fromURL raw: String) -> VideoService? {
        guard let host = URL(string: raw)?.host?.lowercased() else { return nil }
        if host.contains("youtu") { return .youtube }
        if host.contains("vk.com") || host.contains("vkvideo") { return .vk }
        if host.contains("rutube") { return .rutube }
        if host.contains("kinopoisk") { return .kinopoisk }
        if host.contains("ivi.ru") { return .ivi }
        if host.contains("okko") { return .okko }
        if host.contains("wink") { return .wink }
        if host.contains("start.ru") { return .start }
        if host.contains("premier") { return .premier }
        if host.contains("smotrim") { return .smotrim }
        if host.contains("kion") { return .kion }
        if host.contains("netflix") { return .netflix }
        if host.contains("disney") { return .disney }
        if raw.contains(".mp4") || raw.contains(".m3u8") { return .customURL }
        return nil
    }
}

// MARK: - Фильтры карусели

enum ServicePickerFilter: String, CaseIterable, Identifiable {
    case all
    case russian
    case international
    case free
    case subscription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .russian: return "🇷🇺 Российские"
        case .international: return "🌍 Зарубежные"
        case .free: return "Без подписки"
        case .subscription: return "С подпиской"
        }
    }

    func matches(_ service: VideoService) -> Bool {
        switch self {
        case .all: return true
        case .russian: return service.region == .russian
        case .international: return service.region == .international
        case .free: return service.isFree
        case .subscription: return !service.isFree
        }
    }
}

// MARK: - Недавние сервисы

enum RecentServicesStore {
    private static let key = "plink.recentServices"
    private static let maxCount = 4

    static var recents: [VideoService] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .compactMap { VideoService(rawValue: $0) }
    }

    static func note(_ service: VideoService) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == service.rawValue }
        list.insert(service.rawValue, at: 0)
        UserDefaults.standard.set(Array(list.prefix(maxCount)), forKey: key)
    }
}

// MARK: - Чипы фильтров

struct ServiceFilterChips: View {
    @Binding var filter: ServicePickerFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ServicePickerFilter.allCases) { f in
                    Button {
                        HapticManager.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = f }
                    } label: {
                        Text(f.title)
                            .font(.system(size: 13, weight: filter == f ? .bold : .medium))
                            .foregroundStyle(filter == f ? .black : Cinema2026.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(filter == f ? Cinema2026.accent : Cinema2026.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Карточка сервиса в карусели

struct ServiceCarouselCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    private var authorized: Bool {
        !service.requiresAuth || ServiceAuthStore.hasAccess(to: service.serviceType)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ServiceLogoView(service: service, size: 40)
                    Spacer()
                    Text(service.region.badge)
                        .font(.system(size: 17))
                }

                Spacer()

                Text(service.title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                Text(service.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    badge(service.isFree ? "Без подписки" : "Подписка",
                          color: service.isFree ? Color.green : Color.orange)
                    if service.requiresAuth && authorized {
                        badge("✓ Вход выполнен", color: Color.white)
                    }
                }
                .padding(.top, 8)
            }
            .padding(16)
            .frame(width: 200, height: 168, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [service.accentColor.opacity(0.85), service.accentColor.opacity(0.35), Color.black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { p in
            withAnimation(.easeOut(duration: 0.12)) { pressed = p }
        }, perform: {})
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.32), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 0.5))
    }
}

// MARK: - Карточка «ссылка из буфера обмена»

struct ClipboardVideoCard: View {
    let url: String
    let service: VideoService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ссылка в буфере — \(service.title)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(1)
                    Text(url)
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Cinema2026.accent)
            }
            .padding(14)
            .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Cinema2026.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
