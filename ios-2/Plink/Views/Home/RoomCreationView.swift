
// Plink/Views/Home/RoomCreationView.swift
// PLINK_M11: Beautiful room creation with service carousel

import SwiftUI
import UIKit

// MARK: - Step
enum RoomCreationStep { case service, content, setup, creating }

// MARK: - ServiceCardKind
enum ServiceCardKind { case direct, subscription, other }

// MARK: - Main View
struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: RoomCreationStep = .service
    @State private var selectedService: VideoService? = nil
    @State private var detectedVideo: DetectedVideo? = nil
    @State private var roomName: String = ""
    @State private var isPublic: Bool = true
    @State private var showAuthSheet: Bool = false
    @State private var pendingAuthService: VideoService? = nil
    @State private var isCreating: Bool = false
    @State private var heroOffset: CGFloat = 0

    let onCreate: ((String, VideoService, DetectedVideo?) -> Void)?
    /// M15: полный цикл — мастер сам создаёт комнату по сети
    /// (с приватностью и паролем) и возвращает готовую Room.
    let onRoomCreated: ((Room) -> Void)?

    // M15: модерация и карусель сервисов
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var roomPassword: String = ""
    @State private var serviceFilter: ServicePickerFilter = .all
    @State private var clipboardSuggestion: (url: String, service: VideoService)? = nil
    @State private var recentServices: [VideoService] = RecentServicesStore.recents
    @State private var createErrorMessage: String? = nil

    /// Мастер открыт сразу на «Настройке» по готовой ссылке (карточка буфера на
    /// «Главной»). Шагов «сервис» и «контент» позади нет, поэтому «Назад» в них
    /// уводить не должен — он закрывает мастер.
    private let startedFromLink: Bool

    init(onCreate: ((String, VideoService, DetectedVideo?) -> Void)? = nil) {
        self.onCreate = onCreate
        self.onRoomCreated = nil
        self.startedFromLink = false
    }

    init(onRoomCreated: @escaping (Room) -> Void) {
        self.onCreate = nil
        self.onRoomCreated = onRoomCreated
        self.startedFromLink = false
    }

    /// Открыть мастер сразу на шаге настройки с готовой ссылкой.
    ///
    /// Нужен для карточки «ссылка из буфера» на «Главной»: сервис и видео уже
    /// известны, проходить шаги выбора заново незачем.
    init(
        prefilledLink: String,
        service: VideoService,
        onRoomCreated: @escaping (Room) -> Void
    ) {
        self.onCreate = nil
        self.onRoomCreated = onRoomCreated
        self.startedFromLink = true
        _step = State(initialValue: .setup)
        _selectedService = State(initialValue: service)
        _detectedVideo = State(initialValue: DetectedVideo(
            title: nil,
            embedURL: prefilledLink,
            originalURL: prefilledLink,
            service: service
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Cinema2026.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        switch step {
                        case .service:  serviceStep
                        case .content:  contentStep
                        case .setup:    setupStep
                        case .creating: creatingStep
                        }
                    }
                }

                // Floating back button.
                // Если мастер открыт по готовой ссылке, позади шагов нет —
                // кнопку не показываем совсем, чтобы «Назад» не уводил в выбор
                // контента для сервиса, который пользователь не выбирал.
                // Закрыть мастер можно «Отменой» в шапке.
                if step != .service && !startedFromLink {
                    VStack {
                        Spacer()
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    switch step {
                                    case .content: step = .service
                                    case .setup:   step = .content
                                    default: break
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text(LocalizationManager.shared.string(.rcBack))
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Cinema2026.text)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .plinkGlass(.control, in: Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Cinema2026.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(stepTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                }
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            if let svc = pendingAuthService {
                ServiceAuthSheet(service: svc) {
                    ServiceAuthStore.markAuthorized(svc.serviceType)
                    showAuthSheet = false
                    selectedService = svc
                    withAnimation { step = .content }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .service:  return "Создать комнату"
        case .content:  return selectedService?.title ?? "Выбор видео"
        case .setup:    return "Настройка"
        case .creating: return "Создаём..."
        }
    }

    // MARK: - Service groups
    private var syncableServices: [VideoService] {
        [.youtube, .vk, .rutube]
    }
    private var cinemaServices: [VideoService] {
        [.kinopoisk, .netflix, .okko, .ivi, .disney, .wink, .start, .premier, .kion]
    }
    private var otherServices: [VideoService] {
        [.browser, .customURL]
    }

    // MARK: - Step 1: Service (M15 — карусель с фильтрами)

    /// Все сервисы в порядке показа в карусели.
    private var carouselServices: [VideoService] {
        [.youtube, .vk, .rutube, .kinopoisk, .ivi, .okko, .wink, .start, .premier, .kion, .smotrim, .netflix, .disney]
    }

    private var filteredServices: [VideoService] {
        carouselServices.filter { serviceFilter.matches($0) }
    }

    /// Честная витрина: прямой синх vs «ваш экран» (Netflix/Disney/кино остаются).
    private var worksNowFiltered: [VideoService] {
        filteredServices.filter { $0.deliveryBucket == .worksNow }
    }
    private var yourScreenFiltered: [VideoService] {
        filteredServices.filter { $0.deliveryBucket == .yourScreen }
    }

    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero greeting
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizationManager.shared.string(.rcWhatWatch))
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(Cinema2026.text)
                Text(LocalizationManager.shared.string(.rcPickService))
                    .font(.system(size: 15))
                    .foregroundStyle(Cinema2026.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // M15: ссылка из буфера — мгновенный старт без поиска
            if let clip = clipboardSuggestion {
                ClipboardVideoCard(url: clip.url, service: clip.service) {
                    useClipboardSuggestion(clip)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // M15: недавние сервисы — в один тап
            if !recentServices.isEmpty {
                sectionLabel("НЕДАВНИЕ", subtitle: "Вы недавно смотрели здесь")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentServices, id: \.self) { svc in
                            Button { selectService(svc) } label: {
                                HStack(spacing: 6) {
                                    ServiceLogoView(service: svc, size: 20)
                                    Text(svc.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Cinema2026.text)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Cinema2026.surface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 18)
            }

            // M15: фильтры — российские/зарубежные, бесплатно/подписка
            ServiceFilterChips(filter: $serviceFilter)
                .padding(.bottom, 18)

            // Прямой синхронный поток (YouTube / VK / Rutube / …)
            if !worksNowFiltered.isEmpty {
                sectionLabel(
                    DeliveryBucket.worksNow.sectionTitle,
                    subtitle: DeliveryBucket.worksNow.sectionSubtitle
                )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(worksNowFiltered, id: \.self) { svc in
                            ServiceCarouselCard(service: svc) { selectService(svc) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.bottom, 24)
            }

            // Netflix / Disney / кино — остаются в выборе, режим «ваш экран»
            if !yourScreenFiltered.isEmpty {
                sectionLabel(
                    DeliveryBucket.yourScreen.sectionTitle,
                    subtitle: DeliveryBucket.yourScreen.sectionSubtitle,
                    accent: true
                )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(yourScreenFiltered, id: \.self) { svc in
                            ServiceCarouselCard(service: svc) { selectService(svc) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.bottom, 24)
            }

            if filteredServices.isEmpty {
                Text(LocalizationManager.shared.string(.rcNoServices))
                    .font(.system(size: 14))
                    .foregroundStyle(Cinema2026.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }

            // Section: Other
            sectionLabel("ДРУГОЕ", subtitle: "Любая ссылка или встроенный браузер")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                ForEach(otherServices, id: \.self) { svc in
                    OtherServiceRow(service: svc) { selectService(svc) }
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 60)
        }
        .onAppear {
            recentServices = RecentServicesStore.recents
            refreshClipboardSuggestion()
        }
    }

    private func useClipboardSuggestion(_ clip: (url: String, service: VideoService)) {
        HapticManager.impact(.light)
        selectedService = clip.service
        detectedVideo = DetectedVideo(
            title: nil,
            embedURL: clip.url,
            originalURL: clip.url,
            service: clip.service
        )
        roomName = ""
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = .setup }
    }

    private func refreshClipboardSuggestion() {
        guard UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings else {
            clipboardSuggestion = nil
            return
        }
        guard let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.hasPrefix("http"),
              let svc = VideoService.detect(fromURL: raw) else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = (raw, svc)
    }

    private func selectService(_ svc: VideoService) {
        RecentServicesStore.note(svc)
        if svc.serviceType.requiresAuth && !ServiceAuthStore.hasAccess(to: svc.serviceType) {
            pendingAuthService = svc
            showAuthSheet = true
        } else {
            selectedService = svc
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { step = .content }
        }
    }

    private func sectionLabel(_ title: String, subtitle: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if accent {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Cinema2026.accent)
                }
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(accent ? Cinema2026.accent : Cinema2026.secondary)
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Cinema2026.secondary.opacity(0.8))
        }
    }

    // MARK: - Step 2: Content
    private var contentStep: some View {
        Group {
            if let svc = selectedService {
                // FIX: ServiceBrowserView отдаёт ДВА аргумента (contentURL, title),
                // а не готовый DetectedVideo — собираем модель здесь.
                ServiceBrowserView(service: svc) { contentURL, title in
                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    detectedVideo = DetectedVideo(
                        title: cleanTitle.isEmpty ? nil : cleanTitle,
                        embedURL: contentURL,
                        originalURL: contentURL,
                        service: svc,
                        thumbnailURL: Self.thumbnailURL(for: contentURL, service: svc)
                    )
                    roomName = cleanTitle.isEmpty ? svc.title : cleanTitle
                    withAnimation { step = .setup }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    // MARK: - Step 3: Setup
    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let video = detectedVideo {
                // Video preview
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { img in
                        img.resizable().aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Cinema2026.surface)
                    }
                    .frame(height: 200)
                    .clipped()

                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

                    if let svc = selectedService {
                        ServiceLogoView(service: svc, size: 28)
                            .padding(14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                // Room name
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizationManager.shared.string(.rcRoomName))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                    TextField("Как назвём комнату?", text: $roomName)
                        .font(.system(size: 17))
                        .foregroundStyle(Cinema2026.text)
                        .padding(14)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                }

                // M15: модерация — кто может войти (те же 4 режима, что в комнате)
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizationManager.shared.string(.rcWhoCanJoin))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Cinema2026.secondary)
                    LazyVGrid(columns: [.init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(RoomPrivacy.allCases) { mode in
                            privacyModeCard(mode)
                        }
                    }
                    if privacy == .privateRoom {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Cinema2026.accent)
                            SecureField("Пароль комнаты", text: $roomPassword)
                                .font(.system(size: 15))
                                .foregroundStyle(Cinema2026.text)
                                .textInputAutocapitalization(.never)
                        }
                        .padding(14)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity)
                    }
                }

                if let err = createErrorMessage {
                    Text(err)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }

                // Create button
                Button {
                    createErrorMessage = nil
                    withAnimation { step = .creating }
                    Task { await performCreate() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                        Text(LocalizationManager.shared.string(.rcCreate))
                            .font(.system(size: 17, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [Cinema2026.accent, Cinema2026.accent.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .foregroundStyle(.black)
                    .shadow(color: Cinema2026.accent.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 4: Creating
    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Cinema2026.accent)
            Text(LocalizationManager.shared.string(.rcCreating))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Cinema2026.text)
            Spacer()
        }
        .frame(minHeight: 400)
    }

    // MARK: - M15: карточка режима приватности + сетевое создание

    @ViewBuilder
    private func privacyModeCard(_ mode: RoomPrivacy) -> some View {
        let selected = privacy == mode
        Button {
            HapticManager.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { privacy = mode }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? .black : Cinema2026.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(selected ? Color.white.opacity(0.25) : Cinema2026.accent.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selected ? .black : Cinema2026.text)
                    Text(mode.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(selected ? .black.opacity(0.7) : Cinema2026.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Cinema2026.accent : Cinema2026.surface)
            )
        }
        .buttonStyle(.plain)
    }

    /// Постер для превью на шаге «Настройка». Сейчас надёжно восстанавливается
    /// только для YouTube; остальные сервисы — плейсхолдер (nil).
    private static func thumbnailURL(for rawURL: String, service: VideoService) -> String? {
        guard service == .youtube, let vid = extractYouTubeID(from: rawURL) else { return nil }
        return "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"
    }

    private static func extractYouTubeID(from raw: String) -> String? {
        guard let url = URL(string: raw) else { return nil }
        if PlinkHost.matches(url.host, domain: "youtu.be") {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let v = items.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        if url.path.contains("/embed/") || url.path.contains("/shorts/") {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// M15: полный сетевой цикл создания комнаты с приватностью и паролем.
    @MainActor
    private func performCreate() async {
        let svc = selectedService ?? .youtube
        RecentServicesStore.note(svc)

        // Легаси-путь: экран-обёртка сам создаёт комнату
        guard onRoomCreated != nil else {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onCreate?(roomName, svc, detectedVideo)
            dismiss()
            return
        }

        // Собираем MediaItem из выбранного контента
        var mediaItem: MediaItem? = nil
        if let video = detectedVideo {
            var streamURL = video.embedURL.isEmpty ? video.originalURL : video.embedURL
            var source: MediaItem.MediaSource = .url
            var videoId: String? = nil
            var thumb: String? = nil
            if svc == .youtube,
               let vid = Self.extractYouTubeID(from: video.originalURL) ?? Self.extractYouTubeID(from: video.embedURL) {
                streamURL = "https://www.youtube.com/watch?v=\(vid)"
                source = .youtube
                videoId = vid
                thumb = "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"
            }
            mediaItem = MediaItem(
                id: UUID().uuidString,
                title: roomName.isEmpty ? (video.title ?? svc.title) : roomName,
                artist: nil,
                thumbnailURL: thumb,
                streamURL: streamURL,
                duration: nil,
                mediaType: .video,
                source: source,
                videoId: videoId
            )
        }

        let name = roomName.trimmingCharacters(in: .whitespaces).isEmpty
            ? (detectedVideo?.title ?? "Комната \(svc.title)")
            : roomName

        let request = CreateRoomRequest(
            name: String(name.prefix(80)),
            maxParticipants: 10,
            mediaItem: mediaItem,
            privacy: privacy,
            password: privacy == .privateRoom && !roomPassword.isEmpty ? roomPassword : nil,
            hostName: AuthService.shared.currentUserValue?.username
        )

        do {
            let room = try await RoomService(api: APIClient.shared).createRoom(request)
            HapticManager.roomJoined()
            onRoomCreated?(room)
            dismiss()
        } catch {
            createErrorMessage = "Не удалось создать комнату: \(error.localizedDescription)"
            HapticManager.errorOccurred()
            withAnimation { step = .setup }
        }
    }
}

// MARK: - Direct Service Card (YouTube / VK / Rutube)
struct DirectServiceCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Brand gradient
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [service.accentColor.opacity(0.9), service.accentColor.opacity(0.4), .black.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 210, height: 140)

                // Inner glow
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(service.accentColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 210, height: 140)

                // SYNC badge
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text("SYNC")
                                .font(.system(size: 8, weight: .black))
                                .tracking(1.2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(12)
                    }
                    Spacer()
                }
                .frame(width: 210, height: 140)

                // Bottom info
                HStack(alignment: .bottom, spacing: 10) {
                    ServiceLogoView(service: service, size: 42)
                        .shadow(color: .black.opacity(0.4), radius: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(service.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(14)
            }
            .frame(width: 210, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: service.accentColor.opacity(0.35), radius: 14, x: 0, y: 6)
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

// MARK: - Cinema Service Card (Kinopoisk, Netflix, Okko...)
struct CinemaServiceCard: View {
    let service: VideoService
    let action: () -> Void
    @State private var pressed = false

    private var isAuthorized: Bool {
        ServiceAuthStore.hasAccess(to: service.serviceType)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(service.accentColor.opacity(0.12))
                            .frame(width: 64, height: 64)
                        ServiceLogoView(service: service, size: 44)
                    }

                    Text(service.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // Host badge
                    HStack(spacing: 3) {
                        Image(systemName: isAuthorized ? "checkmark.circle.fill" : "crown.fill")
                            .font(.system(size: 8))
                        Text(isAuthorized ? "Вход" : "Host")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(isAuthorized ? .green : Cinema2026.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isAuthorized ? Color.green : Cinema2026.accent).opacity(0.12),
                        in: Capsule()
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 6)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Cinema2026.surface)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isAuthorized
                                ? LinearGradient(colors: [.green.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [service.accentColor.opacity(0.3), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }

                // Green dot if authorized
                if isAuthorized {
                    Circle().fill(Color.green).frame(width: 8, height: 8).padding(8)
                }
            }
            .scaleEffect(pressed ? 0.94 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
    }
}

// MARK: - Other Service Row (Browser, Custom URL)
struct OtherServiceRow: View {
    let service: VideoService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(service.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    ServiceLogoView(service: service, size: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                    Text(service.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Cinema2026.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Cinema2026.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Service Auth Sheet
struct ServiceAuthSheet: View {
    let service: VideoService
    let onAuthorized: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var webShown: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                // Logo & brand
                ZStack {
                    Circle()
                        .fill(service.accentColor.opacity(0.15))
                        .frame(width: 110, height: 110)
                    ServiceLogoView(service: service, size: 72)
                }

                VStack(spacing: 10) {
                    Text("Войдите в \(service.title)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Cinema2026.text)
                    Text("Чтобы стать Host, необходима подписка \(service.title).\nГости смотрят бесплатно через Plink.")
                        .font(.system(size: 15))
                        .foregroundStyle(Cinema2026.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                // Benefits
                VStack(spacing: 12) {
                    authBenefit(icon: "key.fill", text: "Войдите один раз — сессия сохраняется")
                    authBenefit(icon: "iphone", text: "Чтобы снова войти — откройте Настройки → Сервисы")
                    authBenefit(icon: "person.2.fill", text: "Гостям подписка не нужна")
                }
                .padding(.horizontal, 30)

                Spacer()

                // CTA
                Button {
                    webShown = true
                } label: {
                    HStack(spacing: 10) {
                        ServiceLogoView(service: service, size: 22)
                        Text("Войти через \(service.title)")
                            .font(.system(size: 17, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(colors: [service.accentColor, service.accentColor.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: service.accentColor.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Button("Позже") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Cinema2026.secondary)
                    .padding(.bottom, 30)
            }
            .background(Cinema2026.bg.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $webShown) {
                ServiceBrowserView(service: service) { _, _ in
                    onAuthorized()
                }
            }
        }
    }

    private func authBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.text)
            Spacer()
        }
    }
}
