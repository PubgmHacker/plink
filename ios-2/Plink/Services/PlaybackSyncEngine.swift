//  PlaybackSyncEngine.swift
//  Plink — M39
//
//  Движок, который держит картинку у всех участников в одной точке.
//
//  Ключевое решение: малые расхождения исправляются ИЗМЕНЕНИЕМ СКОРОСТИ (±5%),
//  а не перемоткой. Перемотка каждые несколько секунд — главная причина,
//  по которой люди бросают совместный просмотр. Изменение скорости на 5% незаметно уху.

import Foundation
import AVFoundation
import Combine

@MainActor
final class PlaybackSyncEngine: ObservableObject {

    struct HostState {
        let position: TimeInterval
        let timestamp: Date
        let isPlaying: Bool
        let rate: Float
    }

    @Published private(set) var driftMilliseconds: Int = 0
    @Published private(set) var isCorrecting = false
    @Published private(set) var correctionsCount = 0
    @Published private(set) var quality: ClockSync.Quality = .unknown

    /// Меньше 50 мс — человек не воспринимает рассинхрон. Не трогаем.
    private let deadZone: TimeInterval = 0.05
    /// До 300 мс — мягко догоняем скоростью. Больше — честная перемотка.
    private let softCorrectionLimit: TimeInterval = 0.3
    private let maxRateDelta: Float = 0.05
    private let tickInterval: TimeInterval = 0.5

    private weak var player: AVPlayer?
    private var host: HostState?
    private var timer: Timer?

    func attach(player: AVPlayer) {
        self.player = player
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        player = nil
        host = nil
        isCorrecting = false
    }

    func update(hostState: HostState) {
        host = hostState
        tick()
    }

    private func tick() {
        guard let player, let host else { return }

        Task {
            let clock = ClockSync.shared
            await clock.syncIfNeeded()
            let serverNow = await clock.serverNow
            let currentQuality = await clock.quality

            await MainActor.run {
                self.quality = currentQuality

                guard host.isPlaying else {
                    if player.rate != 0 { player.pause() }
                    self.isCorrecting = false
                    return
                }

                // Где должны быть сейчас, если бы шли вровень с хостом.
                let elapsed = serverNow.timeIntervalSince(host.timestamp)
                let target = host.position + elapsed * Double(host.rate)
                let actual = player.currentTime().seconds
                guard actual.isFinite else { return }

                let drift = target - actual
                self.driftMilliseconds = Int(drift * 1000)

                if abs(drift) <= self.deadZone {
                    if player.rate != host.rate { player.rate = host.rate }
                    self.isCorrecting = false
                    return
                }

                if abs(drift) <= self.softCorrectionLimit {
                    // Мягкая коррекция: догоняем примерно за 6 секунд, незаметно для уха.
                    let delta = Float(max(-1, min(1, drift / 6))) * self.maxRateDelta
                    player.rate = host.rate + delta
                    self.isCorrecting = true
                } else {
                    // Жёсткая коррекция: точный seek без допусков.
                    let time = CMTime(seconds: target, preferredTimescale: 600)
                    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        Task { @MainActor in player.rate = host.rate }
                    }
                    self.correctionsCount += 1
                    self.isCorrecting = true
                }
            }
        }
    }
}
