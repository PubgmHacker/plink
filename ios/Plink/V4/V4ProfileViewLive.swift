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
    /// Счётчик у строки «История просмотров» обновляется вживую.
    @ObservedObject private var historyManager = WatchHistoryManager.shared

    /// Счётчики шапки — тот же /users/me/profile, что и экран статистики.
    @State private var social: UserSocialProfile?

    private var isAdmin: Bool { store?.isAdmin == true }
    private var avatarURL: URL? { currentAvatarURL ?? store?.avatarURL }
    /// Обложка ложится под статус-бар, поэтому высота считается от
    /// физического верха экрана: ~62 pt статус-зоны + ~150 pt тела — как в ВК.
    private let coverHeight: CGFloat = 212
    /// Насколько аватар нахлёстывается на нижний край обложки.
    private let avatarOverlap: CGFloat = 46

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                avatarActionRow
                identityBlock
                countersCard
                settingsLinkGroup
                    .padding(.top, 14)
                sectionsGroup
                    .padding(.top, 14)
            }
            .padding(.bottom, 110)
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
                default: break
                }
            }
            #endif
        }
        .task { await reloadSocial() }
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

    /// Обложка как в ВК: полное полотно от края до края под статус-баром.
    /// Фото выбирает пользователь — пресет V4CoverStyle или своё из галереи
    /// (кнопка-кисть в углу), выбор синхронизируется через coverURL.
    private var cover: some View {
        ZStack {
            if let custom = store?.customCoverImage, store?.usesCustomCover == true {
                // Color.clear.overlay — scaledToFill заполняет полотно, не
                // распирая ширину ZStack под размер исходного фото.
                Color.clear
                    .overlay(Image(uiImage: custom).resizable().scaledToFill())
                    .clipped()
            } else {
                (store?.coverStyle ?? .hall).artwork()
            }
            // Скримы сверху и снизу — контраст статус-бара и кольца аватара.
            LinearGradient(colors: [.black.opacity(0.20), .clear, .black.opacity(0.30)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: coverHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
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
        HStack(alignment: .bottom, spacing: 8) {
            avatarBlock
            Spacer(minLength: 8)

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
            .buttonStyle(PlinkGlassButtonStyle(tint: theme.accentColor, height: 42, cornerRadius: 14))
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
        .padding(.horizontal, 18)
        // Нахлёст: ряд поднят на обложку, отрицательный нижний отступ
        // возвращает вертикальный ритм (offset место в layout не освобождает).
        .offset(y: -avatarOverlap)
        .padding(.bottom, -avatarOverlap)
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
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("screen.profile")
    }

    /// Аватар 96 pt с бейджем камеры — редактирование очевидно без слов.
    /// Кольцо цвета канваса отделяет круг от обложки (как в ВК), тень
    /// приподнимает его над ней.
    private var avatarBlock: some View {
        Button {
            HapticManager.selection()
            showAvatarPicker = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let local = store?.localAvatarImage {
                        Image(uiImage: local).resizable().scaledToFill()
                    } else if let avatarURL {
                        AsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 96, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                            }
                        }
                    } else {
                        V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 96, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(V4.canvas, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

                ZStack {
                    Circle().fill(theme.accentColor)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.buttonTextColor)
                }
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(V4.canvas, lineWidth: 2.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Сменить аватар")
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
            HStack(spacing: 0) {
                counter(social?.watchHoursText ?? "—", "время")
                counterDivider
                counter(social.map { "\($0.filmsWatched)" } ?? "—", "фильмов")
                counterDivider
                counter(social.map { "\($0.friendsCount)" } ?? "—", "друзей")
                counterDivider
                counter(social.map { "\($0.roomsCreated)" } ?? "—", "комнат")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Статистика профиля")
        .accessibilityHint("Открывает подробную статистику и достижения")
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
                tint: theme.accentColor,
                title: "Управление аккаунтом"
            ) { showAccountCenter = true }

            V4RowSeparator()

            V4ProfileRow(
                icon: "chart.bar.fill",
                tint: theme.accentColor,
                title: "Статистика и достижения"
            ) { showStats = true }

            V4RowSeparator()

            // История — контент, не идентичность: живёт своим экраном,
            // как статистика и настройки, а не лентой на лице профиля.
            V4ProfileRow(
                icon: "clock.arrow.circlepath",
                tint: theme.accentColor,
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
                tint: theme.accentColor,
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

// MARK: - Обложки профиля

/// Пресеты обложки профиля — живые фотографии (CC0, Wikimedia Commons /
/// Unsplash), а не процедурная графика: рисованные градиенты читались как
/// «сделано ИИ». Три сюжета вокруг кино-вечера: зал, неон города, ночь.
/// Выбор хранится токеном `plink://cover/<id>` в поле coverURL — синк
/// между устройствами задаром; своя картинка — data-URL там же.
enum V4CoverStyle: String, CaseIterable, Identifiable {
    case hall, neon, night

    var id: String { rawValue }

    static let urlPrefix = "plink://cover/"
    var remoteToken: String { Self.urlPrefix + rawValue }

    /// Разбор сохранённого id с маппингом токенов прежних процедурных
    /// пресетов на ближайшее фото — выбор со старых сборок не теряется.
    static func fromStored(_ id: String?) -> V4CoverStyle? {
        guard let id else { return nil }
        if let style = V4CoverStyle(rawValue: id) { return style }
        switch id {
        case "beam", "film": return .hall
        case "marquee": return .neon
        case "midnight", "aurora", "graphite": return .night
        default: return nil
        }
    }

    static func parse(_ raw: String?) -> V4CoverStyle? {
        guard let raw, raw.hasPrefix(urlPrefix) else { return nil }
        return fromStored(String(raw.dropFirst(urlPrefix.count)))
    }

    var title: String {
        switch self {
        case .hall: return "Кинозал"
        case .neon: return "Неон"
        case .night: return "Ночь"
        }
    }

    /// Imageset в Assets.xcassets: кропы 1500×750 (2:1) под полотно 212 pt.
    /// Источники: Movie theater seats / Neon light trails in Munich /
    /// Milky Way over Silverthorne — все с Wikimedia Commons, лицензия CC0.
    var assetName: String {
        switch self {
        case .hall: return "CoverHall"
        case .neon: return "CoverNeon"
        case .night: return "CoverNight"
        }
    }

    /// Фото обложки. GeometryReader + явный frame — одинаковый центральный
    /// кроп в полотне 212 pt и в миниатюре пикера, scaledToFill не распирает
    /// родителя.
    func artwork() -> some View {
        GeometryReader { geo in
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
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

    init(theme: V4Theme, store: V4ProfileStore?) {
        self.theme = theme
        self.store = store
        _selected = State(initialValue: store?.usesCustomCover == true
                          ? .custom
                          : .preset(store?.coverStyle ?? .hall))
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
                    apply()
                    dismiss()
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
    }

    private func apply() {
        switch selected {
        case .preset(let style):
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
        return Button {
            HapticManager.selection()
            withAnimation(.easeInOut(duration: 0.15)) { selected = .preset(style) }
        } label: {
            VStack(spacing: 7) {
                style.artwork()
                    .frame(height: 86)
                    .frame(maxWidth: .infinity)
                    .modifier(CoverCellChrome(theme: theme, isSelected: isSelected))
                Text(style.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? V4.ink : V4.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Обложка «\(style.title)»")
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


