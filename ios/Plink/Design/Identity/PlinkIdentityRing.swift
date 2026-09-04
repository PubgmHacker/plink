// Plink/Design/Identity/PlinkIdentityRing.swift
//
// Единая система колец и бейджей вокруг аватарок.
//
// До этого файла в приложении жили ЧЕТЫРЕ независимых реализации кольца:
// VIPAvatarRingModifier (CinemaComponents), RingModifier (AvatarView),
// V4Avatar (V4Components) и тонирование фона в WatchRoomOverlays. У них
// расходились цвета (админ был то #FF2D55, то RGB(1,0.2,0.3), то amber),
// толщина (2 / 2.5 / 1.5 pt), длительность вращения (3.2 с против 4 с) и
// даже смысл: в одном месте кольцо означало роль, в другом — «говорит
// сейчас». Здесь всё сведено к одному источнику истины.
//
// Правило разделения каналов (так делают Discord, Instagram и Twitch):
// на аватарке одновременно живут максимум ДВА сигнала — кольцо роли и
// один угловой бейдж. Всё остальное (онлайн-точка) ставится в свободный
// угол и получает собственную «канавку» цвета фона, чтобы не сливаться.

import SwiftUI

// MARK: - Уровень аккаунта

/// Три уровня, которые кольцо обязано различать.
///
/// Порядок важен: при совпадении (админ с подпиской) кольцо достаётся
/// более высокому уровню, а второй сигнал уходит в угловой бейдж — иначе
/// пришлось бы рисовать третий стиль кольца.
enum PlinkIdentityLevel: Int, Comparable {
    /// Обычный пользователь. Кольца нет вообще — отсутствие и есть сигнал.
    case regular = 0
    /// Администратор или хост комнаты.
    case admin = 1
    /// Подписчик Plink+.
    case plus = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(isAdmin: Bool, isPremium: Bool) {
        // Plink+ выигрывает слот кольца: подписку человек купил, и она
        // должна читаться. Админство при совпадении уходит в бейдж.
        if isPremium { self = .plus }
        else if isAdmin { self = .admin }
        else { self = .regular }
    }
}

// MARK: - Геометрия

/// Пропорции кольца. Все размеры считаются от диаметра аватарки, поэтому
/// кольцо выглядит одинаково и на 28 pt в чате, и на 96 pt в профиле.
private enum RingMetrics {
    /// 4.5 % диаметра: тоньше — на маленьких размерах градиент не читается,
    /// толще — кольцо начинает выглядеть как рамка, а не как свет.
    static func stroke(for diameter: CGFloat) -> CGFloat {
        max(1.6, diameter * 0.045)
    }

    /// «Канавка» цвета фона между кольцом и фотографией. Без неё кольцо
    /// касается снимка и читается как дешёвая цветная обводка.
    static func moat(for diameter: CGFloat) -> CGFloat {
        max(1.5, diameter * 0.028)
    }

    /// Угловой бейдж — 26 % диаметра: заметен, но не спорит с лицом.
    static func badge(for diameter: CGFloat) -> CGFloat {
        max(14, diameter * 0.26)
    }
}

// MARK: - Кольцо

/// Кольцо роли вокруг аватарки.
///
/// Админ получает ровный цвет, Plink+ — угловой градиент. Это осознанное
/// различие: роль в иерархии и купленный статус должны отличаться на
/// глаз, а не только оттенком.
struct PlinkIdentityRing: ViewModifier {
    let level: PlinkIdentityLevel
    let diameter: CGFloat
    /// Цвет фона под аватаркой — им заполняется канавка.
    var background: Color = V4.canvas

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        let stroke = RingMetrics.stroke(for: diameter)
        let moat = RingMetrics.moat(for: diameter)

        switch level {
        case .regular:
            // Обычный пользователь: только волосяная линия, чтобы аватарка
            // не растворялась на тёмном фоне.
            content
                .overlay(Circle().strokeBorder(V4.line, lineWidth: 0.75))

        case .admin:
            content
                .padding(moat)
                .background(background, in: Circle())
                .overlay(
                    Circle().strokeBorder(Self.adminColor, lineWidth: stroke)
                )
                .shadow(color: Self.adminColor.opacity(0.28), radius: stroke * 2, y: 0)

        case .plus:
            content
                .padding(moat)
                .background(background, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Self.plusGradient, lineWidth: stroke)
                        .rotationEffect(.degrees(rotation))
                )
                .shadow(color: Self.plusGlow.opacity(0.30), radius: stroke * 2.2, y: 0)
                .onAppear {
                    guard !reduceMotion, rotation == 0 else { return }
                    withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
        }
    }

    // Единственное место, где заданы цвета уровней.
    static let adminColor = Color(hex: 0xFF3B5C)
    static let plusGlow = Color(hex: 0xFFC24B)

    /// Угловой, а не линейный: линейный градиент на круге даёт видимый
    /// шов там, где сходятся первый и последний цвет.
    static let plusGradient = AngularGradient(
        colors: [
            Color(hex: 0xFFD98A),
            Color(hex: 0xFFC24B),
            Color(hex: 0xE89A2B),
            Color(hex: 0xFFD98A)
        ],
        center: .center
    )
}

extension View {
    /// Кольцо роли вокруг аватарки заданного диаметра.
    func plinkIdentityRing(
        _ level: PlinkIdentityLevel,
        diameter: CGFloat,
        background: Color = V4.canvas
    ) -> some View {
        modifier(PlinkIdentityRing(level: level, diameter: diameter, background: background))
    }

    /// Удобная форма для мест, где под рукой только два флага.
    func plinkIdentityRing(
        isAdmin: Bool,
        isPremium: Bool,
        diameter: CGFloat,
        background: Color = V4.canvas
    ) -> some View {
        plinkIdentityRing(
            PlinkIdentityLevel(isAdmin: isAdmin, isPremium: isPremium),
            diameter: diameter,
            background: background
        )
    }
}

// MARK: - Бейдж

/// Тип углового бейджа поверх аватарки.
enum PlinkBadgeKind {
    case admin
    case plus
    case verified

    var symbol: String {
        switch self {
        case .admin:    return "shield.fill"
        case .plus:     return "star.fill"
        case .verified: return "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .admin:    return PlinkIdentityRing.adminColor
        case .plus:     return PlinkIdentityRing.plusGlow
        case .verified: return Color(hex: 0x33D17A)
        }
    }
}

/// Угловой бейдж статуса.
///
/// Что отличает дорогой бейдж от дешёвого: заливка не плоская, а с
/// вертикальным светом сверху; есть канавка цвета фона, поэтому бейдж не
/// сливается с кольцом под ним; глиф жирный и простой — тонкие детали на
/// 14 pt превращаются в грязь. Раньше бейджи были капсулой с заливкой
/// `.opacity(0.15)` и 0.5-pt обводкой, из-за чего выглядели как заглушка.
struct PlinkIdentityBadge: View {
    let kind: PlinkBadgeKind
    let diameter: CGFloat
    var background: Color = V4.canvas

    var body: some View {
        let size = RingMetrics.badge(for: diameter)
        let moat = max(1.5, size * 0.11)

        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.46, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    Circle().fill(kind.tint)
                    // Верхний блик — тот же приём, что в кнопках PlinkGlass.
                    Circle().fill(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .blendMode(.overlay)
                }
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
            .padding(moat)
            .background(background, in: Circle())
            .shadow(color: kind.tint.opacity(0.42), radius: size * 0.22, y: size * 0.06)
    }
}

// MARK: - Текстовый чип

/// Текстовый бейдж уровня («АДМИН», «PLINK+») для строк списков и шапок,
/// где угловой бейдж на аватарке слишком мелкий.
///
/// Собран по тем же правилам, что `PlinkIdentityBadge`: насыщенная заливка
/// вместо `opacity(0.15)`, верхний блик, читаемая обводка. Прежний вариант
/// был капсулой с 15-процентной заливкой, 0.5-pt контуром и цветным текстом,
/// которому для читаемости пришлось подкладывать четыре тени по сторонам —
/// признак того, что контраста не хватало изначально.
struct PlinkIdentityChip: View {
    let kind: PlinkBadgeKind
    var title: String? = nil
    /// Только глиф, без подписи — для плотных строк.
    var compact: Bool = false

    private var text: String {
        if let title { return title }
        switch kind {
        case .admin:    return "АДМИН"
        case .plus:     return "PLINK+"
        case .verified: return "ПРОВЕРЕН"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: compact ? 9 : 9.5, weight: .heavy))
            if !compact {
                Text(text)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .tracking(0.6)
            }
        }
        // Белый текст на насыщенной подложке: контраст выше, чем у цветного
        // текста на прозрачной, и обводка тенями больше не нужна.
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 3.5)
        .background {
            ZStack {
                Capsule(style: .continuous).fill(kind.tint.opacity(0.92))
                Capsule(style: .continuous).fill(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .blendMode(.overlay)
            }
        }
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.8))
        .shadow(color: kind.tint.opacity(0.34), radius: 5, y: 2)
    }
}

// MARK: - Точка присутствия

/// Онлайн-индикатор. Своя канавка позволяет ставить точку поверх любого
/// кольца, не согласовывая цвета.
struct PlinkPresenceDot: View {
    var isOnline: Bool = true
    let diameter: CGFloat
    var background: Color = V4.canvas

    var body: some View {
        let size = max(9, diameter * 0.23)
        Circle()
            .fill(isOnline ? Color(hex: 0x33D17A) : V4.muted)
            .frame(width: size, height: size)
            .padding(max(1.5, size * 0.18))
            .background(background, in: Circle())
    }
}

// MARK: - Готовая аватарка

/// Аватарка с кольцом, бейджем и точкой — собранные по правилу «не более
/// двух сигналов». Используйте её, чтобы не размножать композиции заново.
struct PlinkIdentityAvatar<Content: View>: View {
    let diameter: CGFloat
    var isAdmin: Bool = false
    var isPremium: Bool = false
    var isOnline: Bool? = nil
    var background: Color = V4.canvas
    @ViewBuilder var content: Content

    private var level: PlinkIdentityLevel {
        PlinkIdentityLevel(isAdmin: isAdmin, isPremium: isPremium)
    }

    /// Бейдж нужен только там, где кольцо не смогло передать всё: у
    /// админа с подпиской кольцо золотое, поэтому админство идёт бейджем.
    private var badge: PlinkBadgeKind? {
        if isPremium && isAdmin { return .admin }
        if isPremium { return .plus }
        return nil
    }

    var body: some View {
        content
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .plinkIdentityRing(level, diameter: diameter, background: background)
            .overlay(alignment: .bottomTrailing) {
                if let badge, diameter >= 44 {
                    PlinkIdentityBadge(kind: badge, diameter: diameter, background: background)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let isOnline {
                    // Точка сидит на самой кромке кольца, а не поверх него:
                    // при смещении наружу она срезала дугу и кольцо читалось
                    // разорванным. Сдвиг по диагонали на ~7 % диаметра ставит
                    // её в угол, свободный от бейджа.
                    PlinkPresenceDot(isOnline: isOnline, diameter: diameter, background: background)
                        .offset(x: -diameter * 0.02, y: diameter * 0.07)
                }
            }
    }
}

#if DEBUG
#Preview("Уровни") {
    HStack(spacing: 22) {
        ForEach([
            (false, false, "Обычный"),
            (true, false, "Админ"),
            (false, true, "Plink+"),
            (true, true, "Админ +")
        ], id: \.2) { admin, plus, label in
            VStack(spacing: 10) {
                PlinkIdentityAvatar(
                    diameter: 64,
                    isAdmin: admin,
                    isPremium: plus,
                    isOnline: true
                ) {
                    Circle().fill(V4.raised)
                        .overlay(Text("А").font(.system(size: 24, weight: .bold)).foregroundStyle(V4.ink))
                }
                Text(label).font(.system(size: 11)).foregroundStyle(V4.muted)
            }
        }
    }
    .padding(34)
    .background(V4.canvas)
}
#endif

// MARK: - Печать у имени

/// Seal next to the display name — the Telegram "verified" model. A
/// scalloped seal in the level colour with a bold glyph: the administrator
/// keeps the shield, Plink+ the star. Replaces the old red name and the
/// solid "АДМИН"/"PLINK+" capsules, which read as debug labels rather than
/// status. The same view on the owner's face and on a friend's face.
struct PlinkIdentitySeal: View {
    let kind: PlinkBadgeKind
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(kind.tint)
                // Top light, the PlinkGlass button trick — flat fill reads as a sticker.
                .overlay {
                    LinearGradient(
                        colors: [.white.opacity(0.42), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .blendMode(.overlay)
                    .mask(
                        Image(systemName: "seal.fill")
                            .font(.system(size: size, weight: .regular))
                    )
                }
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.44, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: kind.tint.opacity(0.45), radius: size * 0.22, y: 1)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch kind {
        case .admin: return LocalizationManager.shared.string(.prAdminSeal)
        case .plus: return LocalizationManager.shared.string(.prPlusSeal)
        case .verified: return "Verified"
        }
    }
}
