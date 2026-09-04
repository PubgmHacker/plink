// Plink/Features/WatchRoom/PlayerStage.swift
//
// Neutral player stage. NO decoration: no glow, no border, no glass,
// no theme stroke, no theme shadow, no theme corner radius.
// Background: plain black. Provider owns controls.

import SwiftUI

struct PlayerStage: View {
    @Bindable var model: WatchRoomModel
    @Binding var ui: WatchRoomUIState
    let variant: WatchRoomLayoutState.Variant
    /// Отступы для хрома. Сам кадр всегда во весь экран (ландшафт вешает на
    /// него `.ignoresSafeArea()`), но полоса перемотки, кнопки и заголовок
    /// обязаны держаться в стороне от выреза и от ящика чата справа. По
    /// умолчанию нули — портрет и планшет остаются как были.
    var chromeInsets: EdgeInsets = EdgeInsets()

    // Short buffering spikes must not be shown. Any seek — a hard drift
    // correction, a ±10s skip, the host scrubbing — sets isBuffering for
    // 200-800ms, so a spinner bound directly to it would flash mid-scene.
    // The chip appears only once buffering outlasts the threshold, and
    // disappears immediately.
    @State private var showBufferingChip = false
    private static let bufferingChipDelayNs: UInt64 = 500_000_000
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Поверхность плеера уже существует — встроенная страница или AVPlayer.
    private var hasSurface: Bool {
        model.coordinator.embeddedView != nil || model.coordinator.nativePlayer != nil
    }

    /// Кадр ещё ничего не показал: либо готовимся, либо стоим на нуле и не
    /// играем. После первой же секунды заставка уходит навсегда — на паузе
    /// посреди фильма видно сам кадр, накрывать его постером неправильно.
    private var showsArtwork: Bool {
        guard model.mediaError == nil else { return false }
        guard model.mediaPoster != nil || model.mediaTitle != nil else { return false }
        if model.coordinator.isPreparing { return true }
        return model.coordinator.position <= 0.05 && !model.coordinator.isPlaying
    }

    var body: some View {
        ZStack {
            // Plain black background, nothing else
            Color.black

            // Player surface — never decorated
            // P0-фикс аудита: в плеер идёт только mediaError — прочие lastError
            // показываются тостами и не должны закрывать видео чёрным экраном.
            PlayerSurfaceView(
                coordinator: model.coordinator,
                roomError: model.mediaError,
                expectMedia: model.mediaSource != nil || model.mediaError == nil,
                onSurfaceTap: {
                    // The room screen schedules auto-hide from controlsVisible.
                    PlinkChromeTrace.log("surfaceTap")
                    guard !ui.chatPresented else { return }
                    withAnimation(.plinkControls) { ui.toggleControlsDebounced() }
                },
                shouldHandleSurfaceTap: { point, size in
                    // Хром скрыт — тапом его поднимают, и весь кадр наш.
                    guard ui.controlsVisible else { return true }
                    // Хром виден: верхняя и нижняя полосы заняты кнопками,
                    // и касание в них принадлежит им, а не переключению
                    // панели. Высоты берём у самой панели, чтобы полосы не
                    // разъезжались с её вёрсткой.
                    let top = PlinkPlayerControls.topBand(for: variant) + chromeInsets.top
                    let bottom = PlinkPlayerControls.bottomBand(for: variant)
                        + chromeInsets.bottom
                    return point.y > top && point.y < size.height - bottom
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Тап по кадру ПОДНИМАЕТ хром — и только это. Слой существует
            // ровно пока панели нет на экране, поэтому спорить с её кнопками
            // ему нечем: как только хром поднят, слоя в дереве уже нет.
            //
            // Так пришлось сделать дважды. Сначала жест сидел на корневом
            // стеке комнаты — там он был ПРЕДКОМ всех кнопок хрома и забирал
            // их касания себе (тап по «Полный экран» гасил панель вместо
            // поворота экрана). Перенос внутрь сцены не помог: SwiftUI отдаёт
            // тап заполняющему слою даже когда кнопка нарисована ВЫШЕ его в
            // том же ZStack — лог ловил stageTapLayer там, где должен был
            // сработать muteButtonAction. Лечит не порядок отрисовки, а
            // условие: нет хрома — есть слой, есть хром — слоя нет.
            //
            // Обратный ход (спрятать панель тапом) живёт в зонах перемотки
            // PlinkPlayerControls: они занимают кадр между полосами хрома и
            // по одиночному тапу гасят панель, не мешая кнопкам.
            //
            // Родная поверхность AVPlayer касаний не принимает вовсе (см.
            // PlayerViewControllerRepresentable), встроенная страница отдаёт
            // их через onSurfaceTap — так что слой нужен обоим путям.
            if !ui.controlsVisible {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        PlinkChromeTrace.log("stageTapLayer")
                        guard !ui.chatPresented else { return }
                        withAnimation(.plinkControls) { ui.toggleControlsDebounced() }
                    }
            }

            // Заставка кадра. До первого показанного пикселя AVPlayer держит
            // ровно чёрный прямоугольник — именно его человек и видел вместо
            // фильма. Пока видео не пошло, кадр занимает постер: размытая
            // заливка под чёрные поля и само превью по центру.
            if showsArtwork {
                PlayerArtworkLayer(
                    poster: model.mediaPoster,
                    accent: PlinkRoomAccent.current
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Danmaku layer (above video, below chrome)
            DanmakuCanvasLayer(
                placements: model.danmakuPlacements,
                laneCount: model.danmakuLaneCount,
                opacity: model.danmakuOpacity
            )
            .padding(.horizontal, 8)
            .padding(.top, 60)
            .padding(.bottom, 80)

            // Reactions belong to the video surface, not to the whole room.
            // The previous sibling lived in WatchRoomScreen's root ZStack, so
            // an emoji could float over the chat, composer and even service
            // notices. Keeping it inside the clipped player stage preserves
            // the live-room effect while making the scope unambiguous.
            WatchReactionLayer(events: model.reactions, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .zIndex(2)

            // Loading overlay only when we still have no player surface.
            // Once WKWebView is attached, never cover it with a full-screen spinner
            // (that was the "eternal loading" symptom: 1 in room + black spinner).
            if model.coordinator.isPreparing && !hasSurface {
                PlayerLoadingView()
                    .transition(.opacity)
            }
            // Soft buffering chip — only mid-playback, never blocks hit testing
            // and never shown for the whole prepare period.
            // P2-фикс аудита: раньше здесь стояло ещё isPlaying == false, из-за
            // чего оверлей не появлялся при ребуфере на ходу (YouTube state 3
            // ставит isBuffering, но isPlaying не сбрасывает) — то есть именно
            // в том случае, для которого чип и сделан.
            if showBufferingChip
                && hasSurface
                && model.coordinator.isPreparing == false
            {
                BufferingOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Top chrome only (functional, not decorative)
            if ui.controlsVisible {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.opacity)

                PlayerTopChrome(
                    model: model,
                    variant: variant,
                    // Панель темы презентует WatchRoomScreen — здесь только
                    // запрос на открытие (хром гаснет по таймеру автоскрытия).
                    onOpenAppearance: { ui.appearancePanelPresented = true },
                    mediaTitle: model.mediaTitle,
                    chromeInsets: chromeInsets
                )
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Своя полноценная панель управления вместо родной панели
                // YouTube — перемотка с буфером, время, ±10 с, скорость,
                // качество, звук и полный экран. Раньше здесь была только
                // кнопка play для хоста, а всё остальное рисовал YouTube.
                //
                // Панель одна на всех провайдеров. Раньше её получал только
                // встроенный путь — «у родного AVPlayer свои системные
                // контролы», — но системную панель никто не включал, и
                // на mp4/HLS оставалась одна кнопка play посреди черноты:
                // ни полосы, ни времени, ни перемотки. Теперь родная панель
                // AVKit выключена намеренно (см. makePlayerViewController),
                // а управление всегда своё.
                if hasSurface {
                    PlinkPlayerControls(model: model, ui: $ui, variant: variant,
                                        chromeInsets: chromeInsets)
                        .transition(.opacity)
                } else if model.isHost {
                    PlayerCenterControl(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(chromeInsets)
                        .transition(.opacity)
                }
            }
        }
        .clipped()
        // Дебаунс спиннера буферизации: при isBuffering ждём порог и только
        // потом показываем; на сброс флага задача перезапускается и гасит чип.
        .task(id: model.coordinator.isBuffering) {
            guard model.coordinator.isBuffering else {
                showBufferingChip = false
                return
            }
            try? await Task.sleep(nanoseconds: Self.bufferingChipDelayNs)
            guard !Task.isCancelled else { return }
            showBufferingChip = true
        }
        .accessibilityElement(children: .contain)
        // FORBIDDEN: PlinkLivingBackground, glassCard, neonGlow, theme stroke,
        // theme shadow, theme corner radius. None of these appear here.
    }
}

// MARK: - Заставка кадра

/// Постер вместо чёрного прямоугольника, пока видео не показало первый кадр.
///
/// Три слоя, как у витрин кинотеатров: размытая заливка во всю площадь (чтобы
/// у 4:3 или вертикального ролика не оставалось мёртвых чёрных полей), само
/// превью по центру без обрезки и затемнение снизу под подпись.
private struct PlayerArtworkLayer: View {
    let poster: String?
    let accent: Color

    private var posterURL: URL? {
        guard let poster, !poster.isEmpty else { return nil }
        return URL(string: poster)
    }

    var body: some View {
        ZStack {
            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 34, opaque: true)
                                .overlay(Color.black.opacity(0.45))
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            // Затемнение снизу — под нижнюю панель, чтобы белые цифры
            // времени и полоса перемотки читались поверх светлого кадра.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipped()
    }

    /// Превью нет или оно не загрузилось — рисуем спокойный градиент акцента
    /// комнаты, а не ещё один чёрный прямоугольник.
    private var placeholder: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.30),
                Color.black.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        // Иконки по центру нет намеренно: ровно там стоит кнопка play, и
        // «плёнка» проступала сквозь неё серым пятном.
    }
}
