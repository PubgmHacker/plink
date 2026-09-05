//
//  PlinkProfileRows.swift
//  Profile settings sheets — polished V4 Cinema UI
//

import SwiftUI

// MARK: - Shared settings chrome

private enum SettingsUI {
    /// Радиус карточек — тот же 24, что у карт лица профиля и хаба
    /// «Общих настроек»: до 23.08.2026 здесь жили свои 16 pt, и внутренние
    /// экраны выглядели «из другого приложения».
    static let cardRadius: CGFloat = 24
    static let iconSize: CGFloat = 34
}

/// Full-screen settings scaffold used by all profile sheets.
/// Фон — канвас V4 с радиальным свечением акцента темы: тот же, что у корня
/// «Общих настроек» и статистики. Раньше здесь жил собственный сине-серый
/// градиент с индиго-пятном — при переходе из корня настроек фон заметно
/// «переключался» на чужую палитру.
struct SettingsScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    /// Надзаголовок-крошка: раздел, которому принадлежит экран («Профиль»,
    /// «Управление аккаунтом», «Общие настройки»). Шапка — V4Heading, тот же
    /// блок, что у хаба настроек и корневых вкладок: до 23.08.2026 здесь жил
    /// собственный титул 28 heavy без крошки, и окно выглядело чужим.
    let eyebrow: String
    /// true — экран открыт шитом (корень своего NavigationStack): крестик
    /// в шапке, системная навигационная панель скрыта — как у хаба настроек.
    /// false — экран пришёл пушем: возврат несёт системная «Назад», второй
    /// выход не нужен (раньше здесь жил тулбарный крестик — на iOS 26
    /// панель заворачивала его в собственное стекло, вырастал серый круг).
    let showsClose: Bool
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    private let theme = V4Theme.saved

    init(
        title: String,
        subtitle: String? = nil,
        eyebrow: String = "Настройки",
        showsClose: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.eyebrow = eyebrow
        self.showsClose = showsClose
        self.content = content()
    }

    var body: some View {
        ZStack {
            V4.canvas.ignoresSafeArea()
            RadialGradient(
                colors: [theme.accentColor.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        V4Heading(eyebrow: eyebrow, title: title, subtitle: subtitle)
                        if showsClose {
                            Spacer(minLength: 0)
                            V4SheetCloseButton { dismiss() }
                        }
                    }
                    .padding(.top, showsClose ? 18 : 8)

                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsClose ? .hidden : .automatic, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

struct SettingsSectionLabel: View {
    let text: String
    var body: some View {
        // Типографика лейбла — та же, что у групп хаба «Общих настроек».
        Text(text.uppercased())
            .font(.system(size: 10.56, weight: .heavy))
            .tracking(1.16)
            .foregroundStyle(V4.muted)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // Карточка настроек — на стекле, как вся навигация приложения.
        // Разделители карточка вставляет сама МЕЖДУ строками: раньше каждая
        // строка носила собственный нижний оверлей, и под последней строкой
        // оставалась линия, упиравшаяся в скругление карты.
        _VariadicView.Tree(SettingsCardRows()) { content }
            .padding(.vertical, 4)
            .plinkGlass(.control, cornerRadius: SettingsUI.cardRadius)
    }
}

/// Раскладка строк карточки: волосяной разделитель между соседями,
/// после последней строки — ничего (язык sectionsGroup лица профиля).
private struct SettingsCardRows: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != lastID {
                    V4RowSeparator()
                }
            }
        }
    }
}

struct SettingsIconBadge: View {
    let systemName: String
    var color: Color = V4Theme.saved.accentColor
    var body: some View {
        // Мягкий круглый чип — побайтово тот же, что у строк лица профиля
        // (V4ProfileRow). Плотная цветная плашка со скруглением 11 читалась
        // чужим языком рядом с круглыми чипами остального приложения.
        ZStack {
            Circle().fill(color.opacity(0.14))
            Circle().stroke(color.opacity(0.22), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: SettingsUI.iconSize, height: SettingsUI.iconSize)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = V4Theme.saved.accentColor
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
                .tint(V4Theme.saved.accentColor)
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(enabled ? 1 : 0.55)
    }
}

struct SettingsInfoRow: View {
    let icon: String
    let title: String
    var value: String
    var iconColor: Color = V4Theme.saved.accentColor
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
                        .foregroundStyle(V4Theme.saved.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Строка ещё не сделанной возможности. `SettingsInfoRow` для этого не
/// годится: он устроен «подпись сверху, значение снизу» и правильно читается
/// на «Это устройство / iPhone · iOS 26.5». На двухфакторной защите он
/// переворачивал смысл — крупным и белым становилось слово «Скоро», а название
/// возможности уходило в мелкую серую подпись. Здесь порядок обычный,
/// как у соседей по карте, а статус — бледная пилюля справа.
struct SettingsPendingRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var badge: String = "Скоро"
    var iconColor: Color = V4Theme.saved.accentColor

    var body: some View {
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
            Spacer(minLength: 8)
            Text(badge)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(V4.line.opacity(0.55), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(0.72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(badge)")
    }
}

struct SettingsNavRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = V4Theme.saved.accentColor
    /// false — строка-действие без обещания перехода (язык V4ProfileRow).
    var showsChevron: Bool = true
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
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V4.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsChoiceRow: View {
    let title: String
    let options: [(String, String)] // id, label
    @Binding var selection: String

    private let theme = V4Theme.saved

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)

            // Сегменты — капсулы: выбранная залита акцентом, остальные на
            // стекле. Прямоугольники со скруглением 10 и плоской заливкой
            // V4.raised были единственными «квадратными» контролами экрана.
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { id, label in
                    let selected = selection == id
                    let button = Button {
                        HapticManager.selection()
                        withAnimation(.easeInOut(duration: 0.15)) { selection = id }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? theme.buttonTextColor : V4.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 36)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if selected {
                        button
                            .background(theme.accentColor, in: Capsule())
                            .shadow(color: theme.accentColor.opacity(0.30), radius: 7, y: 3)
                    } else {
                        button
                            .plinkGlass(.control, in: Capsule(), interactive: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }
}

/// Главная кнопка экрана настроек — единый PlinkProminentButtonStyle.
/// Белая с чёрным текстом, как Play у Apple TV и Netflix: главная CTA
/// статична и не зависит от темы — акцентная заливка перекрашивала кнопку
/// с каждой палитрой и терялась на пёстрых обложках (канон V4Components).
struct SettingsPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            HapticManager.impact(.medium)
            action()
        } label: {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                }
            }
        }
        .buttonStyle(
            PlinkProminentButtonStyle(
                tint: .white,
                textColor: .black,
                height: 52,
                cornerRadius: 16
            )
        )
        .disabled(isLoading)
    }
}

// MARK: - PersonalDataView

internal struct PersonalDataView: View {
    /// true — экран открыт шитом с лица профиля (кнопка «Редактировать»):
    /// нужен крестик. false — пришёл пушем из центра аккаунта.
    var asSheet: Bool = false

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
            subtitle: "Имя, никнейм и почта аккаунта",
            eyebrow: "Управление аккаунтом",
            showsClose: asSheet
        ) {
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Профиль")
                SettingsCard {
                    // Оба поля — один ребёнок карточки: между полями свой
                    // разделитель от кромки текста (14), а не строковый (60).
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizationManager.shared.string(.pxDisplayName))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(V4.muted)
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                            TextField("Как вас видят друзья", text: $displayName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                                .foregroundStyle(V4.ink)
                        }

                        Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 14)

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
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Аккаунт")
                SettingsCard {
                    SettingsInfoRow(icon: "envelope.fill", title: "Email", value: email.isEmpty ? "—" : email)
                }
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4Theme.saved.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            SettingsPrimaryButton(title: "Сохранить", isLoading: saving) {
                Task { await save() }
            }
            .padding(.top, 4)

            // Технический UUID убран с лица экрана: пользователю он не нужен,
            // а 36-символьная простыня выглядела как отладочный дамп. Полный
            // идентификатор нужен только поддержке — тихая строка внизу
            // копирует его целиком одним тапом.
            if !accountID.isEmpty {
                Button {
                    UIPasteboard.general.string = accountID
                    HapticManager.selection()
                    withAnimation { copied = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(copied ? "ID скопирован" : "ID для поддержки: \(accountID.prefix(8))…")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(V4.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Скопировать идентификатор аккаунта для поддержки")
            }
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
            APIClient.shared.authToken = AuthTokenStore.shared.token
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

    /// Серверный флаг «Закрытый профиль» (модель ВК): не @AppStorage —
    /// правда живёт на сервере и действует для всех, кто открывает профиль.
    @State private var profileClosed = false
    /// Пока флаг не приехал с сервера, тумблер выключен: иначе первое же
    /// движение отправило бы на сервер значение, которого юзер не выбирал.
    @State private var closedLoaded = false
    @State private var closedSaveTask: Task<Void, Never>?

    private var inviteBinding: Binding<String> {
        Binding(get: { inviteRaw }, set: { inviteRaw = $0 })
    }

    private var closedBinding: Binding<Bool> {
        Binding(
            get: { profileClosed },
            set: { newValue in
                guard newValue != profileClosed else { return }
                profileClosed = newValue
                saveClosed(newValue)
            }
        )
    }

    /// PATCH /users/me { profileClosed } — при отказе сервера тумблер
    /// возвращается на место: рисовать невыполненную приватность нельзя.
    private func saveClosed(_ value: Bool) {
        closedSaveTask?.cancel()
        closedSaveTask = Task {
            struct Body: Encodable { let profileClosed: Bool }
            struct Resp: Decodable { let profileClosed: Bool? }
            do {
                let _: Resp = try await APIClient.shared.request(
                    "users/me", method: .patch, body: Body(profileClosed: value)
                )
                HapticManager.selection()
            } catch {
                guard !Task.isCancelled else { return }
                profileClosed = !value
                HapticManager.errorOccurred()
            }
        }
    }

    var body: some View {
        SettingsScaffold(
            title: "Приватность",
            subtitle: "Кто может вас находить, приглашать и писать",
            eyebrow: "Управление аккаунтом"
        ) {
            // Без секционного лейбла: карта одна, а «ПРИВАТНОСТЬ» под
            // заголовком «Приватность» читалась дублем.
            VStack(alignment: .leading, spacing: 8) {
                // Закрытый профиль — первой картой: единственная настройка
                // здесь, которая меняет то, что видят другие люди прямо сейчас.
                SettingsCard {
                    SettingsToggleRow(
                        icon: "lock.fill",
                        title: "Закрытый профиль",
                        subtitle: "Друзей, статистику и просмотры видят только друзья",
                        isOn: closedBinding,
                        enabled: closedLoaded
                    )
                }
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
                        subtitle: "Другие могут найти вас по @username",
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

            infoBanner(
                icon: "shield.checkered",
                text: "Plink не продаёт личные данные. Жалобы и блокировки работают в чате комнаты."
            )
        }
        .task {
            // Текущее значение — только с сервера: до ответа тумблер спит,
            // повторный заход на экран пробует снова.
            if let me = try? await SocialProfileService.fetchMe() {
                profileClosed = me.isClosed == true
                closedLoaded = true
            }
        }
    }
}

internal enum InvitePermission: String, CaseIterable, Codable {
    case everyone, friendsOnly, noOne
}

// Раньше сюда снаружи передавался выдуманный список из
// одной захардкоженной сессии («Этот iPhone») — прямая ложь пользователю.
// Сервер (POST /auth/heartbeat) пока не ведёт учёт сессий по устройствам и
// возвращает только текущую, поэтому честный минимум: показываем текущее
// устройство с реальными данными из UIDevice и рабочую кнопку «Завершить
// остальные сессии» (POST /auth/signout-others с подтверждением).
struct ActiveSessionsView: View {
    @State private var signingOut = false
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

    private var currentDeviceTitle: String {
        "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
    }

    /// «Сегодня, 09:41» / «4 сент. 2026 г., 09:41» — относительная дата там,
    /// где система умеет. Экран называется «Активные сессии», и до этой строки
    /// единственным фактом о сессии была модель устройства.
    private var sessionStartedTitle: String? {
        guard let started = AuthService.shared.sessionStartedAt else { return nil }
        let f = DateFormatter()
        f.locale = Locale.current
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: started)
    }


    var body: some View {
        SettingsScaffold(
            // Тот же заголовок, что у строки-входа: «Активные сессии» —
            // название не меняется по пути (когезия навигации).
            title: "Активные сессии",
            subtitle: "Устройство, с которого вы вошли, и выход со всех остальных",
            eyebrow: "Безопасность и вход"
        ) {
            SettingsCard {
                SettingsInfoRow(
                    icon: "iphone",
                    title: "Это устройство",
                    value: currentDeviceTitle
                )
                if let sessionStartedTitle {
                    SettingsInfoRow(
                        icon: "clock",
                        title: "Вход выполнен",
                        value: sessionStartedTitle
                    )
                }
            }

            SettingsCard {
                SettingsNavRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Завершить остальные сессии",
                    subtitle: "Другие устройства выйдут из аккаунта",
                    iconColor: V4.danger,
                    showsChevron: false
                ) {
                    showConfirm = true
                }
            }

            if signingOut {
                ProgressView()
                    .tint(V4Theme.saved.accentColor)
                    .frame(maxWidth: .infinity)
            }
            if let msg = resultMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(resultIsError ? V4.danger : V4Theme.saved.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .alert("Завершить остальные сессии?", isPresented: $showConfirm) {
            Button("Завершить", role: .destructive) {
                Task { await signOutOthers() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все другие устройства будут разлогинены. Это устройство останется в аккаунте.")
        }
    }

    private func signOutOthers() async {
        signingOut = true
        resultMessage = nil
        defer { signingOut = false }
        do {
            try await AuthService.shared.signOutOtherSessions()
            resultIsError = false
            resultMessage = "Готово — остальные сессии завершены"
            HapticManager.impact(.medium)
        } catch {
            resultIsError = true
            resultMessage = "Не удалось: \(error.localizedDescription)"
            HapticManager.errorOccurred()
        }
    }
}

// MARK: - ChangePasswordView

/// Смена пароля через существующий reset-flow сервера: код на почту →
/// новый пароль. Отдельного роута «сменить по старому паролю» на бэкенде
/// нет, а reset-flow покрывает и «забыл», и «хочу сменить» — честно и
/// без выдуманных экранов.
internal struct ChangePasswordView: View {
    @State private var codeSent = false
    @State private var code = ""
    @State private var newPassword = ""
    @State private var working = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var done = false

    private var email: String { AuthService.shared.currentUserValue?.email ?? "" }
    private var canConfirm: Bool {
        code.trimmingCharacters(in: .whitespaces).count >= 4 && newPassword.count >= 8
    }

    var body: some View {
        SettingsScaffold(
            title: "Пароль",
            subtitle: "Смена по коду из письма",
            eyebrow: "Безопасность и вход"
        ) {
            SettingsCard {
                SettingsInfoRow(
                    icon: "envelope.fill",
                    title: "Код придёт на почту",
                    value: email.isEmpty ? "—" : email
                )
            }

            if codeSent {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsSectionLabel(text: "Новый пароль")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Код из письма")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(V4.muted)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 12)
                                TextField("6 цифр", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 10)
                                    .foregroundStyle(V4.ink)
                            }

                            Rectangle().fill(V4.line).frame(height: 1).padding(.leading, 14)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Новый пароль — минимум 8 символов")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(V4.muted)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 12)
                                SecureField("••••••••", text: $newPassword)
                                    .textContentType(.newPassword)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 12)
                                    .foregroundStyle(V4.ink)
                            }
                        }
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(messageIsError ? V4.danger : V4Theme.saved.accentColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }

            if done {
                infoBanner(
                    icon: "checkmark.shield.fill",
                    text: "Пароль обновлён. На других устройствах может потребоваться войти заново.",
                    tone: .success
                )
            } else if codeSent {
                SettingsPrimaryButton(title: "Сменить пароль", isLoading: working) {
                    Task { await confirm() }
                }
                .disabled(!canConfirm)
                .opacity(canConfirm ? 1 : 0.55)

                Button {
                    Task { await sendCode(resend: true) }
                } label: {
                    Text("Отправить код ещё раз")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(V4.muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(working)
            } else {
                SettingsPrimaryButton(title: "Отправить код", isLoading: working) {
                    Task { await sendCode(resend: false) }
                }
                .disabled(email.isEmpty)
            }
        }
        #if DEBUG
        .onAppear {
            // Дизайн-превью второй стадии: `-plink.designrow password.sent`
            // показывает поля кода и нового пароля без похода на бэкенд.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-plink.designrow"),
               args.indices.contains(i + 1), args[i + 1] == "password.sent" {
                codeSent = true
            }
        }
        #endif
    }

    private func sendCode(resend: Bool) async {
        guard !email.isEmpty else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            try await AuthService.shared.requestPasswordReset(email: email)
            codeSent = true
            messageIsError = false
            message = resend ? "Код отправлен ещё раз" : nil
            HapticManager.impact(.light)
        } catch {
            messageIsError = true
            message = "Не удалось отправить код: \(error.localizedDescription)"
            HapticManager.errorOccurred()
        }
    }

    private func confirm() async {
        working = true
        message = nil
        defer { working = false }
        do {
            try await AuthService.shared.confirmPasswordReset(
                email: email,
                code: code.trimmingCharacters(in: .whitespaces),
                newPassword: newPassword
            )
            done = true
            messageIsError = false
            message = nil
            HapticManager.impact(.medium)
        } catch {
            messageIsError = true
            message = "Не удалось сменить пароль: \(error.localizedDescription)"
            HapticManager.errorOccurred()
        }
    }
}

// MARK: - AccountCenterView

/// Строка-переход центра аккаунта: тот же вид, что SettingsNavRow, но ведёт
/// пушем через NavigationLink — внутренние экраны закрываются системной
/// «Назад», а не россыпью вложенных шитов.
private struct AccountNavRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconColor: Color = V4Theme.saved.accentColor
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(V4.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Разделители рисует SettingsCard между соседями — собственный
        // нижний оверлей оставлял линию под последней строкой карты.
    }
}

/// Единый центр аккаунта — модель «Управление VK ID»: одно место, где
/// собраны личные данные, вход и безопасность, приватность и доступ к
/// данным. Раньше эти экраны были рассыпаны по хабу настроек, а
/// безопасность пряталась внутри «Приватности».
internal struct AccountCenterView: View {
    var store: V4ProfileStore?
    /// true — открыт шитом с лица профиля; false — пушем из настроек.
    var asSheet: Bool = false

    private let theme = V4Theme.saved

    #if DEBUG
    /// Дизайн-превью: `-plink.designrow personal|password|password.sent|sessions|
    /// privacy|services|blocked|delete` пушит внутренний экран сразу —
    /// скриншоты без ручных тапов (язык -plink.designsheet лица профиля).
    @State private var debugRow: String?
    #endif

    private var user: User? { AuthService.shared.currentUserValue }
    private var displayName: String { store?.displayName ?? user?.displayName ?? user?.username ?? "—" }
    private var username: String { store?.username ?? user?.username ?? "" }
    private var email: String { store?.email ?? user?.email ?? "" }

    var body: some View {
        SettingsScaffold(
            title: "Управление аккаунтом",
            subtitle: "Данные, вход, приватность и доступ",
            showsClose: asSheet
        ) {
            identityCard

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Аккаунт")
                SettingsCard {
                    AccountNavRow(
                        icon: "person.text.rectangle.fill",
                        title: "Личные данные",
                        subtitle: "Имя, никнейм и почта"
                    ) {
                        PersonalDataView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Безопасность и вход")
                SettingsCard {
                    AccountNavRow(
                        icon: "key.fill",
                        title: "Пароль",
                        subtitle: "Смена по коду из письма",
                        iconColor: Color(hex: 0xF59E0B)
                    ) {
                        ChangePasswordView()
                    }
                    AccountNavRow(
                        icon: "laptopcomputer.and.iphone",
                        title: "Активные сессии",
                        // Экран за строкой показывает ОДНО устройство —
                        // текущее — и кнопку выхода с остальных. Обещать
                        // список устройств здесь было нечестно.
                        subtitle: "Это устройство и выход с остальных",
                        iconColor: Color(hex: 0x3B82F6)
                    ) {
                        ActiveSessionsView()
                    }
                    // На сервере есть поля twofaEnabled/twofaSecret, но нет
                    // пользовательских роутов включения — честная строка «Скоро».
                    SettingsPendingRow(
                        icon: "lock.shield.fill",
                        title: "Двухфакторная защита",
                        subtitle: "Второй шаг при входе с нового устройства",
                        iconColor: Color(hex: 0xA855F7)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Приватность")
                SettingsCard {
                    AccountNavRow(
                        icon: "hand.raised.fill",
                        title: "Приватность",
                        subtitle: "Кто может находить, приглашать и писать",
                        iconColor: Color(hex: 0x22C55E)
                    ) {
                        PrivacySecurityView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Данные и доступ")
                SettingsCard {
                    AccountNavRow(
                        icon: "play.rectangle.on.rectangle.fill",
                        title: "Кинотеатры и Яндекс ID",
                        subtitle: connectedSubtitle
                    ) {
                        ConnectedServicesView()
                    }
                    AccountNavRow(
                        icon: "person.slash.fill",
                        title: "Заблокированные",
                        subtitle: "Их сообщения скрыты",
                        iconColor: V4.danger
                    ) {
                        BlockedUsersView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Опасная зона")
                SettingsCard {
                    AccountNavRow(
                        icon: "trash.fill",
                        title: "Удалить аккаунт",
                        subtitle: "Необратимо после периода ожидания",
                        iconColor: V4.danger
                    ) {
                        DeleteAccountView()
                    }
                }
            }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-plink.designrow"), args.indices.contains(i + 1) {
                debugRow = args[i + 1]
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { debugRow != nil },
            set: { if !$0 { debugRow = nil } }
        )) {
            switch debugRow {
            case "personal": PersonalDataView()
            case "password", "password.sent": ChangePasswordView()
            case "sessions": ActiveSessionsView()
            case "privacy": PrivacySecurityView()
            case "services": ConnectedServicesView()
            case "blocked": BlockedUsersView()
            case "delete": DeleteAccountView()
            default: EmptyView()
            }
        }
        #endif
    }

    private var connectedSubtitle: String {
        let n = LinkedExternalAccount.connectedCount
        return n > 0 ? "Подключено: \(n)" : "Подключение аккаунтов"
    }

    /// Мини-шапка идентичности — как карточка владельца в VK ID: сразу
    /// видно, каким аккаунтом управляешь.
    private var identityCard: some View {
        HStack(spacing: 14) {
            Group {
                if let local = store?.localAvatarImage {
                    Image(uiImage: local).resizable().scaledToFill()
                } else if let url = store?.avatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            V4Avatar(letter: String(displayName.prefix(1)), seed: user?.id ?? username, size: 56)
                        }
                    }
                } else {
                    V4Avatar(letter: String(displayName.prefix(1)), seed: user?.id ?? username, size: 56)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().stroke(V4.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.system(size: 17, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                // Ник только тогда, когда он не повторяет имя: у аккаунта без
                // заданного имени displayName сам берётся из username, и
                // карточка читалась «testdev» / «@testdev» / почта.
                if !username.isEmpty,
                   username.caseInsensitiveCompare(displayName) != .orderedSame {
                    Text("@\(username)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(V4.muted.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .plinkGlass(.control, cornerRadius: SettingsUI.cardRadius)
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
            subtitle: "Качество, субтитры и комфорт просмотра",
            eyebrow: "Общие настройки"
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
                        iconColor: V4.amber,
                        isOn: $reduceMotionOverride
                    )
                }
            }

            infoBanner(
                icon: "waveform.path.ecg",
                text: "Play, пауза и перемотка синхронны на YouTube, RuTube и VK Видео. В кинотеатрах каждый смотрит в своём аккаунте — Plink держит одинаковое время."
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
            body: "Главная или Комнаты → «+» → выберите YouTube/VK/кинотеатр → вставьте ссылку → создайте. Код комнаты копируется автоматически — отправьте другу."
        ),
        HelpArticle(
            id: "2",
            title: "Как пригласить друга",
            body: "Друзья → «+» → введите @username → отправьте заявку. Друг примет во вкладке «Заявки». Либо поделитесь 6-значным кодом комнаты."
        ),
        HelpArticle(
            id: "3",
            title: "Синхронизация play/pause",
            body: "Воспроизведением управляет владелец комнаты — остальные подхватывают паузу и перемотку автоматически, обычно меньше чем за 2 секунды."
        ),
        HelpArticle(
            id: "4",
            title: "Кинотеатры и подписки",
            body: "Plink ничего не транслирует и не раздаёт контент. Владелец комнаты выбирает тайтл, а каждый участник открывает его в своём аккаунте кинотеатра — Plink лишь держит время одинаковым. Подписка нужна каждому, кто смотрит."
        ),
        HelpArticle(
            id: "5",
            title: "Жалоба и блокировка",
            body: "В чате комнаты удержи палец на сообщении → Пожаловаться / Заблокировать. Владелец комнаты может удалить участника."
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
            subtitle: "Ответы, поддержка и юридическая информация",
            eyebrow: "Общие настройки"
        ) {
            // Поиск — на стекле, как поисковые поля Главной и Друзей.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(V4.muted)
                TextField("Поиск по статьям", text: $query)
                    .foregroundStyle(V4.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .plinkGlass(.control, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionLabel(text: "Статьи")
                SettingsCard {
                    ForEach(filtered) { article in
                        NavigationLink {
                            HelpArticleView(article: article)
                        } label: {
                            HStack(spacing: 12) {
                                SettingsIconBadge(systemName: "doc.text.fill", color: V4Theme.saved.accentColor)
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
                    // Opens the support page rather than mail: plink.app publishes
                    // a null MX record (0 ., RFC 7505), so the domain accepts no
                    // mail and the mailto opened a composer aimed at nowhere. The
                    // address is printed on the page; move it back here once the
                    // mailbox works.
                    if let support = PlinkURLs.support {
                        Link(destination: support) {
                            HStack(spacing: 12) {
                                SettingsIconBadge(systemName: "lifepreserver.fill", color: Color(hex: 0x3B82F6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizationManager.shared.string(.pxContactSupport))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(V4.ink)
                                    Text("Справка и контакты")
                                        .font(.system(size: 12))
                                        .foregroundStyle(V4.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .foregroundStyle(V4.muted)
                            }
                            .padding(14)
                        }
                    }
                    linkRow(LocalizationManager.shared.string(.profileTerms), url: PlinkURLs.terms, icon: "doc.plaintext")
                    linkRow(LocalizationManager.shared.string(.profilePrivacy), url: PlinkURLs.privacy, icon: "hand.raised.fill")
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

    private func linkRow(_ title: String, url: URL?, icon: String) -> some View {
        Group {
            if let u = url {
                Link(destination: u) {
                    HStack(spacing: 12) {
                        SettingsIconBadge(systemName: icon, color: V4Theme.saved.accentColor)
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(V4.muted)
                    }
                    .padding(14)
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
            subtitle: "Их сообщения скрыты в чатах",
            eyebrow: "Данные и доступ"
        ) {
            if loading {
                // Скелет строк, а не спиннер посреди пустоты: экран ждёт
                // список людей, и ожидание должно иметь форму этого списка.
                // Крутилка тем более не к месту теперь, когда к запросу
                // блокировок добавились запросы имён — пауза стала заметной,
                // а прыжок «пустой круг → готовая карта» резче.
                // Скелетоны здесь те же, что у полок и списка групп.
                SettingsCard {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            SkeletonCircle(size: SettingsUI.iconSize)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonRect(width: 124, height: 13)
                                SkeletonRect(width: 76, height: 10)
                            }
                            Spacer(minLength: 8)
                            SkeletonRect(width: 96, height: 12, cornerRadius: 6)
                        }
                        .padding(14)
                    }
                }
                .accessibilityLabel("Загрузка списка заблокированных")
            } else if blocked.isEmpty {
                // Пустое состояние — в общем каркасе состояний V4: иконка в
                // мягком круге на стеклянной карте, а не плоская заливка.
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(V4Theme.saved.accentColor.opacity(0.13))
                        Circle().stroke(V4Theme.saved.accentColor.opacity(0.22), lineWidth: 1)
                        Image(systemName: "person.slash")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(V4Theme.saved.accentColor)
                    }
                    .frame(width: 58, height: 58)
                    Text(LocalizationManager.shared.string(.pxEmptyList))
                        .font(.system(size: 16.5, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(V4.ink)
                    Text(LocalizationManager.shared.string(.pxBlockHint))
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineSpacing(2)
                        .foregroundStyle(V4.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .plinkGlass(.control, cornerRadius: 20)
            } else {
                SettingsCard {
                    ForEach(blocked) { u in
                        HStack(spacing: 12) {
                            SettingsIconBadge(systemName: "person.fill", color: V4.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.nickname)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(V4.ink)
                                if let handle = u.handle {
                                    Text("@\(handle)")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(V4.muted)
                                }
                            }
                            .lineLimit(1)
                            Spacer(minLength: 8)
                            Button("Разблокировать") {
                                HapticManager.selection()
                                UserBlockManager.shared.unblockUser(u.id)
                                blocked.removeAll { $0.id == u.id }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(V4Theme.saved.accentColor)
                        }
                        .padding(14)
                    }
                }
            }
        }
        .task {
            loading = true
            await UserBlockManager.shared.refreshBlocksFromServer()
            blocked = await Self.resolveNames(for: UserBlockManager.shared.blockedUserIds)
            loading = false
        }
    }

    /// `GET moderation/blocked` отдаёт только идентификаторы, поэтому имена
    /// приходится дотягивать отдельно — тем же `users/:id`, которым личка
    /// достаёт собеседника. Раньше их не тянули вовсе и в ряду стояли первые
    /// 8 символов сырого id: строка «a3f9c210» с кнопкой «Разблокировать» не
    /// говорит, кого разблокируют, — список блокировок нельзя разобрать.
    ///
    /// Запросы идут разом, а не в цикле: список короткий (люди блокируют
    /// единицы), зато последовательный обход растянул бы открытие экрана на
    /// сумму всех задержек. Кто не ответил — остаётся с коротким id: это
    /// хуже имени, но лучше пустой строки, и кнопка всё равно работает.
    private static func resolveNames(for ids: Set<String>) async -> [BlockedUser] {
        struct UserDTO: Decodable {
            let username: String?
            let displayName: String?
        }

        let people = await withTaskGroup(of: BlockedUser.self) { group in
            for id in ids {
                group.addTask {
                    let dto: UserDTO? = try? await APIClient.shared.request("users/\(id)")
                    let handle = dto?.username?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let name = dto?.displayName?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let title = !name.isEmpty ? name
                        : (!handle.isEmpty ? handle : String(id.prefix(8)))
                    let secondary = !handle.isEmpty
                        && handle.caseInsensitiveCompare(title) != .orderedSame
                        ? handle : nil
                    return BlockedUser(id: id, nickname: title, handle: secondary)
                }
            }
            var out: [BlockedUser] = []
            for await person in group { out.append(person) }
            return out
        }

        // Порядок в Set не определён и меняется между запусками — без
        // сортировки список перетасовывался бы при каждом открытии экрана.
        return people.sorted {
            $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
        }
    }
}

internal struct BlockedUser: Identifiable, Sendable {
    let id: String
    let nickname: String
    /// @-ник второй строкой. `nil`, когда он ничего не добавляет: у человека
    /// без заданного имени displayTitle сам равен username, и ряд читался бы
    /// «plink_sim_demo» / «@plink_sim_demo» — то же самое дважды. Правило
    /// повторяет Friendship.secondaryLine.
    let handle: String?
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
            subtitle: "Необратимо после периода ожидания",
            eyebrow: "Опасная зона"
        ) {
            infoBanner(
                icon: "exclamationmark.triangle.fill",
                text: "Комнаты, друзья, история и аватар будут удалены. В течение 14 дней можно отменить, войдя снова.",
                tone: .danger
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

/// Смысловой цвет плашки. По умолчанию — акцент темы: плашка нейтральна и
/// читается как фирменная подсказка. Но на экране «Опасная зона» треугольник
/// внимания, покрашенный в акцент, — единственный не-красный элемент среди
/// красного щита и красной кнопки: буквальный знак опасности выглядел
/// декорацией. Тон привязывает цвет к смыслу, а не к бренду.
internal enum InfoBannerTone {
    case info, warning, danger, success

    var color: Color {
        switch self {
        case .info:    return V4Theme.saved.accentColor
        case .warning: return V4.amber
        case .danger:  return V4.danger
        case .success: return V4.free
        }
    }
}

internal func infoBanner(
    icon: String,
    text: String,
    tone: InfoBannerTone = .info
) -> some View {
    let accent = tone.color
    return HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 28)
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(V4.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(accent.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(accent.opacity(0.18), lineWidth: 1)
    )
}

// MARK: - Notifications name

internal extension Notification.Name {
    static let plinkUserDeleted = Notification.Name("plink.userDeleted")
}
