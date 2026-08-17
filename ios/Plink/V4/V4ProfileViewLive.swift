// Plink/V4/V4ProfileViewLive.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

/// Profile activity presentation. It is intentionally rendered as part of the
/// identity header, never inside settings: activity describes the person, not
/// application configuration.
struct V4MyStatsCard: View {
    let theme: V4Theme
    @State private var profile: UserSocialProfile?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizationManager.shared.string(.vpMyStats))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(theme.accentColor)
                    Text(LocalizationManager.shared.string(.vpActivity))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(V4.ink)
                }
                Spacer()
                if isLoading {
                    ProgressView().tint(theme.accentColor).scaleEffect(0.8)
                        .accessibilityLabel("Загрузка статистики")
                } else {
                    Button {
                        Task { await reload() }
                    } label: {
                        V4GlyphIcon(glyph: .retry, size: 13, weight: .regular)
                            .foregroundStyle(V4.muted)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Обновить статистику")
                }
            }

            // Ошибка сети не должна маскироваться под реальные нули.
            // Пока данных нет, показываем «—»; ноль показывается только когда
            // сервер действительно вернул 0.
            let hours = profile?.watchHoursText ?? "—"
            let films = profile.map { "\($0.filmsWatched)" } ?? "—"
            let friends = profile.map { "\($0.friendsCount)" } ?? "—"
            let rooms = profile.map { "\($0.roomsCreated)" } ?? "—"

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                v4Stat("Часы в Plink", hours)
                v4Stat("Фильмов", films)
                v4Stat("Друзей", friends)
                v4Stat("Комнат создано", rooms)
            }

            if let badges = profile?.badges, !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { code in
                            let b = ProfileBadge.from(code: code)
                            Text(b?.title ?? code)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(V4.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(V4.raised)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(V4.line))
                        }
                    }
                }
                .accessibilityLabel("Достижения")
            } else if !isLoading {
                Text(LocalizationManager.shared.string(.vpAchievementsHint))
                    .font(.system(size: 11))
                    .foregroundStyle(V4.muted)
            }

            if let loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loadError)
                        .font(.system(size: 11))
                        .foregroundStyle(V4.danger)
                    Button("Повторить") { Task { await reload() } }
                        .buttonStyle(.bordered)
                        .tint(theme.accentColor)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await SocialProfileService.fetchMe()
            loadError = nil
        } catch {
            loadError = "Не удалось загрузить статистику. Проверь соединение и повтори."
        }
    }

    private func v4Stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(V4.muted)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(V4.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            LinearGradient(
                colors: [V4.raised.opacity(0.78), V4.raised.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct V4ProfileViewLive: View {
    let theme: V4Theme
    var store: V4ProfileStore?
    @Binding var showAppearance: Bool
    @State private var currentAvatarURL: URL?

    @State private var showPersonalData = false
    @State private var showPrivacy = false
    @State private var showNotifications = false
    @State private var showPlayback = false
    @State private var showHelp = false
    @State private var showBlocked = false
    @State private var showDeleteAccount = false
    @State private var showSafer = false
    @State private var showAdminPanel = false
    @State private var showAvatarPicker = false
    @State private var showPremium = false

    private var isAdmin: Bool { store?.isAdmin == true }
    private var avatarURL: URL? { currentAvatarURL ?? store?.avatarURL }

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                // ── Identity header: avatar, name, badges and activity belong together ──
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                    Button { showAvatarPicker = true } label: {
                        Group {
                            // Prefer local JPEG (instant + survives cache bugs)
                            if let local = store?.localAvatarImage {
                                Image(uiImage: local)
                                    .resizable()
                                    .scaledToFill()
                            } else if let avatarURL {
                                AsyncImage(url: avatarURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 64, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                                    }
                                }
                            } else {
                                V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 64, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.accentColor.opacity(0.5), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сменить аватар")

                    VStack(alignment: .leading, spacing: 3) {
                        // Name — admin gets red color
                        Text(store?.displayName ?? "Загрузка…")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(isAdmin ? Color(red:1,green:0.3,blue:0.4) : V4.ink)

                        if let username = store?.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(V4.muted)
                        }
                        // M34: поделиться профилем (виральная петля)
                        if let username = store?.username, !username.isEmpty,
                           let shareURL = URL(string: "https://plink.app/u/\(username)") {
                            ShareLink(item: shareURL) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Поделиться профилем")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                            }
                            .padding(.top, 2)
                        }
                        // Email — show below username
                        if let email = store?.email, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 12))
                                .foregroundStyle(V4.muted.opacity(0.7))
                        }

                        // Badges row
                        HStack(spacing: 6) {
                            if isAdmin {
                                Text(LocalizationManager.shared.string(.prAdmin))
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(red:0.9,green:0.1,blue:0.2), in: Capsule())
                            }
                            if store?.isPremium == true {
                                Text("PLINK+")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "#A855F7"), in: Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    Button {
                        showPersonalData = true
                    } label: {
                        Image(systemName:"pencil.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.accentColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать профиль")
                    }

                    V4MyStatsCard(theme: theme)
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(V4.surface.opacity(0.82))
                        LinearGradient(
                            colors: [theme.accentColor.opacity(0.14), .clear, V4.raised.opacity(0.24)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(theme.accentColor.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .accessibilityIdentifier("screen.profile")

                // M32: история просмотров
                groupTitle("История просмотров")
                WatchHistorySection()
                    .padding(.bottom, 6)

                // Stats live inside «Личные данные» / pencil — not on this settings list
                groupTitle("Аккаунт")
                VStack(spacing:0) {
                    setting("person","Личные данные","›"){showPersonalData = true}
                    setting("lock.shield","Приватность и безопасность","›"){showPrivacy = true}
                }.groupStyle()

                groupTitle("Подписка Плинк+")
                VStack(spacing:0) {
                    setting("crown.fill","Плинк+ премиум", store?.isPremium == true ? "Активен ›" : "Оформить ›"){showPremium = true}
                }.groupStyle()

                groupTitle("Приложение")
                VStack(spacing:0) {
                    let themeDisplayName = PlinkPlusLiveTheme.resolve(UserDefaults.standard.integer(forKey: "plink.liveTheme"))?.name ?? theme.name
                    setting("circle.lefthalf.filled","Оформление", themeDisplayName + " ›"){showAppearance=true}
                    setting("bell","Уведомления","›"){showNotifications = true}
                    setting("play.fill","Воспроизведение","›"){showPlayback = true}
                    setting("questionmark","Помощь","›"){showHelp = true}
                }.groupStyle()

                if isAdmin {
                    groupTitle("Администрирование")
                    VStack(spacing:0) {
                        setting("shield.lefthalf.filled","Админ-панель","›"){showAdminPanel = true}
                    }.groupStyle()
                }

                groupTitle("Безопасность")
                VStack(spacing:0) {
                    setting("lock.shield.fill","Почему Plink безопаснее","›"){showSafer = true}
                    setting("nosign","Заблокированные","›"){showBlocked = true}
                    setting("xmark","Удалить аккаунт","›",danger:true){showDeleteAccount = true}
                    // Выйти — synchronous, guaranteed
                    Button {
                        AuthService.shared.signOutLocally()
                    } label: {
                        HStack(spacing:11) {
                            Image(systemName: "arrow.right.square.fill").frame(width:30)
                            Text(LocalizationManager.shared.string(.prSignOut)).font(.system(size:13.6,weight:.bold))
                            Spacer()
                            Text("›").font(.system(size:11.52)).foregroundStyle(V4.muted)
                        }
                        .foregroundStyle(V4.danger)
                        .frame(minHeight:48)
                        .overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)}
                    }
                    .buttonStyle(.plain)
                }.groupStyle()
            }.padding(.bottom,96)
        }.foregroundStyle(V4.ink)
        .sheet(isPresented: $showPersonalData, onDismiss: {
            // Reload name/avatar after «Личные данные» save
            Task { await store?.load() }
        }) {
            NavigationStack { PersonalDataView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkProfileDidUpdate)) { note in
            if let user = note.object as? User {
                store?.applyUser(user)
            } else {
                Task { await store?.load() }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacySecurityView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack { NotificationsView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPlayback) {
            NavigationStack { PlaybackSettingsView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHelp) {
            NavigationStack { HelpView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showBlocked) {
            NavigationStack { BlockedUsersView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSafer) {
            PlinkSaferScreen()
        }
        .sheet(isPresented: $showDeleteAccount) {
            NavigationStack { DeleteAccountView() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAdminPanel) {
            AdminRootView().preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(store: store, theme: theme, onAvatarChanged: { url in
                currentAvatarURL = url
            }).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPremium) {
            // M17: единый paywall Plink+ во всём приложении
            PlinkPlusPaywall(trigger: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }
    private func groupTitle(_ s:String)->some View { Text(s.uppercased()).font(.system(size:10.56,weight:.heavy)).tracking(1.1616).foregroundStyle(V4.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.vertical,9) }
    private func setting(_ icon:String,_ title:String,_ trailing:String,danger:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action){ HStack(spacing:11){ Image(systemName:icon).frame(width:30); Text(title).font(.system(size:13.6,weight:.bold)); Spacer(); Text(trailing).font(.system(size:11.52)).foregroundStyle(V4.muted) }.foregroundStyle(danger ? V4.danger : V4.ink).frame(minHeight:48).overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)} }
    }
}

// MARK: - AvatarPickerSheet (PhotosUI + server upload + local persist)

struct AvatarPickerSheet: View {
    var store: V4ProfileStore?
    /// Аудит 26.07.2026: шит рисовался акцентом Cinema2026 — третьей палитрой,
    /// не связанной с темой приложения. Тема приходит от родителя.
    var theme: V4Theme = .electric
    var onAvatarChanged: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var uploadOK = false
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var selectedDefault: String? = nil
    @State private var pendingImage: UIImage?
    @State private var showPhotosPicker = false
    @State private var photosDeniedAlert = false

    private let defaultAvatars = ["avatar_default", "avatar_blue", "avatar_purple"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable().scaledToFill()
                    } else if let local = store?.localAvatarImage {
                        Image(uiImage: local)
                            .resizable().scaledToFill()
                    } else if let avatarURL = store?.avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(V4.surface)
                                .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                        }
                    } else {
                        Circle().fill(V4.surface)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(uploadOK ? Color.green : theme.accentColor, lineWidth: 3))

                if uploadOK {
                    Label("Сохранено на сервере", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }

                Text(LocalizationManager.shared.string(.vpStandard)).font(.system(size: 13, weight: .bold)).foregroundStyle(V4.muted)
                HStack(spacing: 16) {
                    ForEach(defaultAvatars, id: \.self) { name in
                        Button {
                            selectedDefault = name
                            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars")
                                ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
                               let data = try? Data(contentsOf: url),
                               let img = UIImage(data: data) {
                                previewImage = img
                                pendingImage = img
                                uploadOK = false
                                Task { await saveAndUpload(img) }
                            }
                        } label: {
                            presetThumb(name: name)
                        }
                        .buttonStyle(.plain)
                        .disabled(uploading)
                    }
                }

                Rectangle().fill(V4.line).frame(height: 0.5).padding(.horizontal, 24)

                // System iOS photo dialog (if first time) → then PhotosPicker
                Button {
                    Task { await pickFromGallery() }
                } label: {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Text(uploading ? "Сохраняем…" : "Выбрать из галереи")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .disabled(uploading)
                .photosPicker(isPresented: $showPhotosPicker, selection: $photoItem, matching: .images)
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadPhoto(newItem) }
                }
                .alert("Фото недоступны", isPresented: $photosDeniedAlert) {
                    Button("Настройки") { PlinkPermissions.openAppSettings() }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text(LocalizationManager.shared.string(.phPhotoLimited))
                }

                if let err = uploadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Cinema2026.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    Task { await doneTapped() }
                } label: {
                    Text(uploading ? "Сохраняем…" : "Готово")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(uploading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 32)
            .background(Cinema2026.background.ignoresSafeArea())
            .navigationTitle("Аватар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func presetThumb(name: String) -> some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(selectedDefault == name ? theme.accentColor : V4.line, lineWidth: selectedDefault == name ? 3 : 1))
        } else {
            Circle()
                .fill(V4.surface)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.system(size: 20)).foregroundStyle(V4.muted))
        }
    }

    private func doneTapped() async {
        // If user picked something but upload not finished / failed — retry then close
        if let pending = pendingImage, !uploadOK {
            await saveAndUpload(pending)
            if uploadOK { dismiss() }
            return
        }
        dismiss()
    }

    /// 1) If never asked → system iOS permission sheet immediately.
    /// 2) Then always open PhotosPicker (works even after «Не разрешать»).
    private func pickFromGallery() async {
        let access = await PlinkPermissions.preparePhotoPicker()
        switch access {
        case .authorized, .systemPickerOnly:
            // Small yield so the permission sheet can dismiss before PHPicker.
            try? await Task.sleep(nanoseconds: 150_000_000)
            showPhotosPicker = true
        case .blocked:
            photosDeniedAlert = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploading = true
        uploadError = nil
        uploadOK = false
        defer { uploading = false }
        selectedDefault = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadError = "Не удалось загрузить фото"
                return
            }
            guard let image = UIImage(data: data) else {
                uploadError = "Неверный формат изображения"
                return
            }
            let resized = resizeToSquare(image, size: 512)
            previewImage = resized
            pendingImage = resized
            await saveAndUpload(resized)
        } catch {
            uploadError = "Ошибка: \(error.localizedDescription)"
        }
    }

    private func resizeToSquare(_ image: UIImage, size: CGFloat) -> UIImage {
        let originalSize = image.size
        let shortest = min(originalSize.width, originalSize.height)
        let offsetX = (originalSize.width - shortest) / 2
        let offsetY = (originalSize.height - shortest) / 2
        let cropRect = CGRect(x: offsetX, y: offsetY, width: shortest, height: shortest)
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        let cropped = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            cropped.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// Compress + POST /users/me/avatar + local persist via store.applyAvatar
    private func saveAndUpload(_ image: UIImage) async {
        uploading = true
        uploadError = nil
        defer { uploading = false }

        // Always keep local copy first so "Готово" never loses the photo
        var quality: CGFloat = 0.82
        var jpegData = image.jpegData(compressionQuality: quality)
        while let d = jpegData, d.count > 1_800_000, quality > 0.35 {
            quality -= 0.1
            jpegData = image.jpegData(compressionQuality: quality)
        }
        guard let jpegData else {
            uploadError = "Не удалось обработать изображение"
            return
        }

        let base64 = jpegData.base64EncodedString()
        guard let url = URL(string: PlinkConfig.apiURLString + "/users/me/avatar") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        if let token = AuthTokenStore.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            uploadError = "Не авторизован. Войдите заново."
            store?.applyAvatar(image: image, serverURL: nil)
            return
        }

        let body: [String: Any] = ["avatar": "data:image/jpeg;base64,\(base64)"]
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                var serverURL: URL?
                if let respBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let avatarURLString = respBody["avatarURL"] as? String {
                    serverURL = URL(string: avatarURLString)
                }
                if serverURL == nil, let uid = AuthService.shared.currentUserValue?.id {
                    serverURL = URL(string: PlinkConfig.apiURLString + "/users/\(uid)/avatar")
                }
                await MainActor.run {
                    store?.applyAvatar(image: image, serverURL: serverURL)
                    if let busted = store?.avatarURL {
                        onAvatarChanged?(busted)
                    }
                    uploadOK = true
                    pendingImage = nil
                }
            } else if code == 401 {
                uploadError = "Сессия истекла. Войдите заново."
                store?.applyAvatar(image: image, serverURL: nil)
            } else if code == 413 {
                uploadError = "Фото слишком большое. Выберите другое."
            } else {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                uploadError = msg ?? "Ошибка сервера (\(code))"
                store?.applyAvatar(image: image, serverURL: nil)
            }
        } catch {
            uploadError = "Сеть: \(error.localizedDescription)"
            store?.applyAvatar(image: image, serverURL: nil)
        }
    }
}


