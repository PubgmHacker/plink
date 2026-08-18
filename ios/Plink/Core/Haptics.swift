//  Haptics.swift
//  Plink — M39
//
//  Генераторы кэшируются и готовятся заранее: создание генератора в момент нажатия
//  даёт задержку до 100 мс — именно она ощущается как «тормозящий интерфейс».

import UIKit

// Хранимое свойство `light` и метод `light()` — это для Swift
// одно и то же имя в одном типе (базовое имя совпадает, аргументов нет) —
// отсюда «Invalid redeclaration of 'light()'» и то же для 'medium()'.
// Генераторам дан суффикс Generator — как у уже существовавшего selectionGenerator.
// Публичный API (Haptics.light(), Haptics.medium(), …) не изменился.
@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func prepare() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        rigidGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    static func light() { lightGenerator.impactOccurred() }
    static func medium() { mediumGenerator.impactOccurred() }
    static func rigidTap() { rigidGenerator.impactOccurred() }
    static func selection() { selectionGenerator.selectionChanged() }
    static func success() { notificationGenerator.notificationOccurred(.success) }
    static func warning() { notificationGenerator.notificationOccurred(.warning) }
    static func error() { notificationGenerator.notificationOccurred(.error) }

    /// Отсчёт 3-2-1 перед стартом просмотра: каждая цифра — короткий тик.
    static func countdownTick() { rigidGenerator.impactOccurred(intensity: 0.7) }
    static func countdownFinish() { notificationGenerator.notificationOccurred(.success) }
}
