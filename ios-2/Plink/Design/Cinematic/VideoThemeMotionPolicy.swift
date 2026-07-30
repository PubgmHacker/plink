// Plink/Design/Cinematic/VideoThemeMotionPolicy.swift
//
// Аудит 26.07.2026: энергодисциплина анимированных видео-тем приложения.
//
// MetalVideoBackground (живые темы Plink+ — Aurora/Cosmos/Verdant/Magma)
// раньше игнорировал ВСЕ энергорежимы: крутил декодер и Metal-рендер при
// Reduce Motion, Low Power Mode, термотроттлинге и даже в фоне приложения.
// Эталон корректного поведения — RoomLiveThemeBackdrop
// (Features/WatchRoom/RoomLiveThemeLayer.swift) и ProjectorBeamBackground:
// при любом из режимов показывается статичный кадр.
//
// Логика решения «анимировать или нет» вынесена сюда в ЧИСТУЮ функцию —
// без UIKit/SwiftUI, только Foundation — чтобы тестироваться юнит-тестами
// (PlinkTests/VideoThemeMotionPolicyTests.swift) без симулятора.

import Foundation

/// Снимок окружения, от которого зависит решение «крутить видео или заморозить».
/// Все поля — примитивы: заполняются из SwiftUI Environment / ProcessInfo
/// на месте вызова, сама структура о них не знает.
struct VideoThemeMotionInputs: Equatable {
    /// Настройки → Универсальный доступ → Уменьшение движения.
    var reduceMotion: Bool
    /// Режим энергосбережения (ProcessInfo.isLowPowerModeEnabled).
    var lowPowerMode: Bool
    /// Термотроттлинг: ProcessInfo.thermalState != .nominal.
    var thermalThrottled: Bool
    /// scenePhase == .active. В фоне и в inactive рендерить нечего и незачем.
    var sceneActive: Bool
    /// Пользовательский тумблер «Живое движение» (PlinkAppearancePrefs.livingMotion).
    var motionPreferenceEnabled: Bool = true
}

enum VideoThemeMotionPolicy {

    /// Единственное место, где решается, играет ли фоновая видео-тема.
    /// true — декодер и рендер работают; false — пауза и статичный постер-кадр.
    static func shouldAnimate(_ inputs: VideoThemeMotionInputs) -> Bool {
        inputs.motionPreferenceEnabled
            && !inputs.reduceMotion
            && !inputs.lowPowerMode
            && !inputs.thermalThrottled
            && inputs.sceneActive
    }

    /// Reduce Transparency: как в RoomLiveThemeBackdrop, интенсивность фона
    /// режется, а не выключается — текст поверх должен стоять на плотном фоне.
    /// `base` — авторская яркость видео (0…1), возвращается ужатое значение.
    static func effectiveVideoOpacity(base: Double, reduceTransparency: Bool) -> Double {
        let clamped = min(max(base, 0), 1)
        return reduceTransparency ? min(clamped, 0.25) : clamped
    }
}
