import Foundation
import UIKit

// MARK: - Profile View Model (Блок 2 — Профиль + История просмотров)
@MainActor
@Observable
final class ProfileViewModel {

    // MARK: - State

    var user: User?
    var isLoading = false
    var errorMessage: String?

    /// Локально выбранная аватарка из галереи.
    /// Раньше была computed property от static var — @Observable не отслеживает
    /// static storage, поэтому SwiftUI не перерисовывал экраны при смене аватара.
    /// Теперь это stored instance property — @Observable отслеживает её напрямую.
    /// Синхронизация между инстансами (ProfileView ↔ SettingsView) идёт через
    /// NotificationCenter: при saveAvatar() все инстансы получают уведомление и
    /// обновляют свой instance avatarImage.
    var avatarImage: UIImage?

    /// NEW: Cover photo (обложка профиля как ВКонтакте) — фоновое фото
    /// над аватаром. Хранится локально в Documents/cover.jpg, синхронизируется
    /// между инстансами через NotificationCenter (как avatarImage).
    var coverImage: UIImage?

    /// Общий аватар для всех ProfileViewModel-инстансов (профиль + шторка настроек).
    /// При изменении постит notification — все инстансы подтягивают новое значение.
    static var sharedAvatar: UIImage? {
        didSet { Self.notifyAvatarChange() }
    }

    /// NEW: Общая обложка профиля (как ВКонтакте) — статическая, синхронизируется
    /// между инстансами через NotificationCenter (как sharedAvatar).
    static var sharedCover: UIImage? {
        didSet { Self.notifyCoverChange() }
    }

    /// Уведомляет все инстансы об изменении аватара.
    private static func notifyAvatarChange() {
        NotificationCenter.default.post(name: Self.avatarChangedNotification, object: nil)
    }
    static let avatarChangedNotification = Notification.Name("plink_avatar_changed")

    /// NEW: Уведомляет все инстансы об изменении обложки.
    private static func notifyCoverChange() {
        NotificationCenter.default.post(name: Self.coverChangedNotification, object: nil)
    }
    static let coverChangedNotification = Notification.Name("plink_cover_changed")

    /// Подписка на смену аватара другим инстансом (например, когда юзер
    /// меняет фото в ProfileView — SettingsView тоже должен обновиться немедленно).
    ///
    /// SWIFT 6: stored in `MutexBox` (let Sendable wrapper). Computed accessor
    /// is `nonisolated` — works without `unsafe` because it's computed. Avoids
    /// the contradictory Swift 6 warnings:
    ///   - `nonisolated(unsafe)` → "has no effect, consider using nonisolated"
    ///   - `nonisolated` (on mutable stored var) → "cannot be applied to mutable
    ///     stored properties"
    /// The observer token is mutated only in init (main actor) and removed in
    /// nonisolated deinit. NotificationCenter.removeObserver is internally
    /// thread-safe; MutexBox adds explicit synchronization on top.
    private let avatarObserverBox = MutexBox<NSObjectProtocol?>(nil)
    nonisolated private var avatarObserver: NSObjectProtocol? {
        get { avatarObserverBox.value }
        set { avatarObserverBox.value = newValue }
    }

    /// NEW: MutexBox wrapper for coverObserver (same pattern as avatarObserver)
    private let coverObserverBox = MutexBox<NSObjectProtocol?>(nil)
    nonisolated private var coverObserver: NSObjectProtocol? {
        get { coverObserverBox.value }
        set { coverObserverBox.value = newValue }
    }

    // История просмотров (Блок 2)
    var history: [WatchHistoryItem] {
        historyManager.history
    }

    /// Выбранный медиа-итем для пересоздания комнаты («Посмотреть снова»).
    var rewatchMedia: MediaItem?

    /// Telegram-style display name.
    /// Priority: user.displayName (if non-empty) → user.username → "Гость".
    /// Previously fell back to "Гость" whenever displayName was nil, which
    /// meant every user without an explicit display name showed as "Гость"
    /// — even though they had a perfectly good @username. Now we fall back
    /// to @username first, "Гость" only if even username is missing (e.g.
    /// not signed in).
    var displayName: String {
        if let dn = user?.displayName, !dn.isEmpty {
            return dn
        }
        if let un = user?.username, !un.isEmpty {
            return un
        }
        return "Гость"
    }

    var email: String {
        user?.email ?? ""
    }

    var username: String {
        user?.username ?? ""
    }

    var avatarURL: String? {
        user?.avatarURL
    }

    // MARK: - Stats (реальные данные из services)

    var roomsJoined: Int { history.count }
    var hoursWatched: Int {
        // Суммарная реально досмотренная длительность (watchedDuration в секундах).
        let totalSeconds = history.reduce(0.0) { $0 + $1.watchedDuration }
        return Int((totalSeconds / 3600).rounded())
    }
    var friendsCount: Int { 0 }  // Будет populated из FriendManager при интеграции

    // MARK: - Services

    let authService: AuthServiceProtocol
    private let historyManager = WatchHistoryManager()

    // MARK: - Init

    init(authService: AuthServiceProtocol) {
        self.authService = authService
        // Subscribe to avatar-changed notifications from OTHER instances.
        // When user changes photo in ProfileView, SettingsView's viewModel receives
        // this notification and updates its own instance avatarImage → @Observable
        // triggers re-render → avatar updates IMMEDIATELY, no re-entry needed.
        avatarObserver = NotificationCenter.default.addObserver(
            forName: Self.avatarChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Sync from the shared static into this instance's observable property.
                if self.avatarImage !== Self.sharedAvatar {
                    self.avatarImage = Self.sharedAvatar
                }
            }
        }
        // NEW: Subscribe to cover-changed notifications (same pattern as avatar)
        coverObserver = NotificationCenter.default.addObserver(
            forName: Self.coverChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.coverImage !== Self.sharedCover {
                    self.coverImage = Self.sharedCover
                }
            }
        }
    }

    deinit {
        // Remove the notification observer to avoid leaks / zombie callbacks.
        // deinit is implicitly nonisolated in Swift 6 — safe for strict concurrency
        // (Foundation's removeObserver is thread-safe). NB: spelling it as an
        // explicit `nonisolated deinit` needs the Swift 6.2 IsolatedDeinit feature,
        // which the CI toolchain (Xcode 16.4 / Swift 6.1) rejects outright.
        if let avatarObserver {
            NotificationCenter.default.removeObserver(avatarObserver)
        }
        // NEW: also remove cover observer
        if let coverObserver {
            NotificationCenter.default.removeObserver(coverObserver)
        }
    }

    func loadUser() async {
        isLoading = true
        // Pack v3: Загружаем с сервера (GET /users/me), не из локального кэша
        do {
            let fresh: User = try await authService.fetchCurrentUser()
            user = fresh
            // Обновляем локальный кэш в AuthService
            authService.updateCachedUser(fresh)
        } catch {
            // Fallback на локальный кэш
            user = await authService.currentUser()
        }
        loadAvatarFromDisk()
        isLoading = false
    }

    // MARK: - Avatar (загрузка из галереи)

    private let avatarCacheKey = "local_avatar_image"

    /// Сохраняет выбранное из галереи фото как локальную аватарку + загружает на сервер.
    /// SERVER UPLOAD: base64 → POST /users/me/avatar → сервер сохраняет файл +
    /// обновляет avatarURL в БД → все юзеры видят аватарку в чате.
    func saveAvatar(_ image: UIImage) {
        Self.sharedAvatar = image          // posts notification via didSet
        avatarImage = image                 // immediate instance-level update
        // Сохраняем в Documents directory
        if let data = image.jpegData(compressionQuality: 0.7) {
            let url = avatarFileURL
            try? data.write(to: url, options: .atomic)

            // UPLOAD to server
            let base64 = data.base64EncodedString()
            Task { await uploadAvatarToServer(base64: base64) }
        }
    }

    /// NEW: Upload avatar as base64 to server.
    @MainActor
    private func uploadAvatarToServer(base64: String) async {
        guard let api = authService as? AuthService else { return }
        guard let token = await api.getFreshToken() else { return }

        guard let url = URL(string: PlinkConfig.apiURLString + "/users/me/avatar") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = ["avatar": "data:image/jpeg;base64,\(base64)"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                Logger.api.info("Avatar uploaded to server")
            } else {
                Logger.api.warn("Avatar upload failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
        } catch {
            Logger.api.error("Avatar upload error: \(error.localizedDescription)")
        }
    }

    /// Загружает ранее сохранённую аватарку с диска в instance + shared-кэш.
    /// Теперь пишет и в instance avatarImage, и в static sharedAvatar.
    func loadAvatarFromDisk() {
        // Сначала синхронизируемся со shared-кэшем (мог быть загружен другим инстансом)
        if let shared = Self.sharedAvatar, avatarImage == nil {
            avatarImage = shared
        }
        guard avatarImage == nil, Self.sharedAvatar == nil else {
            loadCoverFromDisk()
            return
        }
        let url = avatarFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            Self.sharedAvatar = img    // posts notification (но текущий инстанс уже обновится ниже)
            avatarImage = img
        }
        loadCoverFromDisk()
    }

    // MARK: - Cover Photo (обложка профиля как ВКонтакте)

    /// NEW: Сохраняет выбранное фото как обложку профиля.
    /// Синхронизируется между инстансами через NotificationCenter (как avatar).
    func saveCover(_ image: UIImage) {
        Self.sharedCover = image          // posts notification via didSet
        coverImage = image                 // immediate instance-level update
        if let data = image.jpegData(compressionQuality: 0.8) {
            let url = coverFileURL
            try? data.write(to: url, options: .atomic)
        }
    }

    /// NEW: Загружает обложку с диска.
    func loadCoverFromDisk() {
        if let shared = Self.sharedCover, coverImage == nil {
            coverImage = shared
            return
        }
        guard coverImage == nil, Self.sharedCover == nil else { return }
        let url = coverFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            Self.sharedCover = img
            coverImage = img
        }
    }

    /// NEW: Удаляет обложку (return к default gradient).
    func removeCover() {
        Self.sharedCover = nil
        coverImage = nil
        try? FileManager.default.removeItem(at: coverFileURL)
    }

    private var avatarFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("avatar.jpg")
    }

    /// NEW: Cover photo file URL
    private var coverFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("cover.jpg")
    }

    // MARK: - History Actions (Блок 2)

    func removeHistoryItem(_ item: WatchHistoryItem) {
        historyManager.remove(item)
    }

    func clearHistory() {
        historyManager.clearAll()
    }

    /// Открывает создание новой комнаты с этим видео.
    func rewatch(_ item: WatchHistoryItem) {
        rewatchMedia = item.mediaItem
    }

    // MARK: - Account

    func updateUsername(_ newName: String) async {
        guard let current = user else { return }
        // Pack v3: Отправляем на сервер (PATCH /users/me)
        // Pass displayName + coverURL through too (so
        // updating username doesn't wipe displayName on the server).
        do {
            let updated: User = try await authService.updateProfile(
                username: newName,
                avatarURL: current.avatarURL,
                displayName: current.displayName,
                coverURL: current.coverURL,
                statusText: nil
            )
            user = updated
            authService.updateCachedUser(updated)
        } catch {
            // Fallback: локальное обновление
            user = User(id: current.id, username: newName, email: current.email,
                        avatarURL: current.avatarURL,
                        displayName: current.displayName, coverURL: current.coverURL,
                        isOnline: current.isOnline,
                        isPremium: current.isPremium, role: current.role, createdAt: current.createdAt)
            errorMessage = "Не удалось сохранить на сервере: \(error.localizedDescription)"
        }
    }

    /// Update display name separately from @username.
    /// Empty string clears the display name → backend uses @username as fallback.
    func updateDisplayName(_ newDisplayName: String) async {
        guard let current = user else { return }
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated: User = try await authService.updateProfile(
                username: nil,
                avatarURL: nil,
                displayName: trimmed.isEmpty ? "" : trimmed,
                coverURL: nil,
                statusText: nil
            )
            user = updated
            authService.updateCachedUser(updated)
        } catch {
            user = User(id: current.id, username: current.username, email: current.email,
                        avatarURL: current.avatarURL,
                        displayName: trimmed.isEmpty ? nil : trimmed,
                        coverURL: current.coverURL,
                        isOnline: current.isOnline,
                        isPremium: current.isPremium, role: current.role, createdAt: current.createdAt)
            errorMessage = "Не удалось сохранить на сервере: \(error.localizedDescription)"
        }
    }

    /// Combined update — username + displayName in one server call.
    /// Used by EditProfileSheet's Save button so user can change both at once.
    func updateProfile(username: String, displayName: String) async {
        guard let current = user else { return }
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated: User = try await authService.updateProfile(
                username: username,
                avatarURL: current.avatarURL,
                displayName: trimmedDisplay.isEmpty ? "" : trimmedDisplay,
                coverURL: current.coverURL,
                statusText: nil
            )
            user = updated
            authService.updateCachedUser(updated)
        } catch {
            user = User(id: current.id, username: username, email: current.email,
                        avatarURL: current.avatarURL,
                        displayName: trimmedDisplay.isEmpty ? nil : trimmedDisplay,
                        coverURL: current.coverURL,
                        isOnline: current.isOnline,
                        isPremium: current.isPremium, role: current.role, createdAt: current.createdAt)
            errorMessage = "Не удалось сохранить на сервере: \(error.localizedDescription)"
        }
    }

    func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
