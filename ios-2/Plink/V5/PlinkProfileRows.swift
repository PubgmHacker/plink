//
//  PlinkProfileRows.swift
//  Profile settings sheets — polished V4 Cinema UI
//

import SwiftUI

// MARK: - Shared settings chrome

private enum SettingsUI {
    static let cardRadius: CGFloat = 16
    static let iconSize: CGFloat = 32
}

/// Full-screen settings scaffold used by all profile sheets.
private struct SettingsScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Soft layered background (not pure empty black)
            LinearGradient(
                colors: [
                    Color(hex: 0x0B1018),
                    Color(hex: 0x0A0D12),
                    Color(hex: 0x0E1520),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(V4.accent.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: 120, y: -180)

            Circle()
                .fill(Color(hex: 0x6366F1).opacity(0.06))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: -140, y: 320)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(V4.ink)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(V4.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)

                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(V4.muted)
                        .frame(width: 32, height: 32)
                        .background(V4.surface.opacity(0.9), in: Circle())
                        .overlay(Circle().stroke(V4.line))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SettingsSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(V4.muted)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(V4.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: SettingsUI.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUI.cardRadius, style: .continuous)
                .stroke(V4.line, lineWidth: 1)
        )
    }
}

private struct SettingsIconBadge: View {
    let systemName: String
    var color: Color = V4.accent
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.16))
            .frame(width: SettingsUI.iconSize, height: SettingsUI.iconSize)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = V4.accent
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemName: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? V4.ink : V4.muted)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(V4.accent)
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.55)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
        }
    }
}

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    var value: String
    var iconColor: Color = V4.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconBadge(systemName: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(V4.muted)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V4.ink)
                    .lineLimit(2)
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
        }
    }
}

private struct SettingsNavRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = V4.accent
    var trailing: String = "›"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SettingsIconBadge(systemName: icon, color: iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(V4.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                }
                Spacer()
                Text(trailing)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
        }
    }
}

private struct SettingsChoiceRow: View {
    let title: String
    let options: [(String, String)] // id, label
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            HStack(spacing: 8) {
                ForEach(options, id: \.0) { id, label in
                    let selected = selection == id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = id }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? V4.accentInk : V4.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(selected ? V4.accent : V4.raised.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(V4.line).frame(height: 1)
        }
    }
}

private struct SettingsPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(V4.accentInk) }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(V4.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [V4.accent, Color(hex: 0x26D9A4)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - PersonalDataView

internal struct PersonalDataView: View {
    @State private var displayName: String = ""
    @State private var nickname: String = ""
    @State private var email: String = ""
    @State private var accountID: String = ""
    @State private var copied = false
    @State private var saving = false
    @State private var saveMessage: String?

    var body: some View {
        SettingsScaffold(
            title: "Личные данные",
            subtitle: "Профиль, статистика и идентификатор аккаунта"
        ) {
            V4MyStatsCard()

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Профиль")
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizationManager.shared.string(.pxDisplayName))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        TextField("Как тебя видят друзья", text: $displayName)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 10)
                            .foregroundStyle(V4.ink)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(V4.line).frame(height: 1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("@username")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        TextField("уникальный_ник", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .foregroundStyle(V4.ink)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Аккаунт")
                SettingsCard {
                    SettingsInfoRow(icon: "envelope.fill", title: "Email", value: email.isEmpty ? "—" : email)
                    SettingsInfoRow(
                        icon: "number",
                        title: "Account ID",
                        value: accountID.isEmpty ? "—" : accountID,
                        actionTitle: copied ? "Скопировано" : "Копировать"
                    ) {
                        UIPasteboard.general.string = accountID
                        withAnimation { copied = true }
                    }
                }
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            SettingsPrimaryButton(title: "Сохранить", isLoading: saving) {
                Task { await save() }
            }
            .padding(.top, 4)
        }
        .onAppear {
            if let u = AuthService.shared.currentUserValue {
                displayName = u.displayName ?? u.username
                nickname = u.username
                email = u.email
                accountID = u.id
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }

        // Ensure API client has JWT (PersonalData may open without EnvironmentObject)
        if APIClient.shared.authToken == nil {
            APIClient.shared.authToken = KeychainHelper.read(for: "rave_auth_token")
                ?? AuthService.shared.authToken
        }
        guard APIClient.shared.authToken != nil else {
            saveMessage = "Не авторизован — войдите снова"
            return
        }

        let nameToSave = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameToSave = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")

        do {
            // Only send displayName if set; username only if changed & non-empty
            let current = AuthService.shared.currentUserValue
            let usernameArg: String? = {
                guard !usernameToSave.isEmpty else { return nil }
                if usernameToSave == current?.username { return nil }
                return usernameToSave
            }()

            let user = try await AuthService.shared.updateProfile(
                username: usernameArg,
                avatarURL: nil,
                displayName: nameToSave, // empty string clears on backend
                coverURL: nil
            )
            AuthService.shared.updateCachedUser(user)
            // Reflect saved values in the form
            displayName = user.displayName ?? user.username
            nickname = user.username
            saveMessage = "Сохранено"
            HapticManager.impact(.medium)
        } catch {
            saveMessage = "Не удалось сохранить: \(error.localizedDescription)"
            HapticManager.errorOccurred()
        }
    }
}

// MARK: - PrivacySecurityView

internal struct PrivacySecurityView: View {
    @AppStorage("privacy_invite") private var inviteRaw: String = InvitePermission.friendsOnly.rawValue
    @AppStorage("privacy_discoverable") private var discoverable = true
    @AppStorage("privacy_online_status") private var showOnlineStatus = true
    @AppStorage("privacy_dm_from") private var dmFromFriendsOnly = true
    @State private var twoFAEnabled = false
    @State private var showSessions = false

    private var inviteBinding: Binding<String> {
        Binding(get: { inviteRaw }, set: { inviteRaw = $0 })
    }

    var body: some View {
        SettingsScaffold(
            title: "Приватность",
            subtitle: "Кто может тебя находить, приглашать и писать"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Приватность")
                SettingsCard {
                    SettingsChoiceRow(
                        title: "Кто может приглашать в комнату",
                        options: [
                            (InvitePermission.everyone.rawValue, "Все"),
                            (InvitePermission.friendsOnly.rawValue, "Друзья"),
                            (InvitePermission.noOne.rawValue, "Никто"),
                        ],
                        selection: inviteBinding
                    )
                    SettingsToggleRow(
                        icon: "magnifyingglass",
                        title: "Виден в поиске",
                        subtitle: "Другие могут найти тебя по @username",
                        isOn: $discoverable
                    )
                    SettingsToggleRow(
                        icon: "circle.fill",
                        title: "Онлайн-статус",
                        subtitle: "Показывать «в сети» друзьям",
                        iconColor: Color(hex: 0x22C55E),
                        isOn: $showOnlineStatus
                    )
                    SettingsToggleRow(
                        icon: "bubble.left.fill",
                        title: "ЛС только от друзей",
                        subtitle: "Сообщения от незнакомцев скрыты",
                        isOn: $dmFromFriendsOnly
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Безопасность")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "lock.shield.fill",
                        title: "Двухфакторная защита",
                        subtitle: twoFAEnabled ? "Включена" : "Скоро · пока локальный переключатель",
                        iconColor: Color(hex: 0xA855F7),
                        isOn: $twoFAEnabled
                    )
                    SettingsNavRow(
                        icon: "laptopcomputer.and.iphone",
                        title: "Активные сессии",
                        subtitle: "Устройства, где выполнен вход",
                        iconColor: Color(hex: 0x3B82F6)
                    ) {
                        showSessions = true
                    }
                    SettingsNavRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Выйти на этом устройстве",
                        subtitle: "Потребуется войти снова",
                        iconColor: V4.danger
                    ) {
                        AuthService.shared.signOutLocally()
                    }
                }
            }

            infoBanner(
                icon: "shield.checkered",
                text: "Plink не продаёт личные данные. Жалобы и блокировки работают в чате комнаты."
            )
        }
        .sheet(isPresented: $showSessions) {
            NavigationStack {
                ActiveSessionsView(sessions: [
                    ActiveSession(
                        id: "1",
                        device: "Этот iPhone",
                        location: nil,
                        lastSeen: Date(),
                        isCurrent: true
                    ),
                ])
            }
            .preferredColorScheme(.dark)
        }
    }
}

internal enum InvitePermission: String, CaseIterable, Codable {
    case everyone, friendsOnly, noOne
}

struct ActiveSessionsView: View {
    let sessions: [ActiveSession]

    var body: some View {
        SettingsScaffold(title: "Сессии", subtitle: "Где открыт твой аккаунт") {
            SettingsCard {
                if sessions.isEmpty {
                    Text(LocalizationManager.shared.string(.pxNoSessions))
                        .font(.subheadline)
                        .foregroundStyle(V4.muted)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(sessions) { s in
                        SettingsInfoRow(
                            icon: "iphone",
                            title: s.device,
                            value: s.isCurrent
                                ? "Это устройство · \(s.lastSeen.formatted(.relative(presentation: .named)))"
                                : "Активна · \(s.lastSeen.formatted(.relative(presentation: .named)))"
                        )
                    }
                }
            }
        }
    }
}

// MARK: - PlaybackSettingsView

internal struct PlaybackSettingsView: View {
    @AppStorage("playback_autoplay_next") private var autoplayNext = false
    @AppStorage("playback_cellular_quality") private var cellularQuality = CellularQuality.auto.rawValue
    @AppStorage("playback_subtitles") private var subtitlesByDefault = false
    @AppStorage("playback_pip") private var pipEnabled = true
    @AppStorage("plink.reduceMotionOverride") private var reduceMotionOverride = false
    @AppStorage("playback_chat_side") private var chatOnRight = true

    private var qualityBinding: Binding<String> {
        Binding(get: { cellularQuality }, set: { cellularQuality = $0 })
    }

    var body: some View {
        SettingsScaffold(
            title: "Воспроизведение",
            subtitle: "Качество, субтитры и комфорт просмотра"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Видео")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "forward.end.fill",
                        title: "Автозапуск следующего",
                        subtitle: "После окончания ролика",
                        isOn: $autoplayNext
                    )
                    SettingsChoiceRow(
                        title: "Качество по сотовой сети",
                        options: [
                            (CellularQuality.auto.rawValue, "Авто"),
                            (CellularQuality.p720.rawValue, "720p"),
                            (CellularQuality.p480.rawValue, "480p"),
                        ],
                        selection: qualityBinding
                    )
                    SettingsToggleRow(
                        icon: "captions.bubble.fill",
                        title: "Субтитры по умолчанию",
                        subtitle: "Если доступны у ролика",
                        isOn: $subtitlesByDefault
                    )
                    SettingsToggleRow(
                        icon: "pip.enter",
                        title: "Picture in Picture",
                        subtitle: "Мини-плеер поверх других приложений",
                        isOn: $pipEnabled
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Комната")
                SettingsCard {
                    SettingsToggleRow(
                        icon: "sidebar.right",
                        title: "Чат справа (планшет)",
                        subtitle: "На iPhone чат всегда снизу",
                        isOn: $chatOnRight
                    )
                    SettingsToggleRow(
                        icon: "figure.walk.motion",
                        title: "Меньше анимаций",
                        subtitle: "Упростить motion и живые фоны",
                        iconColor: Color(hex: 0xF59E0B),
                        isOn: $reduceMotionOverride
                    )
                }
            }

            infoBanner(
                icon: "waveform.path.ecg",
                text: "Синхронизация play/pause/seek работает для YouTube. OTT-кинотеатры — через аккаунт host."
            )
        }
    }
}

internal enum CellularQuality: String, CaseIterable {
    case auto, p720, p480
}

// MARK: - HelpView

internal struct HelpView: View {
    @State private var query = ""
    private let articles: [HelpArticle] = [
        HelpArticle(
            id: "1",
            title: "Как создать комнату",
            body: "Главная или Комнаты → «+» → выбери YouTube/VK/кинотеатр → вставь ссылку → создай. Код комнаты копируется автоматически — отправь другу."
        ),
        HelpArticle(
            id: "2",
            title: "Как пригласить друга",
            body: "Друзья → «+» → введи @username → отправь заявку. Друг примет во вкладке «Заявки». Либо поделись 6-значным кодом комнаты."
        ),
        HelpArticle(
            id: "3",
            title: "Синхронизация play/pause",
            body: "Host управляет воспроизведением. Гости следуют автоматически (обычно <2 с). На YouTube используй кнопки плеера host."
        ),
        HelpArticle(
            id: "4",
            title: "Netflix и Кинопоиск",
            body: "Host входит в свой аккаунт подписки. Plink не раздаёт контент и не обходит DRM. Гости смотрят синхронно через Plink."
        ),
        HelpArticle(
            id: "5",
            title: "Жалоба и блокировка",
            body: "В чате комнаты удержи палец на сообщении → Пожаловаться / Заблокировать. Host может кикнуть участника."
        ),
    ]

    private var filtered: [HelpArticle] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return articles }
        return articles.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        SettingsScaffold(
            title: "Помощь",
            subtitle: "Ответы, поддержка и юридическая информация"
        ) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(V4.muted)
                TextField("Поиск по статьям", text: $query)
                    .foregroundStyle(V4.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(V4.surface.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(V4.line))

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Статьи")
                SettingsCard {
                    ForEach(filtered) { article in
                        NavigationLink {
                            HelpArticleView(article: article)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIconBadge(systemName: "doc.text.fill", color: V4.accent)
                                Text(article.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(V4.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(V4.muted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
                        }
                    }
                    if filtered.isEmpty {
                        Text(LocalizationManager.shared.string(.nothingFound))
                            .font(.subheadline)
                            .foregroundStyle(V4.muted)
                            .padding(20)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Поддержка")
                SettingsCard {
                    if let mail = URL(string: "mailto:support@plink.app?subject=Plink%20Support") {
                        Link(destination: mail) {
                            HStack(spacing: 12) {
                                SettingsIconBadge(systemName: "envelope.fill", color: Color(hex: 0x3B82F6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizationManager.shared.string(.pxContactSupport))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(V4.ink)
                                    Text("support@plink.app")
                                        .font(.system(size: 12))
                                        .foregroundStyle(V4.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(V4.muted)
                            }
                            .padding(14)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
                        }
                    }
                    linkRow("Условия использования", url: "https://plink.app/terms", icon: "doc.plaintext")
                    linkRow("Конфиденциальность", url: "https://plink.app/privacy", icon: "hand.raised.fill")
                }
            }

            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Text("Plink \(ver) (\(build))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(V4.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func linkRow(_ title: String, url: String, icon: String) -> some View {
        Group {
            if let u = URL(string: url) {
                Link(destination: u) {
                    HStack(spacing: 12) {
                        SettingsIconBadge(systemName: icon, color: V4.accent)
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(V4.muted)
                    }
                    .padding(14)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
                }
            }
        }
    }
}

internal struct HelpArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
}

struct HelpArticleView: View {
    let article: HelpArticle
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(article.title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(V4.ink)
                Text(article.body)
                    .font(.system(size: 16))
                    .foregroundStyle(V4.ink.opacity(0.88))
                    .lineSpacing(5)
            }
            .padding(20)
        }
        .background(V4.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - BlockedUsersView

internal struct BlockedUsersView: View {
    @State private var blocked: [BlockedUser] = []
    @State private var loading = true

    var body: some View {
        SettingsScaffold(
            title: "Заблокированные",
            subtitle: "Их сообщения скрыты в чатах"
        ) {
            if loading {
                ProgressView().tint(V4.accent).frame(maxWidth: .infinity).padding(.top, 40)
            } else if blocked.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(V4.accent.opacity(0.7))
                    Text(LocalizationManager.shared.string(.pxEmptyList))
                        .font(.headline)
                        .foregroundStyle(V4.ink)
                    Text(LocalizationManager.shared.string(.pxBlockHint))
                        .font(.subheadline)
                        .foregroundStyle(V4.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(V4.surface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(V4.line))
            } else {
                SettingsCard {
                    ForEach(blocked) { u in
                        HStack(spacing: 12) {
                            SettingsIconBadge(systemName: "person.fill", color: V4.danger)
                            Text(u.nickname)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(V4.ink)
                            Spacer()
                            Button("Разблок.") {
                                UserBlockManager.shared.unblockUser(u.id)
                                blocked.removeAll { $0.id == u.id }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(V4.accent)
                        }
                        .padding(14)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 58)
                        }
                    }
                }
            }
        }
        .task {
            loading = true
            await UserBlockManager.shared.refreshBlocksFromServer()
            blocked = UserBlockManager.shared.blockedUserIds.map {
                BlockedUser(id: $0, nickname: String($0.prefix(8)))
            }
            // Prefer usernames if we ever store them; for now show short ids
            loading = false
        }
    }
}

internal struct BlockedUser: Identifiable, Sendable {
    let id: String
    let nickname: String
}

// MARK: - DeleteAccountView

internal struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var loading = false
    @State private var error: String?
    @State private var scheduledForDeletionAt: Date?

    var body: some View {
        SettingsScaffold(
            title: "Удалить аккаунт",
            subtitle: "Необратимо после периода ожидания"
        ) {
            infoBanner(
                icon: "exclamationmark.triangle.fill",
                text: "Комнаты, друзья, история и аватар будут удалены. В течение 14 дней можно отменить, войдя снова."
            )

            SettingsCard {
                SettingsToggleRow(
                    icon: "checkmark.shield.fill",
                    title: "Я понимаю последствия",
                    subtitle: "Подтверждаю удаление аккаунта",
                    iconColor: V4.danger,
                    isOn: $confirmed
                )
            }

            Button {
                Task { await delete() }
            } label: {
                HStack {
                    if loading { ProgressView().tint(.white) }
                    Text(LocalizationManager.shared.string(.pxDeleteAccount))
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(confirmed ? V4.danger : V4.danger.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!confirmed || loading)

            if let err = error {
                Text(err).font(.caption).foregroundStyle(V4.danger)
            }
            if let date = scheduledForDeletionAt {
                Text("Удаление запланировано: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(V4.muted)
            }
        }
    }

    private func delete() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let resp = try await AuthService.shared.requestAccountDeletion(reason: "user_initiated")
            scheduledForDeletionAt = resp.scheduledForDeletionAt
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NotificationCenter.default.post(name: .plinkUserDeleted, object: nil)
            dismiss()
        } catch {
            self.error = "Не удалось: \(error.localizedDescription)"
        }
    }
}

// MARK: - Shared helpers

private func infoBanner(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(V4.accent)
            .frame(width: 28)
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(V4.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(V4.accent.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(V4.accent.opacity(0.18), lineWidth: 1)
    )
}

// MARK: - Notifications name

internal extension Notification.Name {
    static let plinkUserDeleted = Notification.Name("plink.userDeleted")
}
