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
    ///
    /// Строгий матч домена через PlinkHost. Прошлая версия матчила подстроки и
    /// была самой слабой из трёх копий этой логики в проекте: `contains("youtu")`
    /// принимал youtube-clone.ru, `contains("wink")` — любой winkle.io.
    /// Список доменов один — `PlinkHost`.
    static func detect(fromURL raw: String) -> VideoService? {
        guard let host = URL(string: raw)?.host else { return nil }
        if PlinkHost.matches(host, anyOf: PlinkHost.youtubeDomains)   { return .youtube }
        if PlinkHost.matches(host, anyOf: PlinkHost.vkDomains)        { return .vk }
        if PlinkHost.matches(host, anyOf: PlinkHost.rutubeDomains)    { return .rutube }
        if PlinkHost.matches(host, anyOf: PlinkHost.kinopoiskDomains) { return .kinopoisk }
        if PlinkHost.matches(host, anyOf: PlinkHost.iviDomains)       { return .ivi }
        if PlinkHost.matches(host, anyOf: PlinkHost.okkoDomains)      { return .okko }
        if PlinkHost.matches(host, anyOf: PlinkHost.winkDomains)      { return .wink }
        if PlinkHost.matches(host, anyOf: PlinkHost.startDomains)     { return .start }
        if PlinkHost.matches(host, anyOf: PlinkHost.premierDomains)   { return .premier }
        if PlinkHost.matches(host, anyOf: PlinkHost.smotrimDomains)   { return .smotrim }
        if PlinkHost.matches(host, anyOf: PlinkHost.kionDomains)      { return .kion }
        if PlinkHost.matches(host, anyOf: PlinkHost.netflixDomains)   { return .netflix }
        if PlinkHost.matches(host, anyOf: PlinkHost.disneyDomains)    { return .disney }
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
        // Эмодзи-флаги убраны: в чипах они выглядели как стикеры, а на части
        // устройств 🇷🇺 рендерится как «RU» — ширина чипа скакала.
        case .russian: return "Российские"
        case .international: return "Зарубежные"
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(filter == f ? V4.canvas : V4.ink)
                            .padding(.horizontal, 15)
                            .frame(minHeight: 36)
                            .background {
                                if filter == f {
                                    Capsule(style: .continuous).fill(V4.accent)
                                } else {
                                    // Невыбранные чипы — на стекле, как вся
                                    // остальная навигация приложения.
                                    Capsule(style: .continuous)
                                        .fill(.white.opacity(0.06))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(V4.line, lineWidth: 1)
                                        )
                                }
                            }
                            // Вес шрифта постоянный: раньше выбранный чип
                            // становился .bold и его ширина менялась, из-за
                            // чего соседние чипы дёргались при переключении.
                            .contentShape(Capsule())
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
                HStack(alignment: .top) {
                    // Логотип на нейтральной подложке. Раньше он лежал прямо
                    // на брендовом градиенте и терял контраст: белые марки
                    // (Apple TV+) растворялись, тёмные — сливались с углом.
                    ServiceLogoView(service: service, size: 40)
                        .padding(7)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                        )
                    Spacer()
                    if service.requiresAuth && authorized {
                        // Вход выполнен — единственный статус, который нужен
                        // в углу. Эмодзи-флаг региона убран: он выглядел как
                        // случайный стикер и дублировал фильтр над каруселью.
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(V4.canvas)
                            .frame(width: 22, height: 22)
                            .background(Color(hex: 0x33D17A), in: Circle())
                    }
                }

                Spacer()

                Text(service.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(service.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                accessTag
                    .padding(.top, 9)
            }
            .padding(15)
            .frame(width: 200, height: 168, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.34), radius: 14, y: 8)
            .scaleEffect(pressed ? 0.96 : 1)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { p in
            withAnimation(.easeOut(duration: 0.12)) { pressed = p }
        }, perform: {})
    }

    /// Фон: почти чёрная подложка приложения плюс мягкое пятно бренда в
    /// верхнем углу. Раньше градиент бренда заливал карточку целиком на 85 %,
    /// и полка из пяти сервисов превращалась в набор кричащих плашек, каждая
    /// со своим цветом — рядом с остальным тёмным интерфейсом это и читалось
    /// «дешёво».
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(V4.surface)
            RadialGradient(
                colors: [service.accentColor.opacity(0.40), .clear],
                center: UnitPoint(x: 0.16, y: 0.10),
                startRadius: 0,
                endRadius: 186
            )
        }
    }

    /// Доступность сервиса: подписка или свободный вход.
    private var accessTag: some View {
        let free = service.isFree
        let tint = free ? Color(hex: 0x33D17A) : V4.amber
        return HStack(spacing: 4) {
            Image(systemName: free ? "bolt.fill" : "lock.fill")
                .font(.system(size: 8.5, weight: .heavy))
            Text(free ? "Без подписки" : "Нужна подписка")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.3)
        }
        .foregroundStyle(V4.canvas)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint, in: Capsule(style: .continuous))
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
