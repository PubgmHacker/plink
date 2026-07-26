//  Haptics.swift
//  Plink — M39
//
//  Генераторы кэшируются и готовятся заранее: создание генератора в момент нажатия
//  даёт задержку до 100 мс — именно она ощущается как «тормозящий интерфейс».

import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        selectionGenerator.prepare()
        notification.prepare()
    }

    static func light() { light.impactOccurred() }
    static func medium() { medium.impactOccurred() }
    static func rigidTap() { rigid.impactOccurred() }
    static func selection() { selectionGenerator.selectionChanged() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    static func error() { notification.notificationOccurred(.error) }

    /// Отсчёт 3-2-1 перед стартом просмотра: каждая цифра — короткий тик.
    static func countdownTick() { rigid.impactOccurred(intensity: 0.7) }
    static func countdownFinish() { notification.notificationOccurred(.success) }
}
