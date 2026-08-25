// Plink/V4/V4ProfileViewLive.swift — профиль-первая архитектура (модель ВК):
// обложка сверху, аватар внахлёст на неё, имя и счётчики слева, ниже —
// разделы профиля (статистика, история, Плинк+) и строка «Общие настройки»,
// открывающая шитом все настройки Плинка и приложения (V4SettingsView ниже).
// В таббаре настроек нет: шесть кнопок теснили капсулу (22.08.2026).
// Поверхности — единый Liquid Glass слой (Plink/Design/Glass).

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - Лицо профиля

struct V4ProfileViewLive: View {
    let theme: V4Theme
    var store: V4ProfileStore?
    /// Оверлей «Оформление» живёт над корнем (zIndex 25) — из шита настроек
    /// его не показать, поэтому профиль пробрасывает включение наверх.
    @Binding var showAppearance: Bool
    @State private var currentAvatarURL: URL?

    @State private var showAvatarPicker = false
    @State private var showPersonalData = false
    @State private var showPremium = false
    @State private var showStats = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showAccountCenter = false
    @State private var showCoverPicker = false
    @State private var showStatusEditor = false
    /// Счётчик у строки «История просмотров» обновляется вживую.
    @ObservedObject private var historyManager = WatchHistoryManager.shared
    /// Карточка «Друзья» — живой стек аватарок из общего менеджера
    /// (тот же список, что и вкладка «Друзья»; загрузка — фоном в .task).
    @ObservedObject private var friendManager = FriendManager.shared

    /// Счётчики шапки — тот же /users/me/profile, что и экран статистики.
    @State private var social: UserSocialProfile?
    /// Тап по другу в рельсе — его профиль шитом (модель ВК). Без
    /// onWatchTogether/onMessage: действия живут на вкладке «Друзья».
    @State private var profileFriend: ProfileFriendPreview?

    private var isAdmin: Bool { store?.isAdmin == true }
    private var avatarURL: URL? { currentAvatarURL ?? store?.avatarURL }
    /// Обложка ложится под статус-бар, поэтому высота считается от
    /// физического верха экрана: ~62 pt статус-зоны + ~150 pt тела — как в ВК.
    /// Акцент лица профиля: обложка владельца, а не тема приложения. Своя
    /// фотография — тон считается с неё (PlinkCoverAccent), пресет отдаёт
    /// свой. Тема остаётся оформлением приложения: настройки, шиты, пикеры.
    @MainActor private var faceAccent: Color {
        if store?.usesCustomCover == true, let image = store?.customCoverImage {
            return PlinkCoverAccent.of(image)
        }
        return (store?.coverStyle ?? .dusk).accent
    }

    private let coverHeight: CGFloat = 212
    /// Насколько аватар нахлёстывается на нижний край обложки.
    private let avatarOverlap: CGFloat = 54

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                coverSlot
                avatarActionRow
                identityBlock
                countersCard
                watchRailCard
                friendsCard
                    .padding(.top, 12)
                settingsLinkGroup
                    .padding(.top, 14)
                sectionsGroup
                    .padding(.top, 14)
            }
            .padding(.bottom, 110)
            // Задник шапки: обложка + амбиент одним композитом, в котором
            // под аватар пробит прозрачный вырез (модель Discord) — лицо и
            // карты живут в свете обложки, а не на постороннем живом фоне.
            .background(alignment: .top) { headerBackdrop }
        }
        // Обложка — от физического верха экрана, статус-бар лежит на ней
        // (модель ВК). Без этого сверху остаётся полоса живого фона.
        .ignoresSafeArea(edges: .top)
        .foregroundStyle(V4.ink)
        .onAppear {
            // Дизайн-превью: `-plink.designsheet stats|history|premium|settings` открывает
            // шит сразу — скриншоты внутренних экранов без ручных тапов. Только DEBUG.
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-plink.designsheet"), args.indices.contains(i + 1) {
                switch args[i + 1] {
                case "stats": showStats = true
                case "history": showHistory = true
                case "premium": showPremium = true
                case "settings": showSettings = true
                case "personal": showPersonalData = true
                case "account": showAccountCenter = true
                case "cover": showCoverPicker = true
                case "status": showStatusEditor = true
                default: break
                }
            }
            #endif
        }
        .task { await reloadSocial() }
        .task {
            // Стек аватарок в карточке «Друзья»: если вкладку «Друзья» ещё
            // не открывали, список пуст — подтягиваем сами.
            if friendManager.friends.isEmpty {
                await friendManager.loadFriends()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkProfileDidUpdate)) { note in
            if let user = note.object as? User {
                store?.applyUser(user)
            } else {
                Task { await store?.load() }
            }
            Task { await reloadSocial() }
        }
        .sheet(isPresented: $showPersonalData, onDismiss: {
            Task { await store?.load() }
        }) {
            NavigationStack { PersonalDataView(asSheet: true) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAccountCenter, onDismiss: {
            Task { await store?.load() }
        }) {
            NavigationStack { AccountCenterView(store: store, asSheet: true) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCoverPicker) {
            V4CoverPickerSheet(theme: theme, store: store)
        }
        .sheet(isPresented: $showStatusEditor) {
            V4StatusEditorSheet(theme: theme, store: store)
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(store: store, theme: theme, onAvatarChanged: { url in
                currentAvatarURL = url
            }).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPremium) {
            PlinkPlusPaywall(trigger: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showStats) {
            V4StatsSheet(theme: theme)
        }
        .sheet(isPresented: $showHistory) {
            V4WatchHistorySheet(theme: theme)
        }
        .sheet(item: $profileFriend) { friend in
            NavigationStack {
                FriendProfileView(userId: friend.id, usernameHint: friend.username)
                    .toolbar {
                        V4SheetCloseToolbarItem { profileFriend = nil }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            V4SettingsView(theme: theme, store: store, openAppearance: {
                // Сначала уходит шит, потом включается оверлей — иначе
                // «Оформление» откроется под шитом и его не будет видно.
                showSettings = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation { showAppearance = true }
                }
            }, inSheet: true)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Обложка

    /// Полотно обложки без скримов — используется дважды: самой обложкой
    /// и амбиент-свечением под ней.
    @ViewBuilder private var coverCanvas: some View {
        if let custom = store?.customCoverImage, store?.usesCustomCover == true {
            // Color.clear.overlay — scaledToFill заполняет полотно, не
            // распирая ширину ZStack под размер исходного фото.
            Color.clear
                .overlay(Image(uiImage: custom).resizable().scaledToFill())
                .clipped()
        } else {
            (store?.coverStyle ?? .dusk).artwork()
        }
    }

    /// Зеркальная размытая копия обложки под её нижней кромкой: цвета на
    /// стыке совпадают, свечение тает к живому фону — обложка и страница
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

    /// Обложка как в ВК: полное полотно от края до края под статус-баром.
    /// Скримы — только на фото из галереи: у градиентных пресетов контраст
    /// статус-бара и тёмный низ уже вшиты в само полотно.
    private var coverPlate: some View {
        ZStack {
            coverCanvas
            if store?.usesCustomCover == true, store?.customCoverImage != nil {
                LinearGradient(colors: [.black.opacity(0.20), .clear, .black.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(height: coverHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Обложка + амбиент одним композитом с прозрачным вырезом под аватар
    /// (модель Discord): в зазоре видна сама страница, а не нарисованное
    /// кольцо — аватар «врезан» в шапку, к какой бы обложке он ни прилегал.
    /// Геометрия выреза выводится из констант ряда аватара: центр
    /// (18 + 56, coverHeight − 54 + 56), диаметр 112 + 2×7 зазора.
    private var headerBackdrop: some View {
        let strip = coverHeight - 40 + 400
        return ZStack(alignment: .top) {
            // Канва под композитом. Вырез открывает то, что лежит ниже
            // ВСЕГО профиля, а ниже лежит V4LivingBackground с ярким пятном
            // темы ровно в левом верхнем углу — под аватаром. Отсюда и брался
            // синий «ободок» на фиолетовой обложке. Своя канва закрывает
            // пятно и тает к низу полосы, чтобы живой фон вернулся без шва.
            LinearGradient(stops: [
                .init(color: V4.canvas, location: 0),
                .init(color: V4.canvas, location: min(0.95, (coverHeight + 120) / strip)),
                .init(color: V4.canvas.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: strip)
            .frame(maxWidth: .infinity)

            ZStack(alignment: .top) {
                coverAmbient
                coverPlate
            }
            .frame(height: strip, alignment: .top)
            .overlay(alignment: .topLeading) {
                Circle()
                    .frame(width: 126, height: 126)
                    .offset(x: 74 - 63, y: coverHeight + 2 - 63)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .frame(height: strip, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Место обложки в потоке: прозрачный слот (полотно рисует задник),
    /// сверху — только кисть смены обложки, ей нужен передний план для тапа.
    private var coverSlot: some View {
        Color.clear
            .frame(height: coverHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                // Кисть — в верхнем углу: нижняя кромка обложки занята
                // аватаром и кнопками «Редактировать»/«Поделиться».
                Button {
                    HapticManager.selection()
                    showCoverPicker = true
                } label: {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.ink)
                        .frame(width: 32, height: 32)
                        .plinkGlass(.control, in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сменить обложку")
                .padding(.top, 62)
                .padding(.trailing, 14)
            }
    }

    // MARK: Аватар внахлёст + действия

    /// Ряд под обложкой: аватар наполовину лежит на ней (как в ВК), справа —
    /// «Редактировать» и «Поделиться» по нижней линии аватара.
    private var avatarActionRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            avatarBlock

            // Колонка справа от аватара: статус-пузырь наверху ложится на
            // обложку рядом с верхней половиной аватара (модель Discord),
            // кнопки остаются по нижней линии аватара. Высота = аватару,
            // чтобы пузырь и кнопки не двигали друг друга.
            VStack(alignment: .leading, spacing: 0) {
                statusBubble
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)

                    Button {
                        HapticManager.selection()
                        showPersonalData = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                            Text("Редактировать")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(PlinkGlassButtonStyle(tint: faceAccent, height: 42, cornerRadius: 14))
                    .accessibilityHint("Имя, почта и личные данные")

                    if let username = store?.username, !username.isEmpty,
                       let shareURL = PlinkURLs.profileLink(username) {
                        ShareLink(item: shareURL) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .buttonStyle(PlinkGlassIconButtonStyle(diameter: 42))
                        .accessibilityLabel("Поделиться профилем")
                    }
                }
            }
            .frame(height: 112)
        }
        .padding(.horizontal, 18)
        // Нахлёст: ряд поднят на обложку, отрицательный нижний отступ
        // возвращает вертикальный ритм (offset место в layout не освобождает).
        .offset(y: -avatarOverlap)
        .padding(.bottom, -avatarOverlap)
    }

    /// Статус-«мысль» (модель Discord): пузырь с хвостом-точками у аватара,
    /// до двух строк на лице. Пустой — приглашение задать; тап открывает
    /// редактор, полный текст живёт в нём.
    private var statusBubble: some View {
        Button {
            HapticManager.selection()
            showStatusEditor = true
        } label: {
            PlinkStatusBubbleShell(interactive: true) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if store?.statusText.isEmpty != false {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(V4.muted)
                        Text("Что смотрим сегодня?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.muted)
                    } else {
                        Text(store?.statusText ?? "")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(V4.ink)
                    }
                }
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store?.statusText.isEmpty != false ? "Добавить статус" : "Статус: \(store?.statusText ?? ""). Изменить")
    }

    // MARK: Идентичность

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store?.displayName ?? "Загрузка…")
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.7)
                .foregroundStyle(isAdmin ? Color(red: 1, green: 0.3, blue: 0.4) : V4.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 7) {
                if let username = store?.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                if isAdmin {
                    roleChip(LocalizationManager.shared.string(.prAdmin), Color(red: 0.9, green: 0.1, blue: 0.2))
                }
                if store?.isPremium == true {
                    roleChip("PLINK+", Color(hex: "#A855F7"))
                }
            }
            .padding(.top, 5)

            // Строка присутствия (модель ВК): свой профиль всегда «в сети» —
            // тот же язык, что на профиле друга.
            Text("в сети")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color(hex: "#23A55A"))
                .padding(.top, 4)

            badgesRow
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("screen.profile")
    }

    /// Капсулы достижений (модель Discord: бейджи под именем). Приходят
    /// строками с сервера в /users/me/profile, известные коды маппятся в
    /// ProfileBadge; неизвестные (со старых/новых версий) не рисуем.
    @ViewBuilder private var badgesRow: some View {
        let badges = (social?.badges ?? []).compactMap(ProfileBadge.from)
        if !badges.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.rawValue) { badge in
                        HStack(spacing: 5) {
                            Image(systemName: badge.symbol)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(faceAccent)
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

    /// Аватар 112 pt без рисованных колец: зазор вокруг круга пробит в
    /// задник шапки (headerBackdrop), а зазор вокруг точки присутствия —
    /// сквозь сам аватар (destinationOut). Настоящий вырез Discord: в
    /// просветах видна страница, а не краска.
    private var avatarBlock: some View {
        Button {
            HapticManager.selection()
            showAvatarPicker = true
        } label: {
            Group {
                if let local = store?.localAvatarImage {
                    Image(uiImage: local).resizable().scaledToFill()
                } else if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), seed: AuthService.shared.currentUserValue?.id ?? store?.username ?? "", size: 112, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                        }
                    }
                } else {
                    V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), seed: AuthService.shared.currentUserValue?.id ?? store?.username ?? "", size: 112, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            // Вырез под точку: стирает арку аватара вокруг неё, центры
            // совпадают (смещение +2 компенсирует разницу диаметров 34/26).
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .frame(width: 34, height: 34)
                    .offset(x: 2, y: 2)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            // Точка присутствия (модель Discord) вместо бейджа камеры:
            // свой профиль всегда «в сети» — ты на него смотришь.
            // Редактируемость аватара не потерялась: тап по кругу
            // по-прежнему открывает пикер (как в ВК, без бейджа).
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(hex: "#23A55A"))
                    .frame(width: 26, height: 26)
                    .offset(x: -2, y: -2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Сменить аватар")
        .accessibilityValue("В сети")
    }

    private func roleChip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .tracking(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    /// Счётчики — стеклянной картой под именем: показатели в шапке, как в ВК.
    private var countersCard: some View {
        countersRow
            .padding(.vertical, 13)
            .plinkGlass(.control, cornerRadius: 20)
            .padding(.horizontal, 18)
            .padding(.top, 16)
    }

    /// Ряд «значение + подпись», тап ведёт в статистику.
    private var countersRow: some View {
        Button {
            HapticManager.selection()
            showStats = true
        } label: {
            // «Друзей» здесь больше нет: у друзей своя карточка-дверь ниже
            // (VK-модель), дублировать цифру в счётчиках — шум.
            HStack(spacing: 0) {
                counter(social?.watchHoursText ?? "—", "время")
                counterDivider
                counter(social.map { "\($0.filmsWatched)" } ?? "—", "фильмов")
                counterDivider
                counter(social.map { "\($0.roomsCreated)" } ?? "—", "комнат")
            }
            // .plain не бьёт по прозрачным зазорам лейбла — без явной формы
            // тап между колонками уходил в пустоту.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Статистика профиля")
        .accessibilityHint("Открывает подробную статистику и достижения")
    }

    // MARK: Недавно смотрел

    /// Рельса баннеров (модель ВК/Кинопоиска): постеры с названиями вместо
    /// текстовых строк. Заголовок — дверь в полную историю. Пустая история —
    /// карты нет: строка «История просмотров» остаётся в разделах ниже.
    @ViewBuilder private var watchRailCard: some View {
        if let history = social?.watchHistory, !history.isEmpty {
            ProfileWatchRailCard(history: history, accent: faceAccent) {
                showHistory = true
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    // MARK: Карточка «Друзья»

    /// Друзья для рельсы: серверное превью из /users/me/profile (порядок —
    /// закреплённые первыми), пока оно не пришло — живой список FriendManager,
    /// чтобы рельса не ждала второй сети.
    private var railFriends: [ProfileFriendPreview] {
        if let server = social?.friends, !server.isEmpty { return server }
        return friendManager.friends.filter { !$0.deleted }.map {
            ProfileFriendPreview(
                id: $0.id,
                username: $0.username,
                displayName: $0.displayName,
                avatarURL: $0.avatarURL,
                isOnline: $0.isOnline,
                lastSeenAt: $0.lastSeenAt
            )
        }
    }

    /// Блок друзей (модель ВК): рельса круглых аватарок с никами — тап по
    /// другу открывает его профиль, заголовок ведёт на вкладку «Друзья».
    /// Пока друзей нет — прежняя карточка-дверь «Найдите первых друзей».
    @ViewBuilder private var friendsCard: some View {
        let rail = railFriends
        if rail.isEmpty {
            friendsDoorCard
        } else {
            ProfileFriendsRailCard(
                friends: rail,
                friendsCount: social?.friendsCount ?? rail.count,
                onFriend: { profileFriend = $0 },
                onHeader: {
                    NotificationCenter.default.post(name: Notification.Name("plinkOpenFriendsTab"), object: nil)
                }
            )
            .padding(.horizontal, 18)
        }
    }

    /// Дверь на вкладку «Друзья» — пустое состояние блока (стек аватарок
    /// заменён рельсой выше, карточка осталась приглашением к первым друзьям).
    private var friendsDoorCard: some View {
        let alive = friendManager.friends.filter { !$0.deleted }
        let count = social?.friendsCount ?? alive.count
        let online = alive.filter(\.isOnline).count
        return Button {
            HapticManager.selection()
            NotificationCenter.default.post(name: Notification.Name("plinkOpenFriendsTab"), object: nil)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("Друзья")
                            .font(.system(size: 16, weight: .heavy))
                            .tracking(-0.3)
                            .foregroundStyle(V4.ink)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(V4.muted)
                        }
                    }
                    Text(count == 0
                         ? "Найдите первых друзей"
                         : (online > 0 ? "\(online) в сети" : "Сейчас никого в сети"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(online > 0 ? Color(hex: "#23A55A") : V4.muted)
                }

                Spacer(minLength: 8)

                if alive.isEmpty {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(faceAccent)
                } else {
                    // Стек внахлёст: до пяти живых аватарок, кольцо цвета
                    // канваса отделяет круги друг от друга.
                    HStack(spacing: -10) {
                        ForEach(alive.prefix(5)) { friend in
                            PlinkStableAvatar(
                                url: PlinkAvatarURL.stable(userId: friend.id, stored: friend.avatarURL),
                                letter: friend.initials,
                                size: 34,
                                userId: friend.id
                            )
                            .overlay(Circle().stroke(V4.canvas, lineWidth: 2))
                        }
                        if count > 5 {
                            ZStack {
                                Circle().fill(V4.canvas)
                                Text("+\(min(count - 5, 99))")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(V4.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 3)
                            }
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(V4.line, lineWidth: 1))
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // .plain не бьёт по прозрачным зазорам лейбла — тап в просвет
            // между текстом и стеком аватарок не открывал вкладку.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plinkGlass(.control, cornerRadius: 20)
        .padding(.horizontal, 18)
        .accessibilityLabel(count == 0 ? "Друзья. Найдите первых друзей" : "Друзья: \(count). \(online) в сети")
        .accessibilityHint("Открывает вкладку «Друзья»")
    }

    private var counterDivider: some View {
        Rectangle().fill(V4.line).frame(width: 1, height: 26)
    }

    private func counter(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.3)
                // Пока значения нет, прочерк не должен кричать белым:
                // приглушённый «—» читается как «ещё грузится», а не «сломано».
                .foregroundStyle(value == "—" ? V4.muted : V4.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V4.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Разделы

    private var sectionsGroup: some View {
        VStack(spacing: 0) {
            // Первая строка — единый центр аккаунта (модель «Управление
            // VK ID»): данные, вход, приватность и доступ в одном месте.
            // Без value: ник и так в шапке профиля прямо над карточкой,
            // а длинный @username отжимал заголовок в «Управление ак…».
            V4ProfileRow(
                icon: "person.crop.circle.badge.checkmark",
                tint: faceAccent,
                title: "Управление аккаунтом"
            ) { showAccountCenter = true }

            V4RowSeparator()

            V4ProfileRow(
                icon: "chart.bar.fill",
                tint: faceAccent,
                title: "Статистика и достижения"
            ) { showStats = true }

            V4RowSeparator()

            // История — контент, не идентичность: живёт своим экраном,
            // как статистика и настройки, а не лентой на лице профиля.
            V4ProfileRow(
                icon: "clock.arrow.circlepath",
                tint: faceAccent,
                title: "История просмотров",
                value: historyManager.history.isEmpty ? nil : "\(historyManager.history.count)"
            ) { showHistory = true }

            V4RowSeparator()

            V4ProfileRow(
                icon: "crown.fill",
                tint: V4.amber,
                title: "Плинк+ премиум",
                value: store?.isPremium == true ? "Активен" : "Оформить"
            ) { showPremium = true }
        }
        .padding(.vertical, 4)
        .plinkGlass(.control, cornerRadius: 24)
        .padding(.horizontal, 18)
    }

    /// Вход во все настройки Плинка и приложения — с лица профиля, шитом.
    /// Первая карта под счётчиками (23.08.2026): самый частый служебный
    /// маршрут не должен искаться взглядом под контентными разделами.
    /// Отдельной картой, а не строкой в sectionsGroup: там контент профиля,
    /// здесь — служебный маршрут.
    private var settingsLinkGroup: some View {
        VStack(spacing: 0) {
            V4ProfileRow(
                icon: "gearshape.fill",
                tint: faceAccent,
                title: "Общие настройки"
            ) { showSettings = true }
        }
        .padding(.vertical, 4)
        .plinkGlass(.control, cornerRadius: 24)
        .padding(.horizontal, 18)
    }

    private func reloadSocial() async {
        social = try? await SocialProfileService.fetchMe()
    }
}

// MARK: - Статус: пузырь и редактор

/// Статус-«мысль» (модель Discord): глухой тёмный пузырь с хвостом из двух
/// точек, шагающих вниз-влево к аватару. Материал непрозрачный — как у
/// Discord: реплика читается на любой обложке, стекло на фото тонуло.
/// Одна оболочка на оба профиля — свой (кнопка-редактор) и друг (чтение).
struct PlinkStatusBubbleShell<Content: View>: View {
    var interactive = false
    @ViewBuilder var content: () -> Content

    /// Материал пузыря: чуть светлее канваса, чтобы не сливаться с «полом»
    /// обложки, с волосяной обводкой по краю — как карточки Discord.
    private var fill: Color { Color(hex: "#1A1E27").opacity(0.97) }
    private var rim: Color { Color.white.opacity(0.10) }

    var body: some View {
        content()
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(rim, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) { tailDot(9).offset(x: -1, y: 8) }
            .overlay(alignment: .bottomLeading) { tailDot(5).offset(x: -10, y: 15) }
            .shadow(color: .black.opacity(0.30), radius: 10, y: 4)
    }

    /// Точка хвоста — тот же материал, что и пузырь: мысль из одного куска.
    private func tailDot(_ diameter: CGFloat) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(rim, lineWidth: 1))
            .frame(width: diameter, height: diameter)
    }
}

/// Шит «Свой статус» (модель Discord): одно поле, лимит 100 символов —
/// как на сервере (PATCH /profile обрезает и превращает «» в NULL).
/// Сохранение мгновенно локально через store.applyStatus, PATCH — фоном.
struct V4StatusEditorSheet: View {
    let theme: V4Theme
    var store: V4ProfileStore?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool
    private let limit = 100

    private var hadStatus: Bool { store?.statusText.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Свой статус")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(V4.ink)
            Text("Реплика в пузыре рядом с аватаром. Видна всем, кто откроет ваш профиль.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(V4.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            TextField("Чем занимаетесь?", text: $text, axis: .vertical)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(V4.ink)
                .tint(theme.accentColor)
                .lineLimit(2...3)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .plinkGlass(.control, cornerRadius: 16)
                .padding(.top, 18)
                .onChange(of: text) { _, newValue in
                    // Клиентский кламп зеркалит серверный: лишнее не даём
                    // даже набрать, чтобы сохранённое совпадало с видимым.
                    if newValue.count > limit { text = String(newValue.prefix(limit)) }
                }

            Text("\(text.count)/\(limit)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(V4.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 6)

            Button {
                HapticManager.selection()
                store?.applyStatus(text)
                dismiss()
            } label: {
                Text("Сохранить")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 48, cornerRadius: 16))
            .padding(.top, 14)

            if hadStatus {
                Button {
                    HapticManager.selection()
                    store?.applyStatus("")
                    dismiss()
                } label: {
                    Text("Убрать статус")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.38))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V4.canvas.ignoresSafeArea())
        .presentationDetents([.height(hadStatus ? 330 : 300)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .onAppear {
            text = store?.statusText ?? ""
            // Фокус после выката шита: клавиатура не дёргает анимацию.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }
}

// MARK: - Обложки профиля

/// Пресеты обложки — базовые градиенты «свет в тёмном зале»: цветной свет
/// живёт в верхней половине полотна, книзу каждый пресет тонет ровно в
/// V4.canvas — обложка и страница смыкаются по построению, без швов.
/// «Перелив» — живой переливающийся градиент, эксклюзив Плинк+.
/// Выбор хранится токеном `plink://cover/<id>` в поле coverURL — синк
/// между устройствами задаром; своя картинка — data-URL там же.
enum V4CoverStyle: String, CaseIterable, Identifiable {
    case dusk, neon, ember, midnight, aurora, graphite, shimmer

    var id: String { rawValue }

    static let urlPrefix = "plink://cover/"
    var remoteToken: String { Self.urlPrefix + rawValue }

    /// Живой пресет — анимируется и продаётся только с Плинк+.
    var isLive: Bool { self == .shimmer }

    /// Разбор сохранённого id с маппингом токенов прежних поколений
    /// (фото-пресеты и процедурные) — выбор со старых сборок не теряется.
    static func fromStored(_ id: String?) -> V4CoverStyle? {
        guard let id else { return nil }
        if let style = V4CoverStyle(rawValue: id) { return style }
        switch id {
        case "hall", "film": return .ember
        case "night": return .midnight
        case "beam": return .dusk
        case "marquee": return .neon
        default: return nil
        }
    }

    static func parse(_ raw: String?) -> V4CoverStyle? {
        guard let raw, raw.hasPrefix(urlPrefix) else { return nil }
        return fromStored(String(raw.dropFirst(urlPrefix.count)))
    }

    var title: String {
        switch self {
        case .dusk: return "Сумерки"
        case .neon: return "Неон"
        case .ember: return "Бархат"
        case .midnight: return "Полночь"
        case .aurora: return "Сияние"
        case .graphite: return "Графит"
        case .shimmer: return "Перелив"
        }
    }

    /// Акцент лица профиля. Берётся от самой обложки, а не от темы: кнопка
    /// «Редактировать», иконки разделов и рельса на фиолетовой обложке не
    /// имеют права быть синими только потому, что в настройках выбрана
    /// «Электрик». Не спектральное среднее полотна, а его сигнальный тон,
    /// поднятый до читаемого на стекле уровня.
    var accent: Color {
        switch self {
        case .dusk: return Color(hex: "#7C5CFF")
        case .neon: return Color(hex: "#4C6BFF")
        case .ember: return Color(hex: "#FF7A52")
        case .midnight: return Color(hex: "#4FB4FF")
        case .aurora: return Color(hex: "#2FD9A6")
        case .graphite: return Color(hex: "#93A7C8")
        case .shimmer: return Color(hex: "#B24BE8")
        }
    }

    /// Небо пресета: три цвета по диагонали + цвет и точка светового пятна.
    /// Тёмный «пол» и виньетку добавляет PlinkCoverGradient — один на всех.
    fileprivate var spec: PlinkCoverSpec {
        switch self {
        case .dusk: return .init(
            sky: [Color(hex: "#5D4BD4"), Color(hex: "#9A55C4"), Color(hex: "#3A1E52")],
            glow: Color(hex: "#FFB2C4"), glowCenter: .init(x: 0.85, y: 0.10), glowStrength: 0.55)
        case .neon: return .init(
            sky: [Color(hex: "#2743E0"), Color(hex: "#7A3BFF"), Color(hex: "#3E1260")],
            glow: Color(hex: "#3EE8FF"), glowCenter: .init(x: 0.12, y: 0.08), glowStrength: 0.60)
        case .ember: return .init(
            sky: [Color(hex: "#8C2231"), Color(hex: "#5A1220"), Color(hex: "#20070E")],
            glow: Color(hex: "#FF9A5A"), glowCenter: .init(x: 0.78, y: 0.10), glowStrength: 0.50)
        case .midnight: return .init(
            sky: [Color(hex: "#16264F"), Color(hex: "#0C1530"), Color(hex: "#05070F")],
            glow: Color(hex: "#4FB4FF"), glowCenter: .init(x: 0.20, y: 0.08), glowStrength: 0.38)
        case .aurora: return .init(
            sky: [Color(hex: "#0E4F46"), Color(hex: "#1E8F6E"), Color(hex: "#0F2B4A")],
            glow: Color(hex: "#59FFC9"), glowCenter: .init(x: 0.72, y: 0.10), glowStrength: 0.45)
        case .graphite: return .init(
            sky: [Color(hex: "#3A4150"), Color(hex: "#262B36"), Color(hex: "#14171D")],
            glow: Color(hex: "#8FA3C4"), glowCenter: .init(x: 0.80, y: 0.08), glowStrength: 0.30)
        case .shimmer: return .init(
            sky: [Color(hex: "#6C3BFF"), Color(hex: "#B03BD9"), Color(hex: "#22306E")],
            glow: Color(hex: "#4FD9FF"), glowCenter: .init(x: 0.25, y: 0.10), glowStrength: 0.60)
        }
    }

    /// Полотно пресета: статичный градиент или живой «Перелив».
    @ViewBuilder func artwork() -> some View {
        if isLive {
            PlinkShimmerCover(spec: spec)
        } else {
            PlinkCoverGradient(spec: spec)
        }
    }
}

/// Рецепт градиентной обложки: диагональное «небо», световое пятно.
fileprivate struct PlinkCoverSpec {
    let sky: [Color]
    let glow: Color
    let glowCenter: UnitPoint
    let glowStrength: Double
}

/// Базовый градиент обложки: небо по диагонали, мягкое световое пятно
/// (plusLighter — свет складывается, а не пачкает), тёмный «пол» из
/// V4.canvas — нижняя кромка совпадает со страницей до канала.
fileprivate struct PlinkCoverGradient: View {
    let spec: PlinkCoverSpec
    /// Сдвиг пятна по X в долях ширины — «Перелив» водит светом вживую.
    var glowDrift: CGFloat = 0

    var body: some View {
        LinearGradient(colors: spec.sky, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(
                    colors: [spec.glow.opacity(spec.glowStrength), .clear],
                    center: UnitPoint(x: spec.glowCenter.x + glowDrift, y: spec.glowCenter.y),
                    startRadius: 0, endRadius: 320
                )
                .blendMode(.plusLighter)
            )
            .overlay(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: V4.canvas.opacity(0.92), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
    }
}

/// Живая обложка Плинк+: медленный дрейф оттенка (±38° за ~9 с) и света —
/// перелив, а не мигание. TimelineView с шагом 1/20 с — GPU-дёшево, без
/// таймеров в модели; в пикере миниатюра переливается той же вьюхой.
fileprivate struct PlinkShimmerCover: View {
    let spec: PlinkCoverSpec

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            PlinkCoverGradient(spec: spec, glowDrift: CGFloat(sin(t * 0.45)) * 0.28)
                .hueRotation(.degrees(sin(t * 0.7) * 38))
        }
    }
}

/// Пикер обложки: сетка живых миниатюр (тот же artwork) + плитка «Своя»
/// из галереи. Выбор применяется мгновенно локально и уезжает на сервер
/// фоном — пресет токеном, своё фото — data-URL в том же coverURL.
struct V4CoverPickerSheet: View {
    /// Что выбрано в сетке: пресет или собственное фото.
    private enum CoverChoice: Equatable {
        case preset(V4CoverStyle)
        case custom
    }

    let theme: V4Theme
    var store: V4ProfileStore?
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CoverChoice
    /// Свежевыбранное из галереи (уже кроп 2:1); nil — не перевыбирали.
    @State private var pickedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var photosDeniedAlert = false
    @State private var loadError: String?
    /// Живой «Перелив» — эксклюзив Плинк+: тап без подписки ведёт в пейволл.
    @State private var showPlusPaywall = false

    init(theme: V4Theme, store: V4ProfileStore?) {
        self.theme = theme
        self.store = store
        _selected = State(initialValue: store?.usesCustomCover == true
                          ? .custom
                          : .preset(store?.coverStyle ?? .dusk))
    }

    var body: some View {
        ZStack {
            V4.canvas.ignoresSafeArea()
            RadialGradient(
                colors: [theme.accentColor.opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    V4Heading(eyebrow: "Оформление профиля", title: "Обложка")
                    Spacer(minLength: 0)
                    V4SheetCloseButton { dismiss() }
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 14
                ) {
                    ForEach(V4CoverStyle.allCases) { style in
                        coverCell(style)
                    }
                    customCell
                }

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(V4.danger)
                }

                Spacer(minLength: 0)

                SettingsPrimaryButton(title: "Применить") {
                    if apply() { dismiss() }
                }
            }
            .padding(18)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $showPlusPaywall) {
            PlinkPlusPaywall(trigger: .theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }

    /// Применяет выбор; false — применить нельзя (живой пресет без Плинк+,
    /// показан пейволл) и шит закрывать не надо.
    private func apply() -> Bool {
        switch selected {
        case .preset(let style):
            // Подстраховка гейта: живой пресет мог остаться выбранным с
            // истёкшей подпиской — тогда в пейволл, а не мимо кассы.
            guard !style.isLive || store?.isPremium == true else {
                showPlusPaywall = true
                return false
            }
            store?.applyCover(style)
        case .custom:
            if let image = pickedImage {
                store?.applyCustomCover(image)
            } else if store?.usesCustomCover != true, let saved = store?.customCoverImage {
                // Плитка выбрана без перевыбора фото — заливаем сохранённое.
                store?.applyCustomCover(saved)
            }
            // usesCustomCover уже true и фото не меняли — PATCH не нужен.
        }
        return true
    }

    /// Флоу как у аватара: сперва системный запрос доступа (если первый
    /// раз), затем PhotosPicker — он работает и после «Не разрешать».
    private func pickFromGallery() async {
        let access = await PlinkPermissions.preparePhotoPicker()
        switch access {
        case .authorized, .systemPickerOnly:
            try? await Task.sleep(nanoseconds: 150_000_000)
            showPhotosPicker = true
        case .blocked:
            photosDeniedAlert = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        loadError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                loadError = "Не удалось загрузить фото"
                return
            }
            let cropped = Self.cropToCover(image)
            withAnimation(.easeInOut(duration: 0.15)) {
                pickedImage = cropped
                selected = .custom
            }
            HapticManager.selection()
        } catch {
            loadError = "Ошибка: \(error.localizedDescription)"
        }
    }

    /// Центральный кроп 2:1 и даунскейл до 1500×750 — как пресеты. Дальше
    /// стор сожмёт в JPEG под data-URL (bodyLimit сервера — 2 МБ).
    private static func cropToCover(_ image: UIImage) -> UIImage {
        // scale = 1: дефолтный рендерер берёт масштаб экрана и утроил бы
        // пиксели. Заодно нормализует EXIF-ориентацию — cgImage.cropping
        // режет «сырые» координаты сенсора, портретные фото кропились бы
        // боком.
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let pxSize = CGSize(width: image.size.width * image.scale,
                            height: image.size.height * image.scale)
        let normalized = UIGraphicsImageRenderer(size: pxSize, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pxSize))
        }
        let cropW = min(pxSize.width, pxSize.height * 2)
        let cropH = cropW / 2
        let cropRect = CGRect(x: (pxSize.width - cropW) / 2,
                              y: (pxSize.height - cropH) / 2,
                              width: cropW, height: cropH)
        guard let cg = normalized.cgImage?.cropping(to: cropRect) else { return normalized }
        // Маленькие фото не апскейлим — качества это не добавит.
        let outW = min(CGFloat(1500), cropW)
        let out = CGSize(width: outW, height: outW / 2)
        return UIGraphicsImageRenderer(size: out, format: fmt).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: out))
        }
    }

    private func coverCell(_ style: V4CoverStyle) -> some View {
        let isSelected = selected == .preset(style)
        let locked = style.isLive && store?.isPremium != true
        return Button {
            HapticManager.selection()
            if locked {
                showPlusPaywall = true
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { selected = .preset(style) }
            }
        } label: {
            VStack(spacing: 7) {
                style.artwork()
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .modifier(CoverCellChrome(theme: theme, isSelected: isSelected))
                    .overlay(alignment: .topLeading) {
                        // Живой пресет подписан всегда: у подписчика — знак
                        // эксклюзива, у остальных — что тап ведёт в Плинк+.
                        if style.isLive {
                            Text("PLINK+")
                                .font(.system(size: 8.5, weight: .black))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Color(hex: "#A855F7"), in: Capsule())
                                .padding(6)
                        }
                    }
                Text(style.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? V4.ink : V4.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "Обложка «\(style.title)» — доступна с Плинк+" : "Обложка «\(style.title)»")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Плитка «Своя»: без фото — приглашение с плюсом (тап открывает
    /// галерею); с фото — миниатюра, тап выбирает, глиф в углу — перевыбор.
    private var customCell: some View {
        let isSelected = selected == .custom
        let shown = pickedImage ?? store?.customCoverImage
        return Button {
            HapticManager.selection()
            if shown == nil {
                Task { await pickFromGallery() }
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { selected = .custom }
            }
        } label: {
            VStack(spacing: 7) {
                Group {
                    if let shown {
                        Color.clear
                            .overlay(Image(uiImage: shown).resizable().scaledToFill())
                            .clipped()
                    } else {
                        ZStack {
                            V4.surface
                            VStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(theme.accentColor)
                                Text("Из галереи")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(V4.muted)
                            }
                        }
                    }
                }
                .frame(height: 86)
                .frame(maxWidth: .infinity)
                .modifier(CoverCellChrome(theme: theme, isSelected: isSelected))
                .overlay(alignment: .bottomTrailing) {
                    if shown != nil {
                        // Перевыбор фото — отдельная мишень, не сбивающая
                        // основной тап-выбор плитки.
                        Button {
                            HapticManager.selection()
                            Task { await pickFromGallery() }
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(V4.ink)
                                .frame(width: 22, height: 22)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .accessibilityLabel("Выбрать другое фото")
                    }
                }
                Text("Своя")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? V4.ink : V4.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Своя обложка из галереи")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Общая рамка плитки пикера: скругление, обводка выбора, чекмарк.
private struct CoverCellChrome: ViewModifier {
    let theme: V4Theme
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accentColor : V4.line,
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    ZStack {
                        Circle().fill(theme.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(theme.buttonTextColor)
                    }
                    .frame(width: 20, height: 20)
                    .padding(6)
                }
            }
    }
}

// MARK: - Строка раздела (общая для лица профиля и настроек)

/// Иконка в мягком цветном чипе + заголовок + значение + шеврон.
struct V4ProfileRow: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String? = nil
    var danger: Bool = false
    /// Шеврон — обещание перехода; строки-действия («Выйти») его не носят.
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.14))
                    Circle().stroke(tint.opacity(0.22), lineWidth: 1)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(danger ? V4.danger : V4.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let value {
                    Text(value)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(V4.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Волосяной разделитель строк — с отступом под чип иконки.
struct V4RowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(V4.line)
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

// MARK: - Экран «Статистика и достижения»

struct V4StatsSheet: View {
    let theme: V4Theme
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserSocialProfile?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                V4.canvas.ignoresSafeArea()
                RadialGradient(
                    colors: [theme.accentColor.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if isLoading {
                            skeleton
                        } else if let loadError {
                            V4ProfileStateCard(
                                theme: theme,
                                icon: "wifi.exclamationmark",
                                iconTint: V4.amber,
                                title: loadError,
                                message: "Проверь соединение — и попробуем ещё раз.",
                                buttonTitle: "Повторить"
                            ) {
                                Task { await reload() }
                            }
                            .padding(.top, 48)
                        } else {
                            statsGrid
                            achievements
                            if let joined = joinedLine {
                                Text(joined)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(V4.muted)
                                    .padding(.top, 18)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Статистика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Крестик закрытия — всегда справа (единый паттерн шитов V4),
                // обновление — слева.
                ToolbarItem(placement: .topBarLeading) {
                    if !isLoading {
                        Button {
                            HapticManager.selection()
                            Task { await reload() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .tint(V4.ink)
                        .accessibilityLabel("Обновить статистику")
                    }
                }
                V4SheetCloseToolbarItem { dismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task { await reload() }
    }

    // Сетевая ошибка не маскируется под нули: пока данных нет — «—»,
    // ноль появляется только когда сервер действительно вернул 0.
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statTile("clock.fill", profile?.watchHoursText ?? "—", "Часы в Plink")
            statTile("film.fill", profile.map { "\($0.filmsWatched)" } ?? "—", "Фильмов вместе")
            statTile("person.2.fill", profile.map { "\($0.friendsCount)" } ?? "—", "Друзей")
            statTile("rectangle.stack.badge.play.fill", profile.map { "\($0.roomsCreated)" } ?? "—", "Комнат создано")
        }
    }

    private func statTile(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(theme.accentColor.opacity(0.14))
                Circle().stroke(theme.accentColor.opacity(0.22), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accentColor)
            }
            .frame(width: 32, height: 32)

            Spacer(minLength: 10)

            Text(value)
                .font(.system(size: 27, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(V4.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(V4.muted)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .plinkGlass(.control, cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    @ViewBuilder
    private var achievements: some View {
        Text("Достижения".uppercased())
            .font(.system(size: 10.56, weight: .heavy))
            .tracking(1.16)
            .foregroundStyle(V4.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
            .padding(.bottom, 10)

        if let badges = profile?.badges, !badges.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(badges, id: \.self) { code in
                    let badge = ProfileBadge.from(code: code)
                    HStack(spacing: 7) {
                        Image(systemName: badge?.symbol ?? "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(V4.amber)
                        Text(badge?.title ?? code)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(V4.ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .plinkGlass(.control, cornerRadius: 12)
                }
            }
            .accessibilityLabel("Достижения")
        } else {
            HStack(spacing: 10) {
                Image(systemName: "trophy")
                    .foregroundStyle(V4.muted)
                Text(LocalizationManager.shared.string(.vpAchievementsHint))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(V4.muted)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(V4.cardBG.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
        }
    }

    private var skeleton: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(V4.cardBG)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(V4.line, lineWidth: 1))
                    .frame(height: 146)
            }
        }
        .modifier(V4ProfileGhostPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загружаем статистику")
    }

    private var joinedLine: String? {
        guard let joined = profile?.joinedAt else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "LLLL yyyy"
        return "В Plink с \(df.string(from: joined))"
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await SocialProfileService.fetchMe()
            loadError = nil
        } catch {
            loadError = "Не удалось загрузить статистику"
        }
    }
}

// MARK: - Экран «Общие настройки»

/// Все настройки Плинка и приложения: аккаунт, приложение,
/// администрирование и выход. На iPhone открывается шитом со строки
/// «Общие настройки» на лице профиля (22.08.2026: шестая вкладка теснила
/// таббар, а маршрут не ежедневный), на iPad — секция сайдбара.
struct V4SettingsView: View {
    let theme: V4Theme
    var store: V4ProfileStore?
    /// Оверлей «Оформление» живёт над корнем (zIndex 25) — из-под шита его
    /// не видно, поэтому включение отдаёт наружу: владелец сам закрывает
    /// шит и поднимает оверлей.
    var openAppearance: () -> Void
    /// true — открыт шитом (iPhone): свой фон-канвас, крестик закрытия,
    /// короче нижний отступ. false — секция сайдбара iPad.
    var inSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var showAdminPanel = false

    #if DEBUG
    /// Дизайн-превью: `-plink.designrow notifications|playback|help` пушит
    /// внутренний экран хаба сразу — скриншоты без ручных тапов.
    @State private var debugRow: String?
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                // Шит рисует фон сам — под ним нет корневого канваса вкладок.
                if inSheet {
                    V4.canvas.ignoresSafeArea()
                    RadialGradient(
                        colors: [theme.accentColor.opacity(0.10), .clear],
                        center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 420
                    )
                    .ignoresSafeArea()
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 12) {
                            V4Heading(eyebrow: "Plink и приложение", title: "Общие настройки")
                            Spacer(minLength: 0)
                            if inSheet {
                                V4SheetCloseButton { dismiss() }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, inSheet ? 18 : 10)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("screen.settings")

                        VStack(spacing: 0) {
                            // «Управление аккаунтом» здесь больше не живёт
                            // (23.08.2026): та же строка стоит первой картой
                            // sectionsGroup на лице профиля — дубль в хабе
                            // заставлял гадать, какой из двух входов «настоящий».
                            // Хаб отвечает только за приложение.
                            settingsGroup("Приложение") {
                                V4ProfileRow(icon: "circle.lefthalf.filled", tint: theme.accentColor, title: "Оформление", value: themeDisplayName) {
                                    openAppearance()
                                }
                                V4RowSeparator()
                                pushRow("bell.fill", "Уведомления") { NotificationsView() }
                                V4RowSeparator()
                                pushRow("play.fill", "Воспроизведение") { PlaybackSettingsView() }
                                V4RowSeparator()
                                pushRow("questionmark.circle.fill", "Помощь") { HelpView() }
                            }

                            if store?.isAdmin == true {
                                settingsGroup("Администрирование") {
                                    V4ProfileRow(icon: "shield.lefthalf.filled", tint: Color(red: 1, green: 0.3, blue: 0.4), title: "Админ-панель") {
                                        showAdminPanel = true
                                    }
                                }
                            }

                            // «Почему Plink безопаснее» удалена (22.08.2026):
                            // сравнительный питч против конкурента на языке
                            // разработчика, а гарантии и так закреплены в условиях
                            // пользования и политике конфиденциальности.
                            // «Удалить аккаунт» переехала в «Управление
                            // аккаунтом» → «Опасная зона» (модель VK ID):
                            // здесь остаётся только выход из приложения.
                            settingsGroup("Выход") {
                                V4ProfileRow(icon: "arrow.right.square.fill", tint: V4.danger, title: LocalizationManager.shared.string(.prSignOut), danger: true, showsChevron: false) {
                                    AuthService.shared.signOutLocally()
                                }
                            }

                            versionFooter
                        }
                    }
                    // В шите крестик закрывает экран сразу за контентом — 40;
                    // полноэкранная деталь iPad держит прежний нижний запас.
                    .padding(.bottom, inSheet ? 40 : 110)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdminPanel) {
                AdminRootView().preferredColorScheme(.dark)
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
                case "notifications": NotificationsView().preferredColorScheme(.dark)
                case "playback": PlaybackSettingsView().preferredColorScheme(.dark)
                case "help": HelpView().preferredColorScheme(.dark)
                default: EmptyView()
                }
            }
            #endif
        }
        .foregroundStyle(V4.ink)
    }

    /// Версия приложения — опора для саппорта: «какая у тебя версия?»
    /// отвечается взглядом, без раскопок в системных настройках.
    private var versionFooter: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return Text("Plink \(v) (\(b))")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(V4.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var themeDisplayName: String {
        PlinkPlusLiveTheme.resolve(UserDefaults.standard.integer(forKey: "plink.liveTheme"))?.name ?? theme.name
    }

    /// Строка-переход внутри NavigationStack настроек.
    private func pushRow<D: View>(
        _ icon: String,
        _ title: String,
        value: String? = nil,
        danger: Bool = false,
        @ViewBuilder destination: @escaping () -> D
    ) -> some View {
        NavigationLink {
            destination()
                .preferredColorScheme(.dark)
        } label: {
            V4ProfileRowLabel(icon: icon, tint: danger ? V4.danger : theme.accentColor, title: title, value: value, danger: danger)
        }
        .buttonStyle(.plain)
    }

    private func settingsGroup<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.56, weight: .heavy))
                .tracking(1.16)
                .foregroundStyle(V4.muted)
                .padding(.horizontal, 19)
                .padding(.bottom, 9)
            VStack(spacing: 0) { content() }
                .padding(.vertical, 4)
                .plinkGlass(.control, cornerRadius: 24)
                .padding(.horizontal, 18)
        }
        .padding(.bottom, 22)
    }
}

/// Контент строки без Button — для NavigationLink label.
struct V4ProfileRowLabel: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String? = nil
    var danger: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Circle().stroke(tint.opacity(0.22), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 34, height: 34)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(danger ? V4.danger : V4.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(V4.muted)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(V4.muted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
}

// MARK: - Общие состояния

/// Каркас ошибки в языке приложения: иконка в мягком круге, заголовок,
/// одна строка объяснения и кнопка следующего шага (единый стиль с «Комнатами»).
struct V4ProfileStateCard: View {
    let theme: V4Theme
    let icon: String
    let iconTint: Color
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(iconTint.opacity(0.13))
                Circle().stroke(iconTint.opacity(0.22), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 58, height: 58)
            .padding(.bottom, 14)

            Text(title)
                .font(.system(size: 16.5, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(V4.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .lineSpacing(2)
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            Button(buttonTitle) {
                HapticManager.impact(.light)
                action()
            }
            .buttonStyle(
                PlinkProminentButtonStyle(
                    tint: theme.accentColor,
                    textColor: theme.buttonTextColor,
                    height: 46,
                    cornerRadius: 15,
                    fillsWidth: false
                )
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 22)
    }
}

/// Пульс скелета загрузки: 0.55 ↔ 1.0; при Reduce Motion — статичные 0.8.
struct V4ProfileGhostPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.8 : (dim ? 0.55 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { if !reduceMotion { dim = true } }
    }
}


// MARK: - AvatarPickerSheet (PhotosUI + server upload + local persist)

struct AvatarPickerSheet: View {
    var store: V4ProfileStore?
    /// Шит рисовался акцентом Cinema2026 — третьей палитрой,
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
                // Вторичное действие — стекло; единственная белая CTA шита — «Готово».
                Button {
                    Task { await pickFromGallery() }
                } label: {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().tint(V4.ink)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Text(uploading ? "Сохраняем…" : "Выбрать из галереи")
                    }
                }
                .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 52, cornerRadius: 14))
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
                        .foregroundStyle(V4.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                SettingsPrimaryButton(title: "Готово", isLoading: uploading) {
                    Task { await doneTapped() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 32)
            .background {
                ZStack {
                    V4.canvas
                    RadialGradient(
                        colors: [theme.accentColor.opacity(0.10), .clear],
                        center: UnitPoint(x: 0.5, y: 0),
                        startRadius: 0,
                        endRadius: 420
                    )
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Аватар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                V4SheetCloseToolbarItem { dismiss() }
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


