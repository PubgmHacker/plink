//
//  PlinkPushCover.swift
//  Plink
//
//  Полноэкранный «пуш» по модели Telegram/VK и окружение plinkPushDismiss.
//  Вынесен из DMChatView.swift: файл упёрся в лимит длины SwiftLint.
//

import SwiftUI
import UIKit

// MARK: - Полноэкранный «пуш» (модель Telegram/VK)

private struct PlinkPushDismissKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Закрытие экрана, поднятого `PlinkPushCover`, тем же горизонтальным
    /// ходом. `nil` — экран показан обычным способом, работает `dismiss`.
    var plinkPushDismiss: (() -> Void)? {
        get { self[PlinkPushDismissKey.self] }
        set { self[PlinkPushDismissKey.self] = newValue }
    }
}

/// Снимок экрана под пушем. `fullScreenCover` убирает родителя из иерархии,
/// а Telegram и ВК при свайпе «назад» показывают список чатов под уезжающим
/// экраном — с параллаксом и затемнением. Снимок делается в момент открытия,
/// пока родитель ещё на экране.
enum PlinkPushBackdrop {
    @MainActor
    static func capture() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes
        guard let window = scenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

/// Отдаёт содержимому действие «закрыть» текущего `PlinkPushCover` — для
/// крестика в тулбаре и кнопок, которым нужен тот же горизонтальный уход.
/// Вне пуша (превью, обычный показ) сводится к системному `dismiss`.
struct PlinkPushCloseHost<Content: View>: View {
    @Environment(\.plinkPushDismiss) private var pushDismiss
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: (@escaping () -> Void) -> Content

    var body: some View {
        content { (pushDismiss ?? { dismiss() })() }
    }
}

/// Экран поверх всего приложения по модели push из Telegram и ВК: въезжает
/// справа, уезжает вправо, свайп от левого края возвращает назад.
///
/// Личка раньше открывалась `.sheet`: скруглённые углы, ручка-свайп сверху,
/// просвет родителя по краям и обрезанная полоса статус-бара. Ни один
/// мессенджер так чат не показывает — там он занимает весь экран целиком,
/// вместе с зоной статус-бара, под которой лежит блюр шапки.
///
/// Собственная (вертикальная) анимация `.fullScreenCover` гасится снаружи
/// через `.transaction { $0.disablesAnimations = true }` — горизонтальный ход
/// рисует сам контейнер, поэтому появление читается как push, а не как штора.
///
/// `backdrop` — снимок родителя (`PlinkPushBackdrop.capture()`): под уезжающим
/// экраном виден список, он едет за пальцем с параллаксом 30 % и светлеет,
/// как в Telegram. Без снимка под экраном чёрный фон — так было раньше.
struct PlinkPushCover<Content: View>: View {
    var backdrop: UIImage? = nil
    let onClose: () -> Void
    @ViewBuilder var content: Content

    @State private var entered = false
    @State private var dragX: CGFloat = 0
    @State private var closing = false
    /// Протяг признан жестом «назад». Решение принимается один раз в начале
    /// хода и держится до отрыва пальца.
    @State private var edgeDrag = false

    /// Ширина экрана нужна до первого прохода компоновки (стартовое смещение),
    /// поэтому берётся из окна, а не из GeometryReader.
    private var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        return window?.bounds.width ?? UIScreen.main.bounds.width
    }

    /// Критически задемпфированная пружина: ход как у системного push,
    /// без отскока в конце.
    private var curve: Animation { .interpolatingSpring(stiffness: 340, damping: 34) }

    var body: some View {
        let w = screenWidth
        // Доля хода «назад»: 0 — экран на месте, 1 — уехал целиком.
        let leave = entered ? min(1, max(0, dragX / max(w, 1))) : 1
        content
            .environment(\.plinkPushDismiss, close)
            .offset(x: entered ? dragX : w)
            // Тень по левому краю — экран читается отдельным слоем над списком,
            // ровно как лист push-навигации.
            .shadow(color: .black.opacity(0.5), radius: 14, x: -8, y: 0)
            // Подложка лежит в background, а не в ZStack: снимок на всё окно
            // раздувал бы ZStack за пределы safe area, и шапка чата уезжала
            // под статус-бар. Фон на размер контента не влияет.
            .background {
                ZStack {
                    Color.black
                    if let backdrop {
                        Image(uiImage: backdrop)
                            .resizable()
                            .scaledToFill()
                            // Параллакс системного push: список стоит на −30 %
                            // ширины и доезжает до нуля вместе с уходом экрана.
                            .offset(x: -w * 0.3 * (1 - leave))
                            .overlay(Color.black.opacity(0.42 * (1 - leave)))
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        // Жест «назад» висит на всём экране и сам отбирает свои протяги по
        // точке старта. Отдельной полосой-перехватчиком у края он быть не
        // может: она накрывала стрелку «‹» (та стоит в 16 pt от края) и
        // съедала по ней тап — чат не закрывался кнопкой.
        .simultaneousGesture(backGesture(width: w))
        .onAppear {
            guard !entered else { return }
            withAnimation(curve) { entered = true }
        }
        // Транзакция показа гасит анимации всему поддереву cover'а —
        // внутри возвращаем их обратно. Иначе чат живёт без единого
        // движения: не едет пилюля «вниз», не пружинит свайп-ответ,
        // не доезжает и сам горизонтальный ход этого контейнера.
        .transaction { $0.disablesAnimations = false }
    }

    private func backGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !closing else { return }
                if !edgeDrag {
                    // Ход берём только от самого края и только вправо: лента
                    // оставляет себе вертикаль, пузырь — свайп-ответ влево.
                    guard value.startLocation.x <= 22,
                          value.translation.width > 0,
                          value.translation.width > abs(value.translation.height)
                    else { return }
                    edgeDrag = true
                }
                dragX = max(0, value.translation.width)
            }
            .onEnded { value in
                guard !closing, edgeDrag else {
                    edgeDrag = false
                    return
                }
                edgeDrag = false
                // Порог как у системного жеста: треть ширины или бросок.
                let far = value.translation.width > width * 0.32
                let flick = value.predictedEndTranslation.width > width * 0.62
                if far || flick {
                    close()
                } else {
                    withAnimation(curve) { dragX = 0 }
                }
            }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        HapticManager.selection()
        withAnimation(curve) { dragX = screenWidth }
        // Снимаем показ после ухода кадра — иначе экран мигнёт на месте.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onClose() }
    }
}
