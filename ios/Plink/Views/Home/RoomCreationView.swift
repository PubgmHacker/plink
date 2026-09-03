
// Plink/Views/Home/RoomCreationView.swift
// Beautiful room creation with service carousel

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
    /// Полный цикл — мастер сам создаёт комнату по сети
    /// (с приватностью и паролем) и возвращает готовую Room.
    let onRoomCreated: ((Room) -> Void)?

    // Модерация и карусель сервисов
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var roomPassword: String = ""
    @State private var serviceFilter: ServicePickerFilter = .all
    @State private var clipboardSuggestion: (url: String, service: VideoService)? = nil
    @State private var recentServices: [VideoService] = RecentServicesStore.recents
    @State private var createErrorMessage: String? = nil
    @State private var customURLDraft = ""
    @State private var unavailableService: VideoService?

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
        #if DEBUG
        if let debug = Self.debugStart {
            _step = State(initialValue: .content)
            _selectedService = State(initialValue: debug.service)
        }
        #endif
    }

    #if DEBUG
    /// Design preview: `-plink.designcreate youtube|rutube|vk[.browse]` opens
    /// the wizard on the content step of that service; `.browse` also opens
    /// the catalogue. Simulator screenshots without taps. Debug builds only.
    struct DebugStart {
        let service: VideoService
        let openBrowser: Bool
    }

    static let debugStart: DebugStart? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-plink.designcreate"), args.indices.contains(i + 1) else {
            return nil
        }
        let parts = args[i + 1].split(separator: ".").map(String.init)
        guard let raw = parts.first, let service = VideoService(rawValue: raw) else { return nil }
        return DebugStart(service: service, openBrowser: parts.dropFirst().contains("browse"))
    }()
    #endif

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
                ToolbarItem(placement: .principal) {
                    Text(stepTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Cinema2026.text)
                }
                V4SheetCloseToolbarItem { dismiss() }
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            if let svc = pendingAuthService {
                ServiceAuthSheet(service: svc) { contentURL, title in
                    ServiceAuthStore.markAuthorized(svc.serviceType)
                    showAuthSheet = false
                    selectedService = svc
                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !contentURL.isEmpty else {
                        withAnimation { step = .content }
                        return
                    }
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
            }
        }
        .alert(
            "Сервис пока готовится",
            isPresented: Binding(
                get: { unavailableService != nil },
                set: { if !$0 { unavailableService = nil } }
            ),
            presenting: unavailableService
        ) { _ in
            Button("Понятно", role: .cancel) { unavailableService = nil }
        } message: { service in
            Text("Поиск и просмотр в \(service.brandName) появятся в следующем обновлении.")
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

    /// Честная витрина: открытое всем vs то, что живёт по своей подписке.
    private var worksNowFiltered: [VideoService] {
        filteredServices.filter { $0.isAvailableInBeta }
    }
    private var subscriptionFiltered: [VideoService] {
        filteredServices.filter { !$0.isAvailableInBeta }
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

            // Ссылка из буфера — мгновенный старт без поиска
            if let clip = clipboardSuggestion {
                ClipboardVideoCard(url: clip.url, service: clip.service) {
                    useClipboardSuggestion(clip)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            // Недавние сервисы — в один тап
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

            // Фильтры — российские/зарубежные, бесплатно/подписка
            ServiceFilterChips(filter: $serviceFilter)
                .padding(.bottom, 18)

            // First release: YouTube, RuTube and VK Видео (VideoService.isAvailableInBeta).
            if !worksNowFiltered.isEmpty {
                sectionLabel(
                    "МОЖНО СМОТРЕТЬ СЕЙЧАС",
                    subtitle: "Выберите видео — Plink синхронизирует плеер в комнате"
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

            // Остальные провайдеры остаются в каталоге как roadmap, но не
            // обещают создание комнаты до готовности собственного адаптера.
            if !subscriptionFiltered.isEmpty {
                sectionLabel(
                    "СКОРО",
                    subtitle: "Подключаем официальные плееры сервисов",
                    accent: false
                )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(subscriptionFiltered, id: \.self) { svc in
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
        .task { await revalidateCinemaSessions() }
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

    /// Протухшие сессии кинотеатров снимаются до того, как карточки
    /// покажут «Вы вошли» и пустят в каталог без входа.
    private func revalidateCinemaSessions() async {
        if !(await LinkedExternalAccount.revalidateConnected()).isEmpty {
            recentServices = RecentServicesStore.recents
        }
    }

    private func selectService(_ svc: VideoService) {
        guard svc.isAvailableInBeta else {
            HapticManager.impact(.light)
            unavailableService = svc
            return
        }
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
            if selectedService == .customURL {
                customURLStep
            } else if let svc = selectedService {
                // Search (YouTube, RuTube), pasted link, or the service catalogue
                // opened full screen. The browser used to sit inline in this
                // ScrollView, where a WKWebView gets no height and rendered as
                // a black screen on device.
                BetaVideoSearchView(service: svc) { video in
                    detectedVideo = video
                    let cleanTitle = video.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    roomName = cleanTitle.isEmpty ? svc.title : cleanTitle
                    withAnimation { step = .setup }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private var customURLStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Прямая ссылка")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Cinema2026.text)
            Text("mp4, m3u8 или страница с плеером. Ссылка на поиск не подойдёт.")
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
            TextField("https://…", text: $customURLDraft)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .padding(14)
                .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Cinema2026.text)
            Button {
                let raw = customURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard raw.hasPrefix("http"), URL(string: raw) != nil else { return }
                detectedVideo = DetectedVideo(
                    title: nil,
                    embedURL: raw,
                    originalURL: raw,
                    service: .customURL
                )
                roomName = "Своя ссылка"
                withAnimation { step = .setup }
            } label: {
                Text("Далее")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!customURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http"))
        }
        .padding(20)
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

                // Модерация — кто может войти (те же 4 режима, что в комнате)
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
                    guard !isCreating, detectedVideo != nil else { return }
                    createErrorMessage = nil
                    isCreating = true
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
                    .foregroundStyle(V4.accentInk)
                    .shadow(color: Cinema2026.accent.opacity(0.4), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(isCreating || detectedVideo == nil)
                .opacity(isCreating || detectedVideo == nil ? 0.55 : 1)
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

    // MARK: - Карточка режима приватности + сетевое создание

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

    /// Постер для превью на шаге «Настройка». Для beta-сервисов восстанавливаем
    /// его из устойчивого публичного URL, если выдача не принесла thumbnail.
    fileprivate static func thumbnailURL(for rawURL: String, service: VideoService) -> String? {
        switch service {
        case .youtube:
            guard let vid = RoomCreateMedia.extractYouTubeID(from: rawURL) else { return nil }
            return "https://img.youtube.com/vi/\(vid)/hqdefault.jpg"
        case .rutube:
            guard let id = RoomCreateMedia.extractRutubeVideoId(from: rawURL) else { return nil }
            return "https://pic.rutubelist.ru/video/\(id.prefix(2))/\(id)/poster.jpg"
        default:
            return nil
        }
    }

    /// Полный сетевой цикл создания комнаты с приватностью и паролем.
    @MainActor
    private func performCreate() async {
        let svc = selectedService ?? .youtube
        guard svc.isAvailableInBeta, let video = detectedVideo else {
            isCreating = false
            createErrorMessage = "Выберите видео из доступного сервиса."
            withAnimation { step = .setup }
            return
        }
        // The button sets this before launching the task; this guard also
        // protects callers that invoke performCreate from a legacy path.
        RecentServicesStore.note(svc)

        // Легаси-путь: экран-обёртка сам создаёт комнату
        guard onRoomCreated != nil else {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onCreate?(roomName, svc, video)
            isCreating = false
            dismiss()
            return
        }

        // Собираем MediaItem из выбранного контента
        let mediaItem = RoomCreateMedia.mediaItem(service: svc, video: video, roomName: roomName)

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
            createErrorMessage = "Не удалось создать комнату. Проверьте соединение и попробуйте ещё раз."
            HapticManager.errorOccurred()
            withAnimation { step = .setup }
        }
        isCreating = false
    }
}

// MARK: - Beta Video Search
/// Content step for the services shipping in the first release.
///
///   • YouTube, RuTube — keyless search through the backend, plus a pasted link
///     and the service catalogue as fallback.
///   • VK Видео — there is no keyless search API, so the step opens the
///     vkvideo.ru catalogue full screen right away; a pasted link works too.
///
/// The catalogue browser is always a full-screen cover: inline in a ScrollView
/// a WKWebView received no height and rendered as a black strip.
struct BetaVideoSearchView: View {
    let service: VideoService
    let onSelect: (DetectedVideo) -> Void

    @State private var query = ""
    @State private var results: [V4SearchResult] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var showBrowser = false
    @State private var linkDraft = ""
    @State private var linkRejected = false
    @State private var didAutoOpenBrowser = false

    /// Keyless search exists for YouTube and RuTube only (backend
    /// /search/videos). VK needs a service token the product does not ship.
    private var provider: V4ClipSearch.Provider? {
        switch service {
        case .youtube: return .youtube
        case .rutube: return .rutube
        default: return nil
        }
    }

    private var supportsSearch: Bool { provider != nil }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if supportsSearch {
                    searchField
                    if !results.isEmpty {
                        resultsList
                    } else if didSearch && !isSearching {
                        emptySearchState
                    } else if !isSearching {
                        hintState
                    }
                } else {
                    catalogueHero
                }

                linkField

                if supportsSearch {
                    catalogueButton
                }
            }
            .padding(.bottom, 36)
        }
        .background(V4.canvas)
        .scrollDismissesKeyboard(.interactively)
        .task(id: query) { await runSearch() }
        .task { await autoOpenBrowserIfNeeded() }
        .fullScreenCover(isPresented: $showBrowser) {
            ServiceBrowserView(service: service) { url, title in
                showBrowser = false
                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let picked: DetectedVideo
                if let selectedURL = URL(string: url),
                   let detected = VideoService.detectVideoURL(
                        selectedURL,
                        for: service,
                        title: cleanTitle.isEmpty ? nil : cleanTitle
                   ) {
                    picked = detected
                } else {
                    // Catalogue pages without an id (cinema services) are the
                    // content themselves — the room player opens the page.
                    picked = DetectedVideo(
                        title: cleanTitle.isEmpty ? nil : cleanTitle,
                        embedURL: url,
                        originalURL: url,
                        service: service
                    )
                }
                onSelect(withThumbnail(picked))
            }
            .preferredColorScheme(.dark)
        }
        .accessibilityIdentifier("room.videoSearch.\(service.rawValue)")
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Выберите видео")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(V4.ink)
            HStack(spacing: 7) {
                ServiceLogoView(service: service, size: 18)
                Text(service.brandName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(V4.muted)
                Text("·")
                    .foregroundStyle(V4.muted.opacity(0.6))
                Text(supportsSearch ? "поиск без входа" : "каталог без входа")
                    .font(.system(size: 13))
                    .foregroundStyle(V4.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.muted)
            TextField("Название фильма или сериала", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(V4.ink)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    didSearch = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(V4.muted)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .plinkGlass(.control, cornerRadius: 18, interactive: true)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Результаты")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            LazyVStack(spacing: 8) {
                ForEach(results) { item in
                    resultRow(item)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// VK: the catalogue is the only way to pick — say so and give one big
    /// button. The browser also opens by itself on the first appearance.
    private var catalogueHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(service.accentColor.opacity(0.18))
                        .frame(width: 52, height: 52)
                    ServiceLogoView(service: service, size: 30)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ролик выбирается в каталоге")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    Text("Найдите видео на сайте и откройте его — Plink подхватит ссылку и вернёт вас сюда.")
                        .font(.system(size: 13))
                        .foregroundStyle(V4.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                HapticManager.impact(.light)
                showBrowser = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "safari.fill")
                    Text("Открыть \(service.brandName)")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(V4.accentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Выбрать видео на сайте сервиса")
        }
        .padding(16)
        .background(V4.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(supportsSearch ? "Или вставьте ссылку" : "Уже есть ссылка?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.muted)
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.muted)
                TextField("https://…", text: $linkDraft)
                    .font(.system(size: 15))
                    .foregroundStyle(V4.ink)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(useLink)
                    .onChange(of: linkDraft) { linkRejected = false }
                if !linkDraft.isEmpty {
                    Button {
                        useLink()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Cinema2026.accent)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Открыть ссылку")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .plinkGlass(.control, cornerRadius: 16, interactive: true)
            if linkRejected {
                Text("Это не ссылка на видео YouTube, RuTube или VK Видео.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var catalogueButton: some View {
        Button {
            HapticManager.impact(.light)
            showBrowser = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                Text("Открыть каталог \(service.brandName)")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(V4.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .plinkGlass(.control, cornerRadius: 16, interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .accessibilityHint("Выбрать видео на сайте сервиса")
    }

    private var hintState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Начните с названия")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.ink)
            Text("Или откройте каталог и выберите ролик там.")
                .font(.system(size: 14))
                .foregroundStyle(V4.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var emptySearchState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ничего не нашли")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.ink)
            Text("Проверьте название или откройте каталог \(service.brandName).")
                .font(.system(size: 14))
                .foregroundStyle(V4.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func resultRow(_ item: V4SearchResult) -> some View {
        Button {
            guard let detected = detectedVideo(for: item) else { return }
            HapticManager.impact(.light)
            onSelect(detected)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let artworkURL = item.artworkURL {
                        AsyncImage(url: artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.06)
                        }
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
                .frame(width: 104, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(service.brandName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(V4.muted)
                        if !item.subtitle.isEmpty {
                            Text("·")
                                .foregroundStyle(V4.muted.opacity(0.6))
                            Text(item.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(V4.muted)
                                .lineLimit(1)
                        }
                        if let duration = item.duration {
                            Text("· \(duration)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(V4.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }
            .padding(10)
            .background(V4.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 80)
        .accessibilityLabel("\(item.title), \(service.brandName)")
        .accessibilityHint("Выбрать видео для новой комнаты")
    }

    // MARK: Actions

    /// A pasted link may belong to another first-release service (a RuTube
    /// link on the YouTube step) — accept whichever it is, if it ships now.
    private func useLink() {
        let raw = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let target = VideoService.detect(fromURL: raw) ?? service
        guard raw.hasPrefix("http"),
              let url = URL(string: raw),
              target.isAvailableInBeta,
              let detected = VideoService.detectVideoURL(url, for: target, title: nil) else {
            linkRejected = true
            HapticManager.notification(.warning)
            return
        }
        linkRejected = false
        HapticManager.impact(.light)
        onSelect(withThumbnail(detected))
    }

    /// VK has no in-app search: jump straight into the catalogue. The wizard
    /// sheet needs a beat to settle or SwiftUI drops the nested presentation.
    private func autoOpenBrowserIfNeeded() async {
        guard !didAutoOpenBrowser else { return }
        didAutoOpenBrowser = true
        var shouldOpen = !supportsSearch
        #if DEBUG
        if RoomCreationView.debugStart?.openBrowser == true { shouldOpen = true }
        #endif
        guard shouldOpen else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        showBrowser = true
    }

    private func withThumbnail(_ video: DetectedVideo) -> DetectedVideo {
        guard video.thumbnailURL == nil else { return video }
        return DetectedVideo(
            title: video.title,
            embedURL: video.embedURL,
            originalURL: video.originalURL,
            service: video.service,
            thumbnailURL: RoomCreationView.thumbnailURL(for: video.originalURL, service: video.service)
        )
    }

    private func detectedVideo(for item: V4SearchResult) -> DetectedVideo? {
        switch service {
        case .youtube:
            guard item.id.count == 11 else { return nil }
            return DetectedVideo(
                title: item.title,
                embedURL: "https://www.youtube.com/embed/\(item.id)",
                originalURL: item.watchURL,
                service: .youtube,
                thumbnailURL: item.artworkURL?.absoluteString
            )
        case .rutube:
            guard let id = RoomCreateMedia.extractRutubeVideoId(from: item.watchURL) else { return nil }
            return DetectedVideo(
                title: item.title,
                embedURL: "https://rutube.ru/play/embed/\(id)",
                originalURL: item.watchURL,
                service: .rutube,
                thumbnailURL: item.artworkURL?.absoluteString
            )
        default:
            return nil
        }
    }

    private func runSearch() async {
        guard let provider else { return }
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else {
            results = []
            didSearch = false
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        isSearching = true
        let found = await V4ClipSearch.search(value, limit: 20, provider: provider)
        guard !Task.isCancelled else { return }
        results = found.filter { $0.isSelectable && detectedVideo(for: $0) != nil }
        isSearching = false
        didSearch = true
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
    /// (адрес контента, заголовок страницы) — пусто, если вход был без выбора.
    let onAuthorized: (String, String) -> Void
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
                    Text("В комнате откроется плеер \(service.title). Каждый смотрит в своём аккаунте — Plink синхронизирует время.")
                        .font(.system(size: 15))
                        .foregroundStyle(Cinema2026.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                VStack(spacing: 12) {
                    authBenefit(icon: "key.fill", text: "Вход один раз — сессия остаётся на этом iPhone")
                    authBenefit(icon: "gearshape.fill", text: "Сменить аккаунт: Настройки → Кинотеатры")
                    authBenefit(icon: "person.2.fill", text: "Подписка \(service.title) нужна каждому участнику")
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

                Button("Позже") { dismiss() }  // без входа мастер остаётся на выборе сервиса
                    .font(.system(size: 15))
                    .foregroundStyle(Cinema2026.secondary)
                    .padding(.bottom, 30)
            }
            .background(Cinema2026.bg.ignoresSafeArea())
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
            }
            .fullScreenCover(isPresented: $webShown) {
                // The catalogue doubles as the sign-in page. The selected title
                // travels with the URL so the film is not searched for twice.
                ServiceBrowserView(service: service) { contentURL, title in
                    webShown = false
                    onAuthorized(contentURL, title)
                }
                .preferredColorScheme(.dark)
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
