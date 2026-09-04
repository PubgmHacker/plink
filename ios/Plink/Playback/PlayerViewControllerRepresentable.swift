// Plink/Playback/PlayerViewControllerRepresentable.swift
// SwiftUI bridge
//
// Supports both playback surfaces:
//   - Native HLS/MP4 → AVPlayerViewController (PiP + AirPlay)
//   - Embedded YouTube → WKWebView from EmbeddedPlaybackController
//
// The underlying AVPlayer instance is owned by PlaybackCoordinator —
// This view does NOT create its own player ( DoD: 'Background/foreground,
// rotation и fullscreen не создают второй player').

import SwiftUI
import AVKit

public struct PlayerSurfaceView: View {
    public let coordinator: PlaybackCoordinator
    /// Optional room-level error (e.g. mediaSource missing) — coordinator may still be idle.
    public var roomError: String? = nil
    /// When true, show loading instead of "Нет видео" during connect bootstrap.
    public var expectMedia: Bool = true
    /// Called for a single tap on an embedded web surface. WKWebView consumes
    /// touches, so a SwiftUI tap gesture above it never fires reliably and the
    /// room chrome (leave button, transport) could become unreachable.
    ///
    /// Родному AVPlayer этот путь не нужен и вреден: его поверхность касаний
    /// не берёт вовсе (см. `PlayerViewControllerRepresentable`), тап по кадру
    /// доходит до SwiftUI сам.
    public var onSurfaceTap: (() -> Void)? = nil
    /// Тап пришёлся в кадр, а не в хром поверх него. Точка — в координатах
    /// поверхности, размер — её собственный. Нужен ровно встроенному пути:
    /// WKWebView забирает касание раньше SwiftUI, поэтому отсечь полосы,
    /// занятые кнопками, может только он сам.
    public var shouldHandleSurfaceTap: ((CGPoint, CGSize) -> Bool)? = nil

    public init(
        coordinator: PlaybackCoordinator,
        roomError: String? = nil,
        expectMedia: Bool = true,
        onSurfaceTap: (() -> Void)? = nil,
        shouldHandleSurfaceTap: ((CGPoint, CGSize) -> Bool)? = nil
    ) {
        self.coordinator = coordinator
        self.roomError = roomError
        self.expectMedia = expectMedia
        self.onSurfaceTap = onSurfaceTap
        self.shouldHandleSurfaceTap = shouldHandleSurfaceTap
    }

    public var body: some View {
        // Observe surfaceEpoch so WKWebView appears as soon as prepare attaches it
        let _ = coordinator.surfaceEpoch
        let _ = coordinator.isPreparing
        let _ = coordinator.lastError
        let error = activeError

        ZStack {
            if let vc = coordinator.makePlayerViewController() {
                // Тап по кадру поднимает и прячет хром — этим занимается
                // жест корневого стека комнаты. Поверхность его не перехватит:
                // касания она не принимает.
                PlayerViewControllerRepresentable(controller: vc)
                    .overlay {
                        if let error {
                            mediaErrorView(error)
                        }
                    }
            } else if let embedded = coordinator.embeddedView {
                // Stable identity — do NOT use .id(surfaceEpoch) or SwiftUI will
                // tear down / re-create the UIViewRepresentable and kill YT load.
                EmbeddedViewRepresentable(view: embedded,
                                          onTap: onSurfaceTap,
                                          shouldHandleTap: shouldHandleSurfaceTap)
                    .overlay {
                        if let error {
                            mediaErrorView(error)
                        }
                    }
            } else if let error {
                // Media prepare failed — show error (chat still works).
                mediaErrorView(error)
            } else if coordinator.isPreparing || (expectMedia && coordinator.currentSource == nil && coordinator.currentController == nil) {
                // Avoid flash "Нет видео" while connect() is still resolving YouTube
                Color.black
                    .overlay(
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Загрузка видео…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    )
            } else {
                Color.black
                    .overlay(
                        Text("Нет видео")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    )
            }
        }
        .background(Color.black)
    }

    private var activeError: String? {
        coordinator.lastError
            ?? (coordinator.currentController as? EmbeddedPlaybackController)?.lastError
            ?? (coordinator.currentController as? RutubePlaybackController)?.lastError
            ?? (coordinator.currentController as? VKPlaybackController)?.lastError
            ?? (coordinator.currentController as? EmbedPlaybackController)?.lastError
            ?? roomError
    }

    private func mediaErrorView(_ error: String) -> some View {
        Color.black
            .overlay(
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                    Text("Не удалось загрузить видео")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Чат и участники работают")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            )
    }
}

public struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    public let controller: AVPlayerViewController

    public init(controller: AVPlayerViewController) {
        self.controller = controller
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        disableTouches(on: controller)
        return controller
    }

    public func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // AVPlayer принадлежит координатору воспроизведения — правим здесь
        // только приём касаний: контроллер кэшируется и переживает пересборку
        // представления, а UIKit умеет вернуть флаг сам.
        disableTouches(on: vc)
    }

    /// Поверхность родного плеера НЕ принимает касания — и это не мелочь,
    /// а починка дефекта, из-за которого хром был нерабочим.
    ///
    /// Раньше на `controller.view` висел свой UITapGestureRecognizer: он
    /// поднимал и прятал панель по тапу в кадр. Вид AVPlayerViewController
    /// занимает всю сцену и лежит НИЖЕ хрома, но UIKit при hit-test отдаёт
    /// касание самому глубокому реальному UIView — а кнопки панели рисует
    /// SwiftUI, своих UIView у них нет. То есть тап по «Полный экран» уходил
    /// не в кнопку, а в поверхность: панель гасла, кнопка не срабатывала, и
    /// из портрета было не выйти. Живой кейс PlayerChromeLiveUITests ловил
    /// это как «кнопка перестала существовать сразу после тапа».
    ///
    /// Своей интерактивности у поверхности нет вовсе: системная панель AVKit
    /// выключена (`showsPlaybackControls = false`), PiP стартует без касаний.
    /// С выключенным приёмом касаний hit-test проходит сквозь неё в SwiftUI:
    /// кнопки хрома получают свой тап, а пустой кадр — жест `.onTapGesture`
    /// корневого стека комнаты, который и переключает хром.
    private func disableTouches(on vc: AVPlayerViewController) {
        guard vc.view.isUserInteractionEnabled else { return }
        vc.view.isUserInteractionEnabled = false
    }
}

/// Wraps a UIView (WKWebView for embedded YouTube) for SwiftUI.
/// Uses a container so Auto Layout always gives the webview a non-zero frame
/// (zero-size WKWebView often never finishes YouTube IFrame load).
public struct EmbeddedViewRepresentable: UIViewRepresentable {
    public let view: UIView
    public var onTap: (() -> Void)? = nil

    /// Тап принадлежит кадру, а не кнопке хрома над ним. См.
    /// `PlayerSurfaceView.shouldHandleSurfaceTap`.
    public var shouldHandleTap: ((CGPoint, CGSize) -> Bool)? = nil

    public init(view: UIView,
                onTap: (() -> Void)? = nil,
                shouldHandleTap: ((CGPoint, CGSize) -> Bool)? = nil) {
        self.view = view
        self.onTap = onTap
        self.shouldHandleTap = shouldHandleTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, shouldHandleTap: shouldHandleTap)
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        install(view, in: container)
        // Recognized alongside the web view's own gestures: the page still
        // gets its click, and the room still learns about the tap.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = context.coordinator
        container.addGestureRecognizer(tap)
        return container
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (() -> Void)?
        var shouldHandleTap: ((CGPoint, CGSize) -> Bool)?

        init(onTap: (() -> Void)?, shouldHandleTap: ((CGPoint, CGSize) -> Bool)?) {
            self.onTap = onTap
            self.shouldHandleTap = shouldHandleTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let host = recognizer.view else { return }
            // Тап в полосу хрома принадлежит кнопке, которая там нарисована.
            // Иначе одно касание и нажимало бы кнопку, и гасило панель — на
            // родном пути этот же дефект делал «Полный экран» нерабочим.
            if let gate = shouldHandleTap,
               !gate(recognizer.location(in: host), host.bounds.size) {
                return
            }
            onTap?()
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.shouldHandleTap = shouldHandleTap
        if view.superview !== uiView {
            // Only re-parent if needed — never strip a live WKWebView mid-load
            // when it's already correctly installed.
            if view.superview != nil {
                view.removeFromSuperview()
            }
            uiView.subviews.forEach { sub in
                if sub !== view { sub.removeFromSuperview() }
            }
            install(view, in: uiView)
        }
        // Keep frame in sync with container (constraints also active)
        if uiView.bounds.width > 0, uiView.bounds.height > 0 {
            view.frame = uiView.bounds
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func install(_ child: UIView, in parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}
