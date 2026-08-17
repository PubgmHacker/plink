// Plink/Services/VoiceNotePlayer.swift
// Plays friend-DM voice notes: local cache (just-sent) + authenticated download.

import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceNotePlayer: NSObject {
    static let shared = VoiceNotePlayer()

    private(set) var playingMessageId: String?
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var tickTimer: Timer?
    /// messageId → on-disk m4a (downloaded or written from local record)
    private var fileCache: [String: URL] = [:]
    /// messageId → raw bytes (optimistic send before server id exists)
    private var memoryCache: [String: Data] = [:]
    private let api = APIClient.shared

    // MARK: - Local register (own just-recorded notes)

    /// Keep bytes so own voice plays immediately without waiting for GET /voice/:id.
    func registerLocal(messageId: String, data: Data) {
        guard !messageId.isEmpty, data.count > 100 else { return }
        memoryCache[messageId] = data
        if let url = try? writeToDisk(messageId: messageId, data: data) {
            fileCache[messageId] = url
        }
    }

    /// After POST /dm/voice returns server id — keep the same audio under the new key.
    func promote(from localId: String, to serverId: String) {
        guard localId != serverId, !serverId.isEmpty else { return }
        if let data = memoryCache.removeValue(forKey: localId) {
            memoryCache[serverId] = data
        }
        if let oldURL = fileCache.removeValue(forKey: localId) {
            if let data = try? Data(contentsOf: oldURL),
               let newURL = try? writeToDisk(messageId: serverId, data: data) {
                fileCache[serverId] = newURL
                try? FileManager.default.removeItem(at: oldURL)
            } else {
                fileCache[serverId] = oldURL
            }
        }
        if playingMessageId == localId {
            playingMessageId = serverId
        }
    }

    // MARK: - Playback

    func toggle(messageId: String) {
        if playingMessageId == messageId, player?.isPlaying == true {
            stop()
            return
        }
        Task { await play(messageId: messageId) }
    }

    func play(messageId: String) async {
        stop(keepCache: true)
        errorMessage = nil
        isLoading = true
        playingMessageId = messageId
        defer { isLoading = false }

        do {
            let fileURL = try await localFile(for: messageId)
            try configurePlaybackSession()
            let p = try AVAudioPlayer(contentsOf: fileURL)
            p.delegate = self
            p.volume = 1.0
            p.prepareToPlay()
            // Some devices need a brief delay after session flip (record → play).
            try await Task.sleep(nanoseconds: 30_000_000)
            guard p.play() else {
                throw URLError(.cannotDecodeContentData)
            }
            player = p
            progress = 0
            startTick()
        } catch {
            errorMessage = friendlyError(error)
            playingMessageId = nil
            Logger.app.error("[VoiceNote] play error id=\(messageId): \(error)")
        }
    }

    func stop(keepCache: Bool = true) {
        tickTimer?.invalidate()
        tickTimer = nil
        player?.stop()
        player = nil
        playingMessageId = nil
        progress = 0
        if !keepCache {
            for (_, url) in fileCache {
                try? FileManager.default.removeItem(at: url)
            }
            fileCache.removeAll()
            memoryCache.removeAll()
        }
        // Don't deactivate session aggressively — avoids killing next play.
    }

    // MARK: - Resolve file

    private func localFile(for messageId: String) async throws -> URL {
        if let cached = fileCache[messageId], FileManager.default.fileExists(atPath: cached.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: cached.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            if size > 100 { return cached }
        }

        if let data = memoryCache[messageId], data.count > 100 {
            let url = try writeToDisk(messageId: messageId, data: data)
            fileCache[messageId] = url
            return url
        }

        // Download from API
        if api.authToken == nil {
            api.authToken = AuthTokenStore.shared.token
                ?? AuthService.shared.authToken
        }
        guard let token = api.authToken else {
            throw URLError(.userAuthenticationRequired)
        }

        // Build path safely (avoid slash encoding issues on some SDKs)
        let url = api.baseURL
            .appendingPathComponent("messages")
            .appendingPathComponent("voice")
            .appendingPathComponent(messageId)

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 {
                throw VoicePlayError.notFound
            }
            throw VoicePlayError.http(http.statusCode)
        }
        guard data.count > 100 else {
            throw VoicePlayError.empty
        }

        // Validate it looks like media (m4a/mp4 often starts with ftyp after size box)
        let file = try writeToDisk(messageId: messageId, data: data)
        fileCache[messageId] = file
        memoryCache[messageId] = data
        return file
    }

    private func writeToDisk(messageId: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plink-voice-play", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Use safe file name (ids are UUIDs)
        let safe = messageId.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent("\(safe).m4a")
        try data.write(to: file, options: .atomic)
        return file
    }

    private func configurePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback → audible even with the hardware mute switch (messenger standard)
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.duckOthers]
        )
        try session.setActive(true, options: [])
        // Prefer loudspeaker for phone earpiece devices when possible
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = min(1, p.currentTime / p.duration)
                if !p.isPlaying, self.progress >= 0.98 {
                    self.progress = 1
                }
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let v = error as? VoicePlayError {
            switch v {
            case .notFound: return "Аудио ещё не загружено"
            case .empty: return "Пустой файл"
            case .http(let c): return "Ошибка \(c)"
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "Нет сети для голосового"
        }
        return error.localizedDescription
    }
}

private enum VoicePlayError: Error {
    case notFound
    case empty
    case http(Int)
}

extension VoiceNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.progress = 1
            self.playingMessageId = nil
            self.tickTimer?.invalidate()
            self.tickTimer = nil
            self.player = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.errorMessage = error?.localizedDescription ?? "Ошибка декодирования"
            self.playingMessageId = nil
            self.player = nil
        }
    }
}
