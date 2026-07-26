import SwiftUI

// MARK: - RoomSetupView
/// 🔧 NEW: Room setup screen — final step before creating a room.
///
/// Flow: Service → ServiceBrowserView (user picks content) → RoomSetupView
///       → Room created.
///
/// User configures:
///   - Room name (auto-filled from the page title)
///   - Privacy (public / friends-only / private)
///   - Max participants (4 free / 50 premium)
///   - Content URL (from the browser, read-only)
struct RoomSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    let service: VideoService
    let contentURL: String
    let contentTitle: String
    /// 🔧 v33: thumbnail URL from YouTube search — used in MediaItem so
    /// "Смотрят сейчас" + history show cover instead of gradient placeholder.
    let thumbnailURL: String?
    var onRoomCreated: (Room) -> Void

    /// 🔧 FIX H1: RoomService for REST API room creation
    private var roomService: RoomService { RoomService(api: apiClient) }

    @State private var roomName = ""
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var maxParticipants = 4
    @State private var selectedTheme: RoomTheme = .default
    /// 🔧 NEW: Password for locked rooms (shown when privacy = .privateRoom)
    @State private var roomPassword = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let isPremium = PremiumStatusManager.shared.isPremium
    private let freeMaxParticipants = 4
    private let premiumMaxParticipants = 50
    // M13: contextual capacity paywall
    @State private var showCapacityPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                Cinema2026.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // ── Content Preview Card ──
                        contentPreviewCard

                        // ── Room Name Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Название комнаты")
                            VStack(spacing: 0) {
                                TextField("Название комнаты", text: $roomName)
                                    .font(.system(size: 16))
                                    .foregroundColor(Cinema2026.text)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                            }
                        }

                        // ── Privacy Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Приватность")
                            PlinkSettingsCard {
                                ForEach(RoomPrivacy.allCases, id: \.self) { level in
                                    privacyRow(level)
                                    if level != RoomPrivacy.allCases.last {
                                        Divider()
                                            .background(Color.white.opacity(0.06))
                                            .padding(.leading, 56)
                                    }
                                }
                            }

                            // 🔧 NEW: Password field — shown when privacy = .privateRoom (locked)
                            if privacy == .privateRoom {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L.string(.roomPassword))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Cinema2026.secondary)
                                        .tracking(0.5)
                                        .padding(.horizontal, 2)

                                    HStack(spacing: 10) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(Cinema2026.accent)
                                        SecureField("Введите пароль", text: $roomPassword)
                                            .font(.system(size: 16))
                                            .foregroundColor(Cinema2026.text)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                                }
                            }
                        }

                        // ── Participants Section ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Максимум участников")
                            PlinkSettingsCard {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Cinema2026.accent.opacity(0.18))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(maxParticipants) человек")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Cinema2026.text)
                                        Text(isPremium ? "Премиум: до \(premiumMaxParticipants)" : "Бесплатно: до \(freeMaxParticipants)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Cinema2026.secondary)
                                    }

                                    Spacer()

                                    Stepper("", value: $maxParticipants,
                                            in: 2...(isPremium ? premiumMaxParticipants : freeMaxParticipants))
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }

                            // M13: soft upsell at the moment the limit matters
                            if !isPremium {
                                Button {
                                    showCapacityPaywall = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12))
                                        Text("\(L.string(.roomCapacityUpsell)) \(premiumMaxParticipants)")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(Cinema2026.accent)
                                }
                                .sheet(isPresented: $showCapacityPaywall) {
                                    PlinkPlusPaywall(trigger: .capacity)
                                }
                            }
                        }

                        // ── Error ──
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundColor(Cinema2026.danger)
                                .padding(.horizontal, 16)
                        }

                        // ── Room Theme Section (Premium only) ──
                        VStack(alignment: .leading, spacing: 6) {
                            PlinkSectionHeader(text: "Оформление комнаты")

                            if isPremium {
                                PlinkSettingsCard {
                                    ForEach(Array(RoomTheme.allCases.enumerated()), id: \.element) { index, theme in
                                        themeRow(theme)
                                        if index < RoomTheme.allCases.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.06))
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                            } else {
                                // 🔧 Free users see a locked teaser
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Cinema2026.tertiary)
                                        .frame(width: 28, height: 28)
                                        .background(Color.white.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 7))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L.string(.roomCustomThemes))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(Cinema2026.text)
                                        Text(L.string(.roomThemesSubtitle))
                                            .font(.system(size: 12))
                                            .foregroundColor(Cinema2026.secondary)
                                    }

                                    Spacer()

                                    Text("Plink+")
                                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .foregroundColor(Cinema2026.accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Cinema2026.accent.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                )
                            }
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(.top, 8)
                }

                // ── Create Button (bottom) ──
                VStack {
                    Spacer()
                    createButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Новая комната")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Cinema2026.accent)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Auto-fill room name from content title
            if roomName.isEmpty {
                roomName = contentTitle.isEmpty ? "Комната \(service.brandName)" : contentTitle
            }
        }
    }

    // MARK: - Content Preview Card

    private var contentPreviewCard: some View {
        HStack(spacing: 14) {
            // Service logo
            ServiceLogoView(service: service, size: 48)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(contentTitle.isEmpty ? "Выбранный контент" : contentTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Cinema2026.text)
                    .lineLimit(2)
                Text(service.brandName)
                    .font(.system(size: 12))
                    .foregroundColor(Cinema2026.secondary)
                // Read-only URL (small, truncated)
                if let url = URL(string: contentURL) {
                    Text(url.host ?? contentURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Cinema2026.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [Cinema2026.accent.opacity(0.2), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Privacy Row

    @ViewBuilder
    private func privacyRow(_ level: RoomPrivacy) -> some View {
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                privacy = level
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: privacyIcon(level))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(privacyColor(level).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Cinema2026.text)
                    Text(level.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Cinema2026.secondary)
                }

                Spacer()

                // Selection checkmark
                Image(systemName: privacy == level ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(privacy == level ? Cinema2026.accent : Cinema2026.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func privacyIcon(_ level: RoomPrivacy) -> String {
        switch level {
        case .publicRoom:   return "globe"
        case .byLink:       return "link"
        case .privateRoom:  return "lock.fill"
        case .friendsRoom:  return "person.2.fill"
        }
    }

    private func privacyColor(_ level: RoomPrivacy) -> Color {
        switch level {
        case .publicRoom:   return Cinema2026.accent
        case .byLink:       return Cinema2026.accent
        case .privateRoom:  return Cinema2026.accent
        case .friendsRoom:  return Cinema2026.accent
        }
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            createRoom()
        } label: {
            HStack(spacing: 10) {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                }
                Text(isCreating ? "Создание…" : "Создать комнату")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Cinema2026.accentAction)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Cinema2026.accent.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isCreating || roomName.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(roomName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }

    // MARK: - Create Room

    private func createRoom() {
        let name = roomName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "Введите название комнаты"
            return
        }

        isCreating = true
        errorMessage = nil
        HapticManager.impact(.medium)

        // Build MediaItem from the browsed URL
        // 🔧 FIX: set proper `source` based on the selected service — was always `.url`.
        // RoomView uses this to pick playbackMode (YouTube embed URL → WebView,
        // .mp4/.m3u8 → AVPlayer directStream).
        let mediaSource: MediaItem.MediaSource = {
            switch service {
            case .youtube: return .youtube
            case .vk, .rutube, .netflix, .disney: return .url
            case .browser, .customURL: return .url
            case .kinopoisk, .ivi, .okko, .wink, .start, .premier, .smotrim, .kion: return .url
            }
        }()

        // 🔧 v8 (July 2026): For YouTube, extract a DIRECT mp4 stream URL via
        // backend yt-dlp BEFORE creating the room. This bypasses WKWebView
        // entirely — AVPlayer plays the mp4 directly. No more error 153, no
        // more bot check, no more IFrame API cross-origin issues.
        //
        // If extraction fails (yt-dlp can't process this video, network error,
        // etc.), fall back to the embed URL + WebView mode (which still has
        // the 153/bot-check issues, but at least the room can be created and
        // user can retry).
        Task {
            //
            // the direct stream URL from YouTube's HTML. The URL is then
            //
            // If extraction fails (DRM, age-restricted, timeout), we fall back
            // to WebView mode (.youtube source) — the old WKWebView approach.
            let finalStreamURL: String
            let finalSource: MediaItem.MediaSource
            let finalDuration: TimeInterval?

            if service == .youtube {
                let videoId = Self.extractYouTubeVideoID(from: contentURL) ?? ""
                guard !videoId.isEmpty else {
                    await MainActor.run {
                        errorMessage = "Не удалось извлечь ID видео из ссылки"
                    }
                    return
                }
                // PATCH 26: use clean video ID as streamURL, not full URL with tracking params
                finalStreamURL = "https://www.youtube.com/watch?v=\(videoId)"
                finalSource = .youtube
                finalDuration = nil
            } else {
                finalStreamURL = contentURL
                finalSource = mediaSource
                finalDuration = nil
            }

            let finalTitle = contentTitle.isEmpty ? name : contentTitle

            // 🔧 v33: determine thumbnail URL.
            // Priority: 1) thumbnailURL from YouTube search, 2) YouTube fallback by video ID,
            // 3) nil (non-YouTube services — gradient placeholder will show).
            let finalThumbnailURL: String?
            if let thumb = thumbnailURL, !thumb.isEmpty {
                finalThumbnailURL = thumb
            } else if service == .youtube {
                // Fallback: YouTube provides thumbnails at predictable URLs
                let videoId = Self.extractYouTubeVideoID(from: contentURL) ?? ""
                if !videoId.isEmpty {
                    finalThumbnailURL = "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg"
                } else {
                    finalThumbnailURL = nil
                }
            } else {
                finalThumbnailURL = nil
            }

            // 🔧 v97: Save videoId for server-side extraction
            let savedVideoId: String?
            if service == .youtube {
                savedVideoId = Self.extractYouTubeVideoID(from: contentURL)
            } else {
                savedVideoId = nil
            }

            let mediaItem = MediaItem(
                id: UUID().uuidString,
                title: finalTitle,
                artist: nil,
                thumbnailURL: finalThumbnailURL,
                streamURL: finalStreamURL,
                duration: finalDuration,
                mediaType: .video,
                source: finalSource,
                videoId: savedVideoId
            )

            do {
                // 🔧 FIX: save selected theme to PremiumStatusManager so RoomView
                // can apply chatBackground + playerBorder.
                PremiumStatusManager.shared.setRoomTheme(selectedTheme)

                let request = CreateRoomRequest(
                    name: name,
                    maxParticipants: maxParticipants,
                    mediaItem: mediaItem,
                    privacy: privacy,
                    password: privacy == .privateRoom && !roomPassword.isEmpty ? roomPassword : nil,
                    hostName: AuthService(api: apiClient).currentUserValue?.username
                )
                let room = try await roomService.createRoom(request)
                await MainActor.run {
                    isCreating = false
                    HapticManager.roomJoined()
                    onRoomCreated(room)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Не удалось создать комнату: \(error.localizedDescription)"
                    HapticManager.impact(.heavy)
                }
            }
        }
    }

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    // MARK: - Theme Row

    @ViewBuilder
    private func themeRow(_ theme: RoomTheme) -> some View {
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTheme = theme
            }
        } label: {
            HStack(spacing: 12) {
                // Theme preview swatch
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.chatBackground)
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(theme.playerBorderColor.opacity(0.5), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Cinema2026.text)
                    if theme.hasPlayerBorder {
                        Text(L.string(.roomWithTheme))
                            .font(.system(size: 12))
                            .foregroundColor(Cinema2026.secondary)
                    } else {
                        Text(L.string(.roomStandardTheme))
                            .font(.system(size: 12))
                            .foregroundColor(Cinema2026.secondary)
                    }
                }

                Spacer()

                Image(systemName: selectedTheme == theme ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selectedTheme == theme ? Cinema2026.accent : Cinema2026.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - YouTube Video ID Extraction

    /// 🔧 v29 (July 2026): Properly extract video ID from any YouTube URL format.
    ///
    /// Supports:
    ///   - https://www.youtube.com/watch?v=VIDEO_ID
    ///   - https://m.youtube.com/watch?v=VIDEO_ID&feature=shared
    ///   - https://youtu.be/VIDEO_ID?si=...
    ///   - https://www.youtube.com/embed/VIDEO_ID
    ///   - https://www.youtube-nocookie.com/embed/VIDEO_ID
    ///   - https://www.youtube.com/shorts/VIDEO_ID
    ///
    /// Returns nil if the URL doesn't match any known YouTube format.
    private static func extractYouTubeVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let host = url.host?.lowercased() ?? ""
        guard host.contains("youtube.com") || host.contains("youtu.be") || host.contains("youtube-nocookie.com") else {
            return nil
        }

        // Format 1: youtube.com/watch?v=VIDEO_ID (also m.youtube.com)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoId = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoId.isEmpty {
            return videoId
        }

        // Format 2: youtu.be/VIDEO_ID or youtube.com/embed/VIDEO_ID or /shorts/VIDEO_ID
        let pathSegments = url.path.split(separator: "/").map(String.init)
        if !pathSegments.isEmpty {
            let lastSegment = pathSegments.last!
            // For /embed/VIDEO_ID and /shorts/VIDEO_ID → last segment IS the video ID
            // For youtu.be/VIDEO_ID → last segment IS the video ID
            // For /watch → last segment is "watch" (not a video ID), skip
            if lastSegment != "watch" && lastSegment.count >= 6 && lastSegment.count <= 20 {
                // YouTube video IDs are 11 chars, but allow some flexibility
                return lastSegment
            }
        }

        return nil
    }
}
