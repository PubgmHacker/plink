import SwiftUI

/// Публичный профиль друга — то же лицо, что у своего профиля в настройках
/// (модель Request C/D): обложка с амбиент-свечением, аватар внахлёст с
/// точкой присутствия, статус-пузырь Discord (read-only), капсулы бейджей,
/// стеклянные карты счётчиков и истории. Удалённый аккаунт — надгробие
/// в духе Telegram: без PII, без действий.
struct FriendProfileView: View {
    let userId: String
    var usernameHint: String = ""
    var onWatchTogether: (() -> Void)? = nil
    /// «Написать» (модель ТГ/ВК: профиль — хаб действий). nil — кнопки нет:
    /// из чата с этим же человеком она была бы дверью в ту же комнату.
    var onMessage: (() -> Void)? = nil

    @State private var profile: UserSocialProfile?
    @State private var error: String?
    @State private var isLoading = true
    /// Своя (data:image) обложка друга — декодируется один раз в load(),
    /// не в body: base64 на каждый кадр непозволителен.
    @State private var customCover: UIImage?
    /// Просмотр аватара на весь экран (модель ТГ): тап по кругу.
    @State private var showAvatarViewer = false
    /// Рекурсия ВК: тап по другу в рельсе/списке открывает ЕГО профиль
    /// поверх текущего. У дриллнутого профиля нет onWatchTogether/onMessage —
    /// действия доступны только с людьми из собственного списка друзей.
    @State private var drillFriend: ProfileFriendPreview?
    /// Полный список друзей владельца профиля (дверь из заголовка рельсы).
    @State private var showAllFriends = false
    /// CTA «Добавить в друзья» для не-друга: idle → отправка → отправлена.
    @State private var isSendingRequest = false
    @State private var friendRequestSent = false

    /// Акцент — сохранённая тема приложения: профиль открывается шитом,
    /// у него нет прямого доступа к теме корня.
    private let theme = V4Theme.saved
    /// Шит без статус-бара — полотно ниже, чем во вкладке профиля (212).
    private let coverHeight: CGFloat = 176
    private let avatarOverlap: CGFloat = 54

    private var isDeleted: Bool {
        profile?.deleted == true || usernameHint.hasPrefix("deleted_")
    }
    private var isOnline: Bool { profile?.isOnline == true && !isDeleted }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: coverHeight)
                    .frame(maxWidth: .infinity)
                avatarRow
                identityBlock
                if isDeleted {
                    deletedCard
                } else {
                    addFriendCTA
                    if profile?.closed == true {
                        // Закрытый профиль (модель ВК): идентичность и
                        // присутствие видны, статистика/просмотры/друзья — нет.
                        ProfileClosedCard(accent: theme.accentColor)
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                    } else {
                        countersCard
                        historyCard
                        friendsCard
                    }
                }
            }
            .padding(.bottom, 40)
            // Задник шапки: обложка + амбиент одним композитом с вырезом
            // под аватар (модель Discord) — лицо и карты живут в свете
            // обложки, а в зазоре вокруг аватара видна сама страница.
            .background(alignment: .top) { headerBackdrop }
        }
        // Обложка — от верхней кромки шита, кнопка закрытия плавает по ней.
        .ignoresSafeArea(edges: .top)
        .background(V4.canvas.ignoresSafeArea())
        .foregroundStyle(V4.ink)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $showAvatarViewer) {
            FriendAvatarViewer(
                userId: userId,
                storedURL: profile?.avatarURL,
                letter: String((profile?.displayTitle ?? usernameHint).prefix(1)).uppercased()
            )
        }
        // Рекурсивный просмотр (модель ВК): профиль друга друга — таким же
        // шитом поверх. Каждый уровень несёт свой drillFriend, цепочка
        // произвольной глубины закрывается по одному экрану.
        .sheet(item: $drillFriend) { friend in
            NavigationStack {
                FriendProfileView(userId: friend.id, usernameHint: friend.username)
                    .toolbar {
                        V4SheetCloseToolbarItem { drillFriend = nil }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllFriends) {
            NavigationStack {
                ProfileFriendListSheet(
                    userId: userId,
                    title: "Друзья",
                    accent: theme.accentColor,
                    onFriend: { friend in
                        // Синхронный своп шитов — тот же приём, что у
                        // «Написать» в V4FriendsView: список закрывается,
                        // профиль выбранного друга открывается.
                        showAllFriends = false
                        drillFriend = friend
                    }
                )
                .toolbar {
                    V4SheetCloseToolbarItem { showAllFriends = false }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Обложка + амбиент

    /// Полотно обложки: своя картинка друга → пресет по токену → «Кинозал»
    /// по умолчанию. У надгробия — глухой графит без сюжета.
    @ViewBuilder private var coverCanvas: some View {
        if isDeleted {
            LinearGradient(
                colors: [Color(hex: "#262A33"), Color(hex: "#101318")],
                startPoint: .top, endPoint: .bottom
            )
        } else if let customCover {
            // Color.clear.overlay — scaledToFill заполняет полотно, не
            // распирая ширину под размер исходного фото.
            Color.clear
                .overlay(Image(uiImage: customCover).resizable().scaledToFill())
                .clipped()
        } else if let p = profile {
            (V4CoverStyle.parse(p.coverURL) ?? .dusk).artwork()
        } else {
            // Профиль ещё грузится — нейтральное полотно вместо флеша
            // дефолтного пресета, который через секунду сменится.
            LinearGradient(
                colors: [Color(hex: "#1A1E27"), Color(hex: "#10131A")],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    /// Скримы — только на фото из галереи: у градиентных пресетов, надгробия
    /// и полотна загрузки тёмный низ уже вшит в само полотно.
    private var coverPlate: some View {
        ZStack {
            coverCanvas
            if customCover != nil, !isDeleted {
                LinearGradient(
                    colors: [.black.opacity(0.18), .clear, .black.opacity(0.22)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .frame(height: coverHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Зеркальная размытая копия обложки под её нижней кромкой: цвета на
    /// стыке совпадают, свечение тает к канвасу — обложка и страница
    /// перестают быть «двумя разными экранами».
    private var coverAmbient: some View {
        coverCanvas
            .scaleEffect(x: 1, y: -1)
            .frame(height: 400)
            .frame(maxWidth: .infinity)
            .blur(radius: 70)
            .saturation(1.35)
            .mask(LinearGradient(stops: [
                .init(color: .black.opacity(0.60), location: 0),
                .init(color: .black.opacity(0.26), location: 0.55),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            // Первые 40 pt прячутся под непрозрачной обложкой — шов без линии.
            .offset(y: coverHeight - 40)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Обложка + амбиент одним композитом с прозрачным вырезом под аватар
    /// (модель Discord): в зазоре видна сама страница, а не нарисованное
    /// кольцо. Геометрия выреза — из констант ряда аватара: центр
    /// (18 + 56, coverHeight − 54 + 56), диаметр 112 + 2×7 зазора.
    private var headerBackdrop: some View {
        ZStack(alignment: .top) {
            coverAmbient
            coverPlate
        }
        .frame(height: coverHeight - 40 + 400, alignment: .top)
        .overlay(alignment: .topLeading) {
            Circle()
                .frame(width: 126, height: 126)
                .offset(x: 74 - 63, y: coverHeight + 2 - 63)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Аватар внахлёст + статус

    private var avatarRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            avatarBlock

            // Колонка справа: статус-реплика наверху ложится на обложку
            // (модель Discord), CTA — по нижней линии аватара.
            VStack(alignment: .leading, spacing: 0) {
                if !isDeleted, let status = profile?.statusText, !status.isEmpty {
                    statusBubble(status)
                }
                Spacer(minLength: 8)
                // Ряд действий (модель ТГ/ВК: профиль — хаб действий):
                // «Смотреть вместе» — главное, «Написать» — дверь в личку.
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if !isDeleted, let onMessage {
                        Button {
                            HapticManager.selection()
                            onMessage()
                        } label: {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .buttonStyle(PlinkGlassIconButtonStyle(diameter: 42))
                        .accessibilityLabel("Написать сообщение")
                    }
                    if !isDeleted, let onWatchTogether {
                        Button {
                            HapticManager.selection()
                            onWatchTogether()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Смотреть вместе")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 42, cornerRadius: 14))
                        .accessibilityLabel("Смотреть вместе")
                    }
                }
            }
            .frame(height: 112)
        }
        .padding(.horizontal, 18)
        // Нахлёст: ряд поднят на обложку, отрицательный нижний отступ
        // возвращает вертикальный ритм.
        .offset(y: -avatarOverlap)
        .padding(.bottom, -avatarOverlap)
    }

    /// Статус-«мысль» как у своего профиля, но реплика чужая — только чтение.
    private func statusBubble(_ text: String) -> some View {
        PlinkStatusBubbleShell {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Статус: \(text)")
    }

    /// Аватар 112 pt без рисованных колец: зазор вокруг круга пробит в
    /// задник шапки (headerBackdrop), зазор вокруг точки присутствия —
    /// сквозь сам аватар. Тап открывает просмотр на весь экран (модель ТГ).
    private var avatarBlock: some View {
        Button {
            guard !isDeleted else { return }
            HapticManager.selection()
            showAvatarViewer = true
        } label: {
            Group {
                if isDeleted {
                    PlinkDeletedAvatar(size: 112)
                } else {
                    PlinkStableAvatar(
                        url: PlinkAvatarURL.stable(userId: userId, stored: profile?.avatarURL),
                        letter: String((profile?.displayTitle ?? usernameHint).prefix(1)).uppercased(),
                        size: 112,
                        userId: userId
                    )
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            // Вырез под точку: стирает арку аватара вокруг неё, центры
            // совпадают (смещение +2 компенсирует разницу диаметров 34/26).
            // У надгробия точки нет — и выреза тоже.
            .overlay(alignment: .bottomTrailing) {
                if !isDeleted {
                    Circle()
                        .frame(width: 34, height: 34)
                        .offset(x: 2, y: 2)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            // Точка присутствия (модель Discord): зелёная — в сети,
            // серая — офлайн.
            .overlay(alignment: .bottomTrailing) {
                if !isDeleted {
                    Circle()
                        .fill(isOnline ? Color(hex: "#23A55A") : Color(hex: "#80848E"))
                        .frame(width: 26, height: 26)
                        .offset(x: -2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDeleted ? "Удалённый аккаунт" : "Аватар. \(profile?.presenceText ?? ""). Открыть на весь экран")
    }

    // MARK: Идентичность

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(profile?.displayTitle ?? (isDeleted ? "Удалённый аккаунт" : (usernameHint.isEmpty ? "Профиль" : usernameHint)))
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 7) {
                if isDeleted {
                    Text(LocalizationManager.shared.string(.fpUnavailable))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(V4.muted)
                } else {
                    if let u = profile?.username {
                        Text("@\(u)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(V4.muted)
                            .lineLimit(1)
                    }
                    if profile?.isPremium == true {
                        Text("PLINK+")
                            .font(.system(size: 10, weight: .black))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#A855F7"), in: Capsule())
                    }
                }
            }
            .padding(.top, 5)

            if let p = profile, !isDeleted {
                Text(p.presenceText)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isOnline ? Color(hex: "#23A55A") : V4.muted)
                    .padding(.top, 4)
            }

            badgesRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Капсулы достижений — тот же язык, что у своего профиля: известные
    /// коды маппятся в ProfileBadge, неизвестные не рисуем.
    @ViewBuilder private var badgesRow: some View {
        let badges = (profile?.badges ?? []).compactMap(ProfileBadge.from)
        if !badges.isEmpty, !isDeleted {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.rawValue) { badge in
                        HStack(spacing: 5) {
                            Image(systemName: badge.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(theme.accentColor)
                            Text(badge.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(V4.ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .plinkGlass(.control, in: Capsule())
                    }
                }
            }
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Достижения: \(badges.map(\.title).joined(separator: ", "))")
        }
    }

    // MARK: Счётчики

    /// Стеклянная карта показателей. «Друзей» здесь есть — в отличие от
    /// своего профиля, у чужого нет карточки-двери в список друзей.
    private var countersCard: some View {
        HStack(spacing: 0) {
            counter(profile?.watchHoursText ?? "—", "время")
            counterDivider
            counter(profile.map { "\($0.filmsWatched)" } ?? "—", "фильмов")
            counterDivider
            counter(profile.map { "\($0.roomsCreated)" } ?? "—", "комнат")
            counterDivider
            counter(profile.map { "\($0.friendsCount)" } ?? "—", "друзей")
        }
        .padding(.vertical, 13)
        .plinkGlass(.control, cornerRadius: 20)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .accessibilityElement(children: .combine)
    }

    private var counterDivider: some View {
        Rectangle().fill(V4.line).frame(width: 1, height: 26)
    }

    private func counter(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V4.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Добавить в друзья

    /// CTA не-другу (модель ВК): на открытом профиле — над статистикой,
    /// на закрытом — над замком (заявка и есть ключ к закрытому профилю).
    /// isFriend == false строго: nil — старый бэкенд, кнопку не рисуем.
    @ViewBuilder private var addFriendCTA: some View {
        if let p = profile, p.isSelf != true, p.isFriend == false {
            Button {
                guard !isSendingRequest, !friendRequestSent else { return }
                HapticManager.selection()
                isSendingRequest = true
                Task {
                    let ok = await FriendManager.shared.sendRequest(to: p.id, username: p.username)
                    isSendingRequest = false
                    if ok {
                        friendRequestSent = true
                        HapticManager.notification(.success)
                    } else {
                        HapticManager.errorOccurred()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isSendingRequest {
                        ProgressView()
                            .tint(V4.ink)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: friendRequestSent ? "checkmark" : "person.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(friendRequestSent ? "Заявка отправлена" : "Добавить в друзья")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 46, cornerRadius: 16))
            .disabled(isSendingRequest || friendRequestSent)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .accessibilityLabel(friendRequestSent ? "Заявка отправлена" : "Добавить в друзья")
        }
    }

    // MARK: История

    @ViewBuilder private var historyCard: some View {
        if let history = profile?.watchHistory, !history.isEmpty {
            ProfileWatchRailCard(history: history, accent: theme.accentColor)
                .padding(.horizontal, 18)
                .padding(.top, 12)
        } else if isLoading, profile == nil {
            HStack {
                Spacer()
                ProgressView().tint(theme.accentColor)
                Spacer()
            }
            .padding(.top, 28)
        } else if let error {
            // Сеть подвела — тупика нет: «Повторить» перезапрашивает профиль,
            // не заставляя закрывать и заново открывать шит.
            VStack(spacing: 12) {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(V4.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    HapticManager.selection()
                    self.error = nil
                    Task { await load() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Повторить")
                    }
                }
                .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 40, cornerRadius: 14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .plinkGlass(.control, cornerRadius: 20)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Не удалось загрузить профиль. Повторить")
        }
    }

    // MARK: Друзья

    /// Рельса друзей (модель ВК): круглые аватарки с никами, тап — профиль
    /// друга поверх (рекурсия), заголовок — полный список.
    @ViewBuilder private var friendsCard: some View {
        if let friends = profile?.friends, !friends.isEmpty {
            ProfileFriendsRailCard(
                friends: friends,
                friendsCount: profile?.friendsCount ?? friends.count,
                onFriend: { drillFriend = $0 },
                onHeader: { showAllFriends = true }
            )
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    // MARK: Надгробие

    private var deletedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Аккаунт удалён", systemImage: "person.crop.circle.badge.xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V4.ink.opacity(0.85))
            Text(LocalizationManager.shared.string(.fpUnavailableSub))
                .font(.system(size: 13))
                .foregroundStyle(V4.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .plinkGlass(.control, cornerRadius: 20)
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    // MARK: Загрузка

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await SocialProfileService.fetch(userId: userId)
            profile = p
            error = nil
            // Обложка-фото друга: тот же data-URL канал, что и в бридже.
            if let raw = p.coverURL, raw.hasPrefix("data:image"),
               let comma = raw.firstIndex(of: ","),
               let data = Data(base64Encoded: String(raw[raw.index(after: comma)...])) {
                customCover = UIImage(data: data)
            } else {
                customCover = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Просмотр аватара на весь экран (модель Телеграма: тап по кругу в
/// профиле — фото крупно на тёмном). Закрытие — тап в любом месте или крест.
private struct FriendAvatarViewer: View {
    let userId: String
    let storedURL: String?
    let letter: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                PlinkStableAvatar(
                    url: PlinkAvatarURL.stable(userId: userId, stored: storedURL),
                    letter: letter,
                    size: min(geo.size.width - 32, geo.size.height - 160),
                    userId: userId
                )
                .clipShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 18)
                .accessibilityLabel("Закрыть")
            }
        }
        .preferredColorScheme(.dark)
    }
}
