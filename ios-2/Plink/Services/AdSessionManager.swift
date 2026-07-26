import Foundation
import SwiftUI
import Combine

// MARK: - Ad Session Manager (Блок 2 — Синхронизированная реклама)
/// Управляет рекламными сессиями внутри комнаты.
///
/// Логика:
/// - Хост запускает таймер (15–25 мин).
/// - Перед триггером проверяется room.host.isPremium.
/// - ЕСЛИ ХОСТ PREMIUM → реклама ОТКЛЮЧЕНА для ВСЕХ участников.
/// - ЕСЛИ ХОСТ БЕЗ ПРЕМИУМА → реклама для ВСЕХ одновременно.
/// - Реклама встраивается ВНУТРЬ фрейма плеера (AdPlayerView), не на весь экран.
/// - Чат, микрофоны и кнопки остаются активны во время рекламы.

@MainActor
final class AdSessionManager: ObservableObject {

    // MARK: - Published State

    /// Реклама активна прямо сейчас (плеер на паузе, AdPlayerView виден).
    @Published private(set) var isAdPlaying = false

    /// Таймер до следующей рекламы (отображается в UI, секунды).
    @Published var nextAdCountdown: Int = 0

    /// Причина, по которой реклама пропущена (для Premium badge).
    @Published var adSkipReason: AdSkipReason?

    // MARK: - Config

    /// Минимальный интервал между рекламами (секунды).
    private let minAdInterval: TimeInterval = 15 * 60   // 15 минут

    /// Максимальный интервал (секунды).
    private let maxAdInterval: TimeInterval = 25 * 60   // 25 минут

    /// Длительность одной рекламной паузы (секунды).
    private let adDuration: TimeInterval = 15

    // MARK: - Callbacks

    /// Вызывается когда нужно показать рекламу (пауза плеера + показ AdPlayerView).
    var onAdShouldPlay: (() -> Void)?

    /// Вызывается когда реклама закончилась (возобновление плеера).
    var onAdFinished: (() -> Void)?

    /// Хост отправляет команду рекламы участникам через WS.
    var onBroadcastAdCommand: ((AdRoomCommand) -> Void)?

    // MARK: - Dependencies

    private var adTimer: Timer?
    private var countdownTimer: Timer?
    private var currentUserId: String
    private var isHost: Bool

    // MARK: - Init

    init(currentUserId: String, isHost: Bool) {
        self.currentUserId = currentUserId
        self.isHost = isHost
    }

    deinit {
        // 🔧 FIX H4: Timers MUST be invalidated explicitly. The comment "timers
        // invalidate themselves" was wrong — Timer.scheduledTimer is retained by
        // the run loop until invalidated, leaking the AdSessionManager instance.
        adTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    // MARK: - Start / Stop

    /// Запускает рекламный таймер (только ХОСТ вызывает).
    func startAdTimer() {
        guard isHost else { return }
        stopAllTimers()

        // Случайный интервал 15–25 минут.
        let interval = TimeInterval.random(in: minAdInterval...maxAdInterval)
        nextAdCountdown = Int(interval)

        // Countdown тикер (каждую секунду).
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.nextAdCountdown > 0 else { return }
                self.nextAdCountdown -= 1
            }
        }

        // Основной таймер — триггер рекламы.
        adTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerAd()
            }
        }
    }

    /// Останавливает все рекламные таймеры.
    func stopAllTimers() {
        adTimer?.invalidate()
        adTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Premium Bypass Check

    /// Проверяет, должен ли хост показывать рекламу.
    /// Вызывается перед триггером рекламы.
    func shouldPlayAd(hostIsPremium: Bool) -> Bool {
        if hostIsPremium {
            adSkipReason = .premiumHost
            // Перезапускаем таймер без показа рекламы.
            startAdTimer()
            return false
        }
        adSkipReason = nil
        return true
    }

    // MARK: - Ad Trigger (Host)

    private func triggerAd() {
        guard !isAdPlaying else { return }

        // 🔧 FIX C10: Premium host bypass — was dead code before (shouldPlayAd
        // existed but was never called from triggerAd). Now always checked first.
        // Uses PremiumStatusManager.shared.isPremium as the authoritative source.
        if !shouldPlayAd(hostIsPremium: PremiumStatusManager.shared.isPremium) {
            // shouldPlayAd already restarted the timer for the next interval.
            // No ad shown — premium host (and their guests) see no ads.
            return
        }

        isAdPlaying = true
        nextAdCountdown = 0

        // Хост рассылает команду рекламы участникам.
        onBroadcastAdCommand?(.play)
        onAdShouldPlay?()

        // Автоматическое завершение рекламы через adDuration.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self?.adDuration ?? 15) * 1_000_000_000)
            self?.finishAd()
        }
    }

    // MARK: - Receive Ad Command (Guest)

    /// Участник получил команду рекламы от хоста через WS.
    func receiveAdCommand(_ command: AdRoomCommand) {
        switch command {
        case .play:
            guard !isAdPlaying else { return }
            isAdPlaying = true
            nextAdCountdown = 0
            onAdShouldPlay?()

            // Гост тоже заканчивает через adDuration (или ждёт команду finish).
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(self?.adDuration ?? 15) * 1_000_000_000)
                self?.finishAd()
            }

        case .finish:
            finishAd()
        }
    }

    // MARK: - Finish Ad

    private func finishAd() {
        guard isAdPlaying else { return }
        isAdPlaying = false
        onAdFinished?()

        // Хост рассылает команду завершения + перезапускает таймер.
        if isHost {
            onBroadcastAdCommand?(.finish)
            startAdTimer()
        }
    }

    /// Ручное завершение рекламы (например, если юзер закрыл AdPlayerView).
    func dismissAd() {
        finishAd()
    }
}

// MARK: - Ad Room Command (WS payload)
/// Команды рекламы, рассылаемые хостом через WebSocket.
enum AdRoomCommand: String, Codable, Sendable {
    case play   // Хост запускает рекламу для всех
    case finish // Хост завершает рекламу для всех
}

// MARK: - Ad Skip Reason
enum AdSkipReason: String, Sendable {
    case premiumHost = "premium_host" // Хост имеет Premium — реклама отключена для всех
}
