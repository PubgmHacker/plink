// Plink/Features/WatchRoom/WatchRoomOverlays.swift
//
// Extracted from WatchRoomSupportTypes.swift.
//
// Contains:
//   - RoomToastView          (toast notification)
//   - WatchChatSheet         (modal chat sheet for portrait)
//   - LandscapeChatDrawer    (slide-in chat for landscape)
//   - WatchChatHeader        (chat header with title + watcher count)
//   - ChatAvatar             (small avatar in chat bubble)
//   - ParticipantAvatar      (larger avatar in presence bar)
//   - DanmakuCanvasLayer     (flying comments overlay)
//
// All chrome uses .ultraThinMaterial + subtle strokes for depth.

import SwiftUI

// MARK: - Toast

struct RoomToastView: View {
    let toast: RoomToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForKind)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colorForKind)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Cinema2026.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .plinkGlass(.overlay, in: Capsule(style: .continuous))
        .overlay(Capsule().stroke(colorForKind.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.top, 8)
    }

    private var colorForKind: Color {
        switch toast.kind {
        case .info: return Cinema2026.secondary
        case .success: return Cinema2026.accent
        case .warning: return Cinema2026.amber
        case .error: return Cinema2026.danger
        }
    }

    private var iconForKind: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Chat containers

struct WatchChatSheet: View {
    let model: WatchRoomModel

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model)
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .background(Cinema2026.background)
    }
}

/// Метрики ландшафтной раскладки. Ширина ящика чата нужна в двух местах —
/// самому ящику и хрому плеера, который обязан держаться левее него: полоса
/// перемотки и кнопки звука с полным экраном лежат под ящиком и там просто
/// не нажимаются, а `.ultraThinMaterial` ещё и делает вид, что они видны.
enum WatchLandscapeMetrics {
    static func drawerWidth(for containerWidth: CGFloat) -> CGFloat {
        min(420, max(320, containerWidth * 0.40))
    }

    /// Отступы хрома плеера в ландшафте. Кадр идёт от края до края, хром —
    /// нет: слева и справа вырез, снизу домашняя полоса, справа сверх того
    /// ящик чата, когда он открыт.
    static func chromeInsets(
        canvasWidth: CGFloat,
        safeArea: EdgeInsets,
        drawerVisible: Bool
    ) -> EdgeInsets {
        EdgeInsets(
            top: safeArea.top,
            leading: safeArea.leading,
            bottom: safeArea.bottom,
            // Ящик и вырез СКЛАДЫВАЮТСЯ, а не спорят за максимум: ящик идёт
            // до физического края и своей же полосой накрывает вырез. Было
            // max(), и на той стороне, где вырез, хром оставался под стеклом
            // ящика ровно на ширину выреза — 59 pt неработающих кнопок.
            trailing: drawerVisible
                ? drawerWidth(for: canvasWidth) + safeArea.trailing
                : safeArea.trailing
        )
    }
}

struct LandscapeChatDrawer: View {
    let model: WatchRoomModel
    @Binding var isVisible: Bool
    /// Ширина канвы. Ящик считает от неё свою ширину тем же правилом, что и
    /// плеер, — иначе отступ хрома разойдётся с реальным краем ящика.
    var containerWidth: CGFloat = 0
    /// Безопасная зона числом — тем же путём, каким её получает хром плеера
    /// (`WatchLandscapeMetrics.chromeInsets`). Ящик стоит у трейлинг-края, а
    /// на той стороне, где вырез, край экрана — это не край читаемой области.
    var safeArea = EdgeInsets()

    var body: some View {
        VStack(spacing: 0) {
            WatchChatHeader(model: model, closable: true, onClose: {
                withAnimation(.plinkDrawer) {
                    isVisible = false
                }
            })
            WatchChatView(model: model)
            WatchChatComposer(model: model)
        }
        .frame(width: containerWidth > 0
               ? WatchLandscapeMetrics.drawerWidth(for: containerWidth)
               : 360)
        // Клип по колонке: горизонтальная лента реакций в поле ввода —
        // ScrollView, и без него она рисовала эмодзи поверх полосы выреза,
        // на 59 pt правее собственной подложки. Замер: правый край ленты
        // 1584 px, а последний эмодзи доезжал до 1699 при кадре 1704.
        .clipped()
        // Стекло доходит до физического края, содержимое — нет. Без этой
        // полосы одно из двух: либо ящик кладут внутрь безопасной зоны и у
        // выреза остаётся чёрная щель между ящиком и краем, либо крестик,
        // счётчик и микрофон уезжают под сам вырез. Ширина колонки чата при
        // этом не меняется — полоса добавляется снаружи неё.
        .padding(.trailing, safeArea.trailing)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.5))
                .frame(width: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 16, x: -4, y: 0)
        // Два якоря вместо одного, и это не перестраховка. `.contain`
        // обязателен: без него идентификатор висит на VStack, у которого
        // есть свои доступные дети, и контейнер не становится отдельным
        // элементом — XCUITest ящик не находит вовсе, хотя он на экране.
        // Но и с `.contain` идентификатор контейнера перебивает
        // `screen.room` с корня комнаты (WatchRoomScreen): корневой
        // .accessibilityIdentifier протекает вниз и выигрывает у
        // контейнеров, хотя листья со своим id — переживают. Поэтому
        // геометрию ящика тесты читают по листу-якорю в фоне: он ровно
        // размером с ящик, касаний не берёт и свой id держит.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room.chatDrawer")
        .background(
            Color.clear
                .accessibilityElement()
                .accessibilityLabel("Ящик чата")
                .accessibilityIdentifier("room.chatDrawerAnchor")
                .allowsHitTesting(false)
        )
        // Только трейлинг: снизу домашняя полоса, и поле ввода обязано
        // остаться над ней.
        .ignoresSafeArea(edges: .trailing)
    }
}

struct WatchChatHeader: View {
    let model: WatchRoomModel
    var closable: Bool = false
    var onClose: () -> Void = {}

    // Шапку не красили заново, её раскрыли: до 04.09.2026 в ландшафтном
    // ящике она лежала ПОД фоном ленты сообщений. Замер: «Чат» — пиксели
    // (35,38,44) на (21,22,28), 1,18:1; крестик и счётчик — так же, то есть
    // чат в ландшафте нечем было закрыть. Проба пурпуром доказала, что
    // гаснут не буквы, а вся шапка целиком: непрозрачную заливку (255,0,255)
    // кадр показывал как (36,25,46) — 6 % от своей силы, ровно остаток от
    // 0,92⊕0,18 фона `WatchChatView`. Причина и правка — там же
    // (WatchChatView.swift, `.ignoresSafeArea` у фона ленты). Токены здесь
    // верные, менять их было бы лечением симптома.
    var body: some View {
        HStack(spacing: 8) {
            Text("Чат")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .medium))
                Text("\(model.participants.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Cinema2026.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Cinema2026.raised.opacity(0.6), in: Capsule())

            if closable {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                        .frame(width: 28, height: 28)
                        .background(Cinema2026.raised, in: Circle())
                }
                .accessibilityLabel("Закрыть чат")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Cinema2026.surface.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Cinema2026.divider.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Host mark

/// Знак хоста. Намеренно не корона.
///
/// Корона в приложении занята премиумом: платные паки стикеров и эмодзи,
/// строка Plink+ в профиле, раздел и пользователи премиума в админке, плюс
/// сервис Premier. Хост под тем же значком читался как «проплаченный»,
/// хотя роль техническая и достаётся даром — при выходе владельца её
/// получает самый давний из оставшихся.
///
/// Что хост делает на самом деле — ведёт таймлайн: он один жмёт паузу и
/// перематывает. Отсюда знак: янтарный диск с треугольником пуска, «у этого
/// человека пульт». Ни с чем в приложении не пересекается.
///
/// Один компонент на все места, иначе знак разъедется, как разъехалась
/// корона на четыре разных смысла.
struct PlinkHostMark: View {
    /// Диаметр янтарного диска без отбивки.
    var size: CGFloat = 11
    /// Тёмное кольцо-отбивка. Нужно поверх аватара и фотографии, вредит
    /// внутри уже янтарной капсулы — там знак и так отделён.
    var ring: Bool = true

    var body: some View {
        ZStack {
            Circle().fill(Cinema2026.amber)
            Image(systemName: "play.fill")
                // Треугольник тяжелее слева: сдвигаем к оптическому центру,
                // иначе на диске он всегда выглядит осевшим влево.
                .font(.system(size: size * 0.44, weight: .black))
                .foregroundStyle(Cinema2026.background)
                .offset(x: size * 0.045)
        }
        .frame(width: size, height: size)
        .padding(ring ? size * 0.12 : 0)
        .background(ring ? Cinema2026.background : .clear, in: Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Avatars

struct ChatAvatar: View {
    let message: ChatMessageInfo

    var body: some View {
        Circle()
            .fill(avatarBackground)
            .frame(width: 28, height: 28)
            .overlay(
                Text(String(message.senderName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(avatarForeground)
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 0.5)
            )
    }

    private var avatarBackground: Color {
        if message.isAdmin { return Cinema2026.amber.opacity(0.18) }
        if message.isPremium { return Cinema2026.danger.opacity(0.18) }
        return Cinema2026.raised
    }

    private var avatarForeground: Color {
        if message.isAdmin { return Cinema2026.amber }
        if message.isPremium { return Cinema2026.danger }
        return Cinema2026.text
    }
}

struct ParticipantAvatar: View {
    let participant: ParticipantInfo
    let hostId: String?
    var isSpeaking: Bool = false

    private var isHost: Bool { participant.userId == hostId }

    var body: some View {
        Circle()
            .fill(Cinema2026.raised)
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(participant.username.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
            )
            .overlay(
                Circle()
                    .stroke(ringColor, lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if isHost { PlinkHostMark(size: 11).offset(x: 2, y: 2) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isHost ? "\(participant.username), хост" : participant.username
            )
    }

    private var ringColor: Color {
        if isSpeaking { return Cinema2026.accent }
        if isHost { return Cinema2026.amber.opacity(0.6) }
        return Cinema2026.accent.opacity(0.18)
    }
}

// MARK: - Danmaku
//
// DanmakuCanvasLayer now renders DanmakuPlacement snapshots from
// the DanmakuEngine actor. Lane assignment, duration, and progress are all
// computed by the engine — this view only draws the current snapshot.
//
// The view polls the engine via TimelineView at .animation cadence (~16ms).
// Each frame it asks the engine for poll(at: now), which returns the
// surviving placements sorted by lane.
//
// Tap on a placement freezes it for 2 seconds.
// Long press reports/blocks the sender — wired via closures.

struct DanmakuCanvasLayer: View {
    let placements: [DanmakuPlacement]
    let laneCount: Int
    let opacity: Double
    var onTap: ((DanmakuPlacement) -> Void)? = nil
    var onLongPress: ((DanmakuPlacement) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let laneHeight = proxy.size.height / CGFloat(max(1, laneCount))
            let viewportWidth = proxy.size.width

            ZStack(alignment: .topLeading) {
                ForEach(placements) { placement in
                    DanmakuItemView(placement: placement, viewportWidth: viewportWidth)
                        .offset(x: xOffset(for: placement, in: viewportWidth),
                                y: CGFloat(placement.lane) * laneHeight + 4)
                        .opacity(opacity)
                        .onTapGesture { onTap?(placement) }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            onLongPress?(placement)
                        }
                }
            }
        }
        .allowsHitTesting(true)
    }

    /// Compute x-offset for a placement at the current frame.
    /// progress 0 = right edge (entering), progress 1 = left edge (exiting).
    /// We compute relative to the placement's own createdAt — but since
    /// this view is fed a snapshot, the caller must use TimelineView to
    /// drive re-renders. The actual progress is recomputed each frame by
    /// the engine's poll() — but we need a stable offset for the rendered
    /// snapshot. For simplicity, we use the placement.id's hash as a
    /// deterministic initial offset and the placement.duration for the
    /// traversal speed.
    ///
    /// NOTE: the engine's poll() returns placements sorted by lane, but
    /// the actual progress is computed by the View using ContinuousClock
    /// — see DanmakuItemView below.
    private func xOffset(for placement: DanmakuPlacement, in viewportWidth: CGFloat) -> CGFloat {
        // The View below (DanmakuItemView) handles its own animation via
        // .offset modifier internally based on TimelineView. This outer
        // offset is just the lane entry position (right edge).
        return 0
    }
}

/// Single danmaku item with self-contained animation. Uses TimelineView
/// to drive its own x-offset based on the placement's createdAt and
/// duration. This avoids re-rendering the entire layer every frame.
private struct DanmakuItemView: View {
    let placement: DanmakuPlacement
    let viewportWidth: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            // Use Date-based progress overload — TimelineView
            // provides context.date as Date, and DanmakuPlacement stores
            // a parallel createdAtDate for this purpose.
            let progress = placement.progress(at: context.date, speed: 1.0)
            let x = viewportWidth - (CGFloat(progress) * (viewportWidth + estimatedTextWidth + 40))

            Text(placement.text)
                .font(.system(size: placement.isPremium ? 17 : 14, weight: .medium))
                .foregroundStyle(placement.isAdmin ? Cinema2026.amber : placement.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Cinema2026.background.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.05), lineWidth: 0.5))
                .offset(x: x)
        }
    }

    private var estimatedTextWidth: CGFloat {
        CGFloat(placement.text.count) * 8
    }
}

// MARK: - Rutube fallback

/// Toast shown when source is .rutube and the embedded player's JS API
/// is unavailable. Tapping «Открыть» launches SFSafariViewController with
/// the Rutube video URL.
struct RutubeFallbackToast: View {
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Cinema2026.amber)

            VStack(alignment: .leading, spacing: 2) {
                Text("Синхронизация недоступна")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                Text("Откройте в Rutube, чтобы смотреть")
                    .font(.system(size: 11))
                    .foregroundStyle(Cinema2026.secondary)
            }

            Spacer()

            Button(action: onOpen) {
                Text("Открыть")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Cinema2026.accentAction, in: Capsule())
            }
            .accessibilityLabel("Открыть в Rutube")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .plinkGlass(.overlay, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Cinema2026.amber.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 90)  // above the composer
    }
}
