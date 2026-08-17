import Foundation
import AVFoundation
import Combine

// MARK: - Audio Manager (Блок 4 — Audio Ducking)
/// Предотвращает «кашу» из звуков во время голосового общения.
///
/// Логика:
/// - Отслеживает флаг активности микрофона `isSpeaking` (локально или удалённо).
/// - При `isSpeaking == true` плавно (0.3 сек) приглушает видеоплеер (1.0 → 0.3).
/// - При `isSpeaking == false` возвращает громкость на 100%.
///
@MainActor
final class AudioManager: ObservableObject {

    // MARK: - Config

    /// Нормальная громкость плеера.
    private let normalVolume: Float = 1.0

    /// Приглушённая громкость (когда кто-то говорит).
    private let duckedVolume: Float = 0.3

    /// Длительность плавного перехода (сек).
    private let duckDuration: TimeInterval = 0.3

    // MARK: - Published State

    /// Текущий флаг: кто-то говорит прямо сейчас (локальный или удалённый юзер).
    @Published private(set) var isSomeoneSpeaking: Bool = false

    /// Текущая громкость плеера (для UI-индикации).
    @Published private(set) var currentVolume: Float = 1.0

    // MARK: - Dependencies

    /// Слабая ссылка на AVPlayer видеоплеера комнаты.
    private weak var player: AVPlayer?

    /// Set участников, которые говорят прямо сейчас (по peerId).
    private var speakingPeers: Set<String> = []

    /// 🔧 FIX H6: Track the current volume animation Task so we can cancel it
    /// before starting a new one. Was: 10 racing Tasks per call, each writing
    /// player.volume with stale delta values → unpredictable final volume.
    private var volumeAnimTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Player Binding

    func attach(player: AVPlayer) {
        self.player = player
        player.volume = normalVolume
        currentVolume = normalVolume
    }

    func detach() {
        player = nil
        speakingPeers.removeAll()
        isSomeoneSpeaking = false
    }

    // MARK: - Speaking State Updates

    /// Локальный пользователь начал/прекратил говорить.
    func setLocalSpeaking(_ speaking: Bool) {
        if speaking {
            speakingPeers.insert("local")
        } else {
            speakingPeers.remove("local")
        }
        updateDucking()
    }

    /// Удалённый участник начал/прекратил говорить.
    func setRemoteSpeaking(_ speaking: Bool, peerId: String) {
        if speaking {
            speakingPeers.insert(peerId)
        } else {
            speakingPeers.remove(peerId)
        }
        updateDucking()
    }

    // MARK: - Ducking Logic

    /// Пересчитывает состояние ducking на основе `speakingPeers`.
    private func updateDucking() {
        let shouldDuck = !speakingPeers.isEmpty

        guard shouldDuck != isSomeoneSpeaking else { return }
        isSomeoneSpeaking = shouldDuck

        let targetVolume = shouldDuck ? duckedVolume : normalVolume

        // Плавная анимация громкости через AVAudioMix не подходит для live-ducking,
        // поэтому используем поэтапную интерполяцию (короткими шагами за duckDuration).
        animateVolume(to: targetVolume, duration: duckDuration)
    }

    /// Плавно меняет громкость плеера за указанное время.
    /// 🔧 FIX H6: Cancel any in-flight animation before starting a new one.
    /// Was: spawned 10 racing Tasks per call, each writing player.volume with
    /// stale delta values → unpredictable final volume on rapid mute→unmute.
    private func animateVolume(to target: Float, duration: TimeInterval) {
        guard let player else { return }

        // Cancel the previous animation Task — its stale steps will be discarded.
        volumeAnimTask?.cancel()

        let steps = 10
        let stepDuration = duration / Double(steps)
        let startVolume = currentVolume
        let delta = target - startVolume

        currentVolume = target

        volumeAnimTask = Task { @MainActor [weak self, weak player] in
            guard let player else { return }
            for step in 1...steps {
                // Bail out if a newer animation Task was started.
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
                if Task.isCancelled { return }
                let progress = Float(step) / Float(steps)
                player.volume = startVolume + delta * progress
                self?.currentVolume = player.volume
            }
        }
    }

    // MARK: - Mute All (полное отключение, напр. при входящем звонке)

    /// Мгновенно выключает звук плеера (без анимации).
    func mutePlayer() {
        player?.volume = 0
        currentVolume = 0
    }

    /// Восстанавливает нормальную громкость.
    func unmutePlayer() {
        let target = isSomeoneSpeaking ? duckedVolume : normalVolume
        animateVolume(to: target, duration: duckDuration)
    }
}
