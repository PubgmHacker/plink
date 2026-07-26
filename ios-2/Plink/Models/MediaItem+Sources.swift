//  MediaItem+Sources.swift
//  Plink — M39
//
//  Баг №3 из аудита: в старом коде было `MediaItem.MediaSource(rawValue: raw) ?? .url`.
//  Любой нераспознанный источник тихо становился `.url` и уезжал в AVPlayer,
//  который молча показывал чᄅрный экран. Здесь старая модель связывается с новым
//  резолвером, и нераспознанное честно помечается как неподдерживаемое.

import Foundation

extension MediaItem {

    /// Разобранный источник. `nil` означает, что ссылка не поддерживается.
    /// Никаких молчаливых фолбэков на `.url`.
    var resolvedSource: MediaSourceResolver.Resolved? {
        MediaSourceResolver.resolve(rawURL)
    }

    /// Можно ли вообще воспроизвести этот элемент.
    var isPlayable: Bool {
        resolvedSource != nil
    }

    /// Точная кадровая синхронизация возможна только в родном плеере.
    /// В embed-плеерах мы не управляем буфером и не должны обещать «кадр в кадр».
    var supportsPreciseSync: Bool {
        resolvedSource?.supportsPreciseSync ?? false
    }

    /// Что показать пользователю, если воспроизвести нельзя.
    var unsupportedReason: String? {
        guard resolvedSource == nil else { return nil }
        return String(localized: "media.unsupported.reason",
                      defaultValue: "Мы пока не умеем открывать ссылки с этого сайта. Поддерживаются Rutube, VK Видео, Одноклассники, Дзен, YouTube, Vimeo и прямые видеофайлы.")
    }

    /// Название сервиса для штампа на карточке.
    var sourceLabel: String {
        resolvedSource?.kind.label ?? String(localized: "media.source.unknown",
                                             defaultValue: "Неизвестный источник")
    }

    var sourceIcon: String {
        resolvedSource?.kind.icon ?? "questionmark.circle"
    }
}

// MARK: - Миграция старого перечисления

extension MediaItem.MediaSource {

    /// Сопоставление старых raw-значений с новыми видами источников.
    /// Нужно для чтения записей, созданных до M39.
    init?(resolvedKind: MediaSourceResolver.Kind) {
        switch resolvedKind {
        case .rutube:      self.init(rawValue: "rutube")
        case .vk:          self.init(rawValue: "vk")
        case .ok:          self.init(rawValue: "ok")
        case .dzen:        self.init(rawValue: "dzen")
        case .youtube:     self.init(rawValue: "youtube")
        case .vimeo:       self.init(rawValue: "vimeo")
        case .nativePlayer: self.init(rawValue: "url")
        }
    }
}
