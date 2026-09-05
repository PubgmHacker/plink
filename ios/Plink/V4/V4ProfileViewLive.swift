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
    /// Итог проходит через `legible`: этим цветом заливается кнопка с белой
    /// подписью, и светлая обложка не имеет права её погасить.
    @MainActor private var faceAccent: Color {
        PlinkCoverAccent.legible(rawFaceAccent)
    }

    @MainActor private var rawFaceAccent: Color {
        #if DEBUG
        if let forced = V4CoverStyle.debugForced { return forced.accent }
        #endif
        if store?.usesCustomCover == true, let image = store?.customCoverImage {
            return PlinkCoverAccent.of(image)
        }
        return activeCoverStyle.accent
    }

    /// Пресет, которым сейчас живёт шапка. В Debug подменяется флагом
    /// `-plink.designcover <id>`.
    private var activeCoverStyle: V4CoverStyle {
        #if DEBUG
        if let forced = V4CoverStyle.debugForced { return forced }
        #endif
        return store?.coverStyle ?? .dusk
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
            V4StatusEditorSheet(accent: faceAccent, store: store)
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
            ProfileStatsSheet(profile: social, accent: faceAccent, isSelf: true)
        }
        .sheet(isPresented: $showHistory) {
            V4WatchHistorySheet(accent: faceAccent, entries: social?.watchHistory ?? [])
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
        if let custom = store?.customCoverImage, store?.usesCustomCover == true,
           !isCoverForced {
            // Color.clear.overlay — scaledToFill заполняет полотно, не
            // распирая ширину ZStack под размер исходного фото.
            Color.clear
                .overlay(Image(uiImage: custom).resizable().scaledToFill())
                .clipped()
        } else {
            activeCoverStyle.artwork()
        }
    }

    /// true — обложка подменена QA-флагом; своё фото тогда не мешает.
    private var isCoverForced: Bool {
        #if DEBUG
        return V4CoverStyle.debugForced != nil
        #else
        return false
        #endif
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
                .plinkHitTarget(32)
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
                        Text(LocalizationManager.shared.string(.frStoryAddStatus))
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
            // Name + seals (Telegram model): the administrator seal sits
            // right after the name instead of recolouring it, Plink+ gets
            // its own star seal. Nothing on the face is tinted by the theme.
            HStack(alignment: .center, spacing: 6) {
                Text(store?.displayName ?? "Загрузка…")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.7)
                    .foregroundStyle(V4.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isAdmin {
                    PlinkIdentitySeal(kind: .admin, size: 21)
                }
                if store?.isPremium == true {
                    PlinkIdentitySeal(kind: .plus, size: 21)
                }
            }

            HStack(spacing: 7) {
                // Ник под именем — только когда он не повторяет имя: у
                // аккаунта без заданного имени displayName берётся из
                // username, и лицо профиля читалось «testdev» / «@testdev».
                if let username = store?.username, !username.isEmpty,
                   username.caseInsensitiveCompare(store?.displayName ?? "") != .orderedSame {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
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
                counter(social.map { "\($0.filmsWatched)" } ?? "—",
                        PlinkPlural.films(social?.filmsWatched ?? 0))
                counterDivider
                counter(social.map { "\($0.roomsCreated)" } ?? "—",
                        PlinkPlural.rooms(social?.roomsCreated ?? 0))
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
    /// Face accent (cover colour) — the editor belongs to the profile face,
    /// not to the app theme.
    let accent: Color
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
                .tint(accent)
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
            .buttonStyle(PlinkGlassButtonStyle(tint: accent, height: 48, cornerRadius: 16))
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
    // Бесплатная витрина.
    case dusk, ember, midnight, graphite
    // Живые — Плинк+.
    case shimmer, projector, reel, bulbs, drift
    // Сняты с витрины, но живут у тех, кто их уже выбрал.
    case neon, aurora

    var id: String { rawValue }

    static let urlPrefix = "plink://cover/"
    var remoteToken: String { Self.urlPrefix + rawValue }

    #if DEBUG
    /// QA-рельса: `-plink.designcover <id>` показывает обложку в шапке, не
    /// трогая аккаунт, подписку и сервер. Только Debug.
    static let debugForced: V4CoverStyle? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-plink.designcover"), i + 1 < args.count else { return nil }
        return V4CoverStyle.fromStored(args[i + 1])
    }()
    #endif

    /// Витрина бесплатных: четыре разных полотна, а не шесть оттенков
    /// одного. `neon` и `aurora` из неё сняты — но остаются валидными и
    /// показываются тому, у кого уже стоят (см. freeShelf(current:)).
    static let freeCatalog: [V4CoverStyle] = [.dusk, .midnight, .ember, .graphite]

    /// Витрина Плинк+: пять живых полотен, каждое на своём движении —
    /// перелив, луч, плёнка, лампы, пыль в луче.
    static let plusCatalog: [V4CoverStyle] = [.shimmer, .projector, .reel, .bulbs, .drift]

    /// Бесплатная полка для конкретного человека: каталог плюс его
    /// собственная легаси-обложка, если он на ней сидит. Забрать уже
    /// выбранное — регресс, показывать всем снятое — мусор.
    static func freeShelf(current: V4CoverStyle?) -> [V4CoverStyle] {
        guard let current, !freeCatalog.contains(current), !plusCatalog.contains(current) else {
            return freeCatalog
        }
        return freeCatalog + [current]
    }

    /// Живой пресет — анимируется и продаётся только с Плинк+.
    var isLive: Bool { motion != .none }

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
        case .projector: return "Проектор"
        case .reel: return "Плёнка"
        case .bulbs: return "Огни"
        case .drift: return "Пылинки"
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
        case .projector: return Color(hex: "#FFC46B")
        case .reel: return Color(hex: "#7E93C4")
        case .bulbs: return Color(hex: "#FF5F8A")
        case .drift: return Color(hex: "#6FD0FF")
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
        case .projector: return .init(
            sky: [Color(hex: "#1A1712"), Color(hex: "#241C14"), Color(hex: "#0B0908")],
            glow: Color(hex: "#FFD79A"), glowCenter: .init(x: 0.08, y: 0.06), glowStrength: 0.30)
        case .reel: return .init(
            sky: [Color(hex: "#232833"), Color(hex: "#171B23"), Color(hex: "#0A0C10")],
            glow: Color(hex: "#DCE6F5"), glowCenter: .init(x: 0.50, y: 0.05), glowStrength: 0.22)
        case .bulbs: return .init(
            sky: [Color(hex: "#3B0E2C"), Color(hex: "#5A1030"), Color(hex: "#180411")],
            glow: Color(hex: "#FF7FA6"), glowCenter: .init(x: 0.50, y: 0.02), glowStrength: 0.30)
        case .drift: return .init(
            sky: [Color(hex: "#0E2340"), Color(hex: "#123255"), Color(hex: "#050B16")],
            glow: Color(hex: "#7FD8FF"), glowCenter: .init(x: 0.68, y: 0.06), glowStrength: 0.34)
        }
    }

    /// Чем полотно живёт. Один TimelineView на плитку — различается только
    /// то, что он рисует поверх общего градиента.
    fileprivate var motion: PlinkCoverMotion {
        switch self {
        case .dusk, .neon, .ember, .midnight, .aurora, .graphite: return .none
        case .shimmer: return .shimmer
        case .projector: return .projector
        case .reel: return .reel
        case .bulbs: return .bulbs
        case .drift: return .drift
        }
    }

    /// Полотно пресета. `preview: true` — миниатюра в пикере: тот же
    /// рисунок на вдвое более редком тике, чтобы полка из пяти живых
    /// обложек не жгла кадры.
    @ViewBuilder func artwork(preview: Bool = false) -> some View {
        if motion == .none {
            PlinkCoverGradient(spec: spec)
        } else {
            PlinkLiveCover(spec: spec, motion: motion, preview: preview)
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

/// Чем живёт полотно. `.none` — статичный пресет бесплатной полки;
/// остальные пять рисуются одним и тем же Canvas'ом поверх общего неба и
/// ПОД «полом», иначе луч и лампы затирали бы стык со страницей.
fileprivate enum PlinkCoverMotion: Equatable {
    case none, shimmer, projector, reel, bulbs, drift
}

/// Базовый градиент обложки: небо по диагонали, мягкое световое пятно
/// (plusLighter — свет складывается, а не пачкает), живой слой и тёмный
/// «пол» из V4.canvas — нижняя кромка совпадает со страницей до канала.
fileprivate struct PlinkCoverGradient: View {
    let spec: PlinkCoverSpec
    /// Сдвиг пятна по X в долях ширины — живые пресеты водят светом.
    var glowDrift: CGFloat = 0
    var motion: PlinkCoverMotion = .none
    /// Время анимации в секундах; для статичных пресетов не используется.
    var t: Double = 0

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
            .overlay {
                if motion != .none && motion != .shimmer {
                    PlinkCoverMotionCanvas(motion: motion, tint: spec.glow, t: t)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: V4.canvas.opacity(0.92), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
    }
}

/// Живая обложка Плинк+. Один TimelineView на полотно; `preview` — тик
/// вдвое реже для миниатюр пикера, чтобы полка из пяти живых обложек не
/// жгла кадры. Reduce Motion — тот же кадр, но замороженный.
fileprivate struct PlinkLiveCover: View {
    let spec: PlinkCoverSpec
    let motion: PlinkCoverMotion
    var preview: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            frame(at: 1.4)
        } else {
            TimelineView(.animation(minimumInterval: preview ? 1.0 / 12.0 : 1.0 / 20.0)) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    @ViewBuilder private func frame(at t: Double) -> some View {
        switch motion {
        case .shimmer:
            // Единственный пресет, который двигает само небо, а не рисует
            // поверх: дрейф оттенка ±38° за ~9 с плюс ход света.
            PlinkCoverGradient(spec: spec, glowDrift: CGFloat(sin(t * 0.45)) * 0.28)
                .hueRotation(.degrees(sin(t * 0.7) * 38))
        case .reel:
            PlinkCoverGradient(spec: spec, glowDrift: CGFloat(sin(t * 0.22)) * 0.30,
                               motion: motion, t: t)
        default:
            PlinkCoverGradient(spec: spec, motion: motion, t: t)
        }
    }
}

/// Рисунок живого слоя: луч проектора, бегущая плёнка, гирлянда ламп,
/// пыль в луче. Один Canvas — один проход по GPU на всю обложку.
fileprivate struct PlinkCoverMotionCanvas: View {
    let motion: PlinkCoverMotion
    let tint: Color
    let t: Double

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            switch motion {
            case .projector: Self.drawProjector(&ctx, size, tint, t)
            case .reel: Self.drawReel(&ctx, size, tint, t)
            case .bulbs: Self.drawBulbs(&ctx, size, tint, t)
            case .drift: Self.drawDrift(&ctx, size, tint, t)
            case .none, .shimmer: break
            }
        }
    }

    /// Дробная часть — общая основа детерминированного «шума» пылинок.
    private static func frac(_ v: Double) -> Double { v - floor(v) }

    /// Конус света из лампы в левом верхнем углу: качается и дышит.
    private static func drawProjector(_ ctx: inout GraphicsContext, _ size: CGSize,
                                      _ tint: Color, _ t: Double) {
        let w = size.width, h = size.height
        let apex = CGPoint(x: w * 0.04, y: h * 0.28)
        let sway = CGFloat(sin(t * 0.26)) * h * 0.11
        var cone = Path()
        cone.move(to: apex)
        cone.addLine(to: CGPoint(x: w * 1.06, y: h * 0.04 + sway))
        cone.addLine(to: CGPoint(x: w * 1.06, y: h * 0.98 + sway))
        cone.closeSubpath()
        let breathe = 0.26 + 0.12 * (0.5 + 0.5 * sin(t * 0.63))
        // Гало вокруг луча — чтобы верхняя кромка не была бритвой.
        var halo = Path()
        halo.move(to: apex)
        halo.addLine(to: CGPoint(x: w * 1.06, y: -h * 0.22 + sway))
        halo.addLine(to: CGPoint(x: w * 1.06, y: h * 1.24 + sway))
        halo.closeSubpath()
        ctx.fill(halo, with: .linearGradient(
            Gradient(colors: [tint.opacity(breathe * 0.45), tint.opacity(breathe * 0.10), .clear]),
            startPoint: apex, endPoint: CGPoint(x: w * 0.85, y: h * 0.5)))
        ctx.fill(cone, with: .linearGradient(
            Gradient(colors: [tint.opacity(breathe), tint.opacity(breathe * 0.28), .clear]),
            startPoint: apex, endPoint: CGPoint(x: w * 0.95, y: h * 0.5)))
        // Сама лампа — маленькая, но самая яркая точка кадра.
        let r = h * 0.10
        ctx.fill(
            Path(ellipseIn: CGRect(x: apex.x - r, y: apex.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(0.90), tint.opacity(0.18), .clear]),
                center: apex, startRadius: 0, endRadius: r))
    }

    /// 35 мм на просвет: подсвеченная лента, две дорожки перфорации и
    /// кадровые границы между ними — всё едет влево одним куском.
    /// 35 мм на просвет: окно кадра светится, перфорация бежит по двум
    /// рельсам, границы кадров идут поперёк окна. Верхние 28% высоты в шапке
    /// закрыты статус-баром — лента живёт ниже.
    private static func drawReel(_ ctx: inout GraphicsContext, _ size: CGSize,
                                 _ tint: Color, _ t: Double) {
        let w = size.width, h = size.height
        let top = h * 0.26, bottom = h * 0.68
        ctx.fill(Path(CGRect(x: 0, y: top, width: w, height: bottom - top)),
                 with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.04), tint.opacity(0.14), tint.opacity(0.04)]),
                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        // Края ленты: без них светящаяся полоса растворяется в небе.
        for edge in [top, bottom] {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: edge))
            line.addLine(to: CGPoint(x: w, y: edge))
            ctx.stroke(line, with: .color(tint.opacity(0.20)), lineWidth: max(0.5, h * 0.005))
        }
        // Шаг перфорации мелкий: четыре отверстия на кадр, как на плёнке.
        let pitch = h * 0.115
        let shift = CGFloat(frac(t * 0.30)) * pitch
        let holeW = pitch * 0.46, holeH = h * 0.042
        let railY: [CGFloat] = [h * 0.298, h * 0.600]
        let count = Int(w / pitch) + 3
        for i in 0..<count {
            let x = CGFloat(i) * pitch - shift - pitch
            for y in railY {
                let hole = Path(roundedRect: CGRect(x: x, y: y, width: holeW, height: holeH),
                                cornerRadius: holeH * 0.34)
                ctx.fill(hole, with: .color(tint.opacity(0.62)))
            }
            guard i % 4 == 0 else { continue }
            var line = Path()
            line.move(to: CGPoint(x: x + holeW * 0.5, y: h * 0.348))
            line.addLine(to: CGPoint(x: x + holeW * 0.5, y: h * 0.596))
            ctx.stroke(line, with: .color(tint.opacity(0.28)), lineWidth: max(0.6, h * 0.006))
        }
    }

    /// Гирлянда над входом: провис по дуге, огонь бежит слева направо.
    /// Провис начинается ниже статус-бара — в шапке верх обложки не виден.
    private static func drawBulbs(_ ctx: inout GraphicsContext, _ size: CGSize,
                                  _ tint: Color, _ t: Double) {
        let w = size.width, h = size.height
        let count = 13
        var wire = Path()
        for i in 0...count {
            let u = Double(i) / Double(count)
            let p = CGPoint(x: w * CGFloat(u), y: h * (0.26 + 0.14 * sin(.pi * u)))
            if i == 0 { wire.move(to: p) } else { wire.addLine(to: p) }
        }
        ctx.stroke(wire, with: .color(tint.opacity(0.16)), lineWidth: max(0.5, h * 0.006))
        for i in 0...count {
            let u = Double(i) / Double(count)
            let c = CGPoint(x: w * CGFloat(u), y: h * (0.26 + 0.14 * sin(.pi * u)))
            // Бегущий огонь: узкий пик волны, а не общее мигание.
            let wave = max(0, sin(t * 2.0 - Double(i) * 0.52))
            let lit = 0.28 + 0.72 * pow(wave, 5)
            let r = h * 0.030
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                with: .color(tint.opacity(0.30 + 0.60 * lit)))
            let halo = r * 3.4
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo,
                                       width: halo * 2, height: halo * 2)),
                with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.34 * lit), .clear]),
                    center: c, startRadius: 0, endRadius: halo))
        }
    }

    /// Пылинки в луче: параллакс — дальние мельче, темнее и медленнее.
    private static func drawDrift(_ ctx: inout GraphicsContext, _ size: CGSize,
                                  _ tint: Color, _ t: Double) {
        let w = size.width, h = size.height
        for i in 0..<34 {
            let n = Double(i)
            let rx = frac(sin(n * 12.9898) * 43758.5453)
            let ry = frac(sin(n * 78.2330) * 12345.6789)
            let rd = frac(sin(n * 39.4250) * 8765.4321)
            let depth = 0.30 + rd * 0.70
            let speed = 0.010 + rd * 0.028
            let x = CGFloat(frac(rx + t * speed) * 1.16 - 0.08) * w
            let y = CGFloat(frac(ry - t * speed * 0.42)) * h * 0.92
            let r = CGFloat(h * (0.004 + 0.011 * depth))
            let pulse = 0.60 + 0.40 * sin(t * 0.9 + n * 1.7)
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .color(tint.opacity(0.12 + 0.52 * depth * pulse)))
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

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    V4Heading(eyebrow: "Оформление профиля", title: "Обложка")
                    Spacer(minLength: 0)
                    V4SheetCloseButton { dismiss() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        customShelf
                        freeShelf
                        plusShelf

                        if let loadError {
                            Text(loadError)
                                .font(.caption)
                                .foregroundStyle(V4.danger)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)

                SettingsPrimaryButton(title: "Применить") {
                    if apply() { dismiss() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 18)
                // Полки уезжают под кнопку, а не обрываются об неё.
                .background(
                    LinearGradient(colors: [V4.canvas.opacity(0), V4.canvas], startPoint: .top, endPoint: .bottom)
                        .padding(.top, -22)
                        .allowsHitTesting(false)
                )
            }
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

    private var hasPlus: Bool { store?.isPremium == true }

    /// Пресет, который стоит у человека сейчас — нужен, чтобы снятая с
    /// витрины обложка («Неон», «Сияние») не исчезла у того, кто её носит.
    private var currentPreset: V4CoverStyle? {
        if case .preset(let style) = selected { return style }
        return store?.coverStyle
    }

    /// Своя обложка — первой и во всю ширину: она одна такая, и фото
    /// стоит показывать в тех же пропорциях, в каких оно ляжет в шапку.
    private var customShelf: some View {
        VStack(alignment: .leading, spacing: 11) {
            shelfHeader(title: "Своя", note: "Фото из галереи", isPlusShelf: false)
            customCell
        }
    }

    private var freeShelf: some View {
        VStack(alignment: .leading, spacing: 11) {
            shelfHeader(title: "Бесплатные", note: "Доступны всем", isPlusShelf: false)
            coverGrid(V4CoverStyle.freeShelf(current: currentPreset))
        }
    }

    private var plusShelf: some View {
        VStack(alignment: .leading, spacing: 11) {
            shelfHeader(title: "Плинк+",
                        note: hasPlus ? "Открыты" : "Двигаются, а не стоят",
                        isPlusShelf: true)
            coverGrid(V4CoverStyle.plusCatalog)
        }
    }

    /// Заголовок полки. У платной вместо слова — сам знак Плинк+: он же
    /// снимает нужду вешать бейдж на каждую из пяти плиток.
    private func shelfHeader(title: String, note: String, isPlusShelf: Bool) -> some View {
        HStack(spacing: 8) {
            if isPlusShelf {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .black))
                    Text("PLINK+")
                        .font(.system(size: 9.5, weight: .black))
                        .tracking(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "#A855F7"), in: Capsule())
                .accessibilityLabel("Плинк+")
            } else {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(V4.ink)
            }
            Text(note)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(V4.muted)
            Spacer(minLength: 0)
        }
    }

    private func coverGrid(_ styles: [V4CoverStyle]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 14
        ) {
            ForEach(styles) { style in
                coverCell(style)
            }
        }
    }

    private func coverCell(_ style: V4CoverStyle) -> some View {
        let isSelected = selected == .preset(style)
        let locked = style.isLive && !hasPlus
        return Button {
            HapticManager.selection()
            if locked {
                showPlusPaywall = true
            } else {
                withAnimation(.easeInOut(duration: 0.15)) { selected = .preset(style) }
            }
        } label: {
            VStack(spacing: 7) {
                style.artwork(preview: true)
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .modifier(CoverCellChrome(theme: theme, isSelected: isSelected))
                    .overlay(alignment: .topLeading) {
                        // Замок — только там, где тап и правда уведёт в
                        // пейволл. У подписчика полка чистая.
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(.black.opacity(0.38), in: Circle())
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
            Group {
                if let shown {
                    Color.clear
                        .overlay(Image(uiImage: shown).resizable().scaledToFill())
                        .clipped()
                } else {
                    ZStack {
                        V4.surface
                        HStack(spacing: 9) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Выбрать фото")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(V4.ink)
                                Text("Кадр обрежется по ширине шапки")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(V4.muted)
                            }
                        }
                    }
                }
            }
            .frame(height: 96)
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
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 10, weight: .bold))
                            Text("Другое фото")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(V4.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .accessibilityLabel("Выбрать другое фото")
                }
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
    /// Button tint — the face accent on profile screens.
    let accent: Color
    var accentInk: Color = .white
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
                    tint: accent,
                    textColor: accentInk,
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
