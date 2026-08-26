// Вспомогательные секции Главной.
// HomeFallbackPlaceholder, FriendsWatchingSection, NewThisWeekSection, TrendingPreviewSheet.

import SwiftUI

/// Чипы Главной и YouTube-хвост их полок.
///
/// Почему так (22.08.2026). Люди приходят в Plink смотреть фильмы и сериалы,
/// а /api/media/trending отдаёт общий YouTube-чарт региона — музыкальные
/// клипы и влоги. Роут менять нельзя без деплоя бэкенда, поэтому каталог
/// собирается клиентом. Первым полку наполняет каталог кинотеатра
/// (V4CinemaCatalog — «кинотеатры в приоритете»); запросы отсюда — ХВОСТ:
/// V4SearchStore.loadShelf добирает ими полку через /api/media/search,
/// когда кинотеатр дал мало или не ответил.
///
/// Прошлая версия (HomeTitleFilter) фильтровала общий чарт ПОДСТРОКОЙ в
/// названии: чип «Фантастика» искал слово «фантастика» в заголовках трендов
/// и почти всегда находил ноль. Чип — это полка каталога, а не grep.
enum HomeCinemaCatalog {
    static let allChip = "Для вас"

    /// «Новинки» (22.08.2026): премьеры этого года + тренды Netflix.
    /// Полка собирается из трёх источников сразу — тренд-карточки
    /// V4TrendsCatalog, свежие годы каталога Иви и YouTube-трейлеры года.
    static let freshChip = "Новинки"

    /// Служебная полка «Топ недели» — не чип, в ряду фильтров не показывается.
    /// У неё собственные запросы: раньше секция резала те же первые карточки,
    /// что герой и «Популярно», и Главная трижды показывала одно и то же.
    static let topWeekShelf = "™topweek"

    /// Порядок чипов = порядок на экране: сперва свежесть, затем форматы
    /// (фильмы, сериалы, мультфильмы), затем жанры.
    static let chips = [
        "Для вас", "Новинки", "Фильмы", "Сериалы", "Мультфильмы",
        "Фантастика", "Комедии", "Ужасы", "Аниме",
    ]

    /// Запросы полки. Несколько запросов — несколько источников: результаты
    /// перемешиваются интерливом, а не клеятся списками встык.
    ///
    /// Формулировки подобраны под то, что реально лежит на YouTube легально:
    /// «фильм полностью» находит официальные каналы студий (Мосфильм,
    /// Star Media, Центральное телевидение…), «трейлер <год>» — свежие
    /// трейлеры прокатчиков. Длительность в ответе поиска не приходит
    /// (duration: null), так что отфильтровать шорты по времени нельзя —
    /// отбор делает сама формулировка запроса.
    static func queries(for chip: String) -> [String] {
        switch chip {
        case Self.freshChip:
            // Театральные хиты года («Человек-паук: Новый путь» и т.п.) в
            // открытых каталогах кинотеатров не живут — их свежие трейлеры
            // поднимает сам YouTube-запрос с годом. Год считается, не вписан.
            let year = Calendar.current.component(.year, from: Date())
            return [
                "новинки кино \(year) официальный трейлер на русском",
                "премьера \(year) фильм полностью на русском",
            ]
        case "Фильмы":      return ["художественный фильм полностью в хорошем качестве"]
        case "Сериалы":     return ["сериал все серии подряд на русском"]
        case "Мультфильмы": return ["мультфильм полностью на русском"]
        case "Фантастика":  return ["фантастика фильм полностью на русском"]
        case "Комедии":     return ["комедия фильм полностью на русском"]
        case "Ужасы":       return ["фильм ужасов полностью на русском"]
        case "Аниме":       return ["аниме сериал на русском все серии"]
        case Self.topWeekShelf:
            // «Топ недели» — популярное к просмотру целиком, а не витрина
            // трейлеров, как «Для вас». Слова «топ» в запросах нет нарочно:
            // по нему YouTube отдаёт нарезки-списки «ТОП 10…» вместо кино.
            let year = Calendar.current.component(.year, from: Date())
            return [
                "самый популярный фильм \(year) полностью на русском",
                "популярный сериал все серии подряд на русском",
            ]
        default:
            // «Для вас» — витрина: свежие трейлеры вперемешку с полными
            // фильмами. Год считается, а не вписан: вписанный устаревает.
            let year = Calendar.current.component(.year, from: Date())
            return [
                "новинки кино \(year) трейлер на русском",
                "лучшие фильмы полностью в хорошем качестве",
            ]
        }
    }
}

// MARK: - Кино-сцена и пустое состояние (общий язык V4)

/// Конус света проектора: узкая «линза» сверху расходится к основанию.
private struct V4ProjectorBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let apexHalf: CGFloat = rect.width * 0.03
        p.move(to: CGPoint(x: rect.midX - apexHalf, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + apexHalf, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Сигнатура пустых состояний: луч кинопроектора освещает веер из трёх
/// мини-постеров. «Иконка в кружке» читалась как заглушка девелопера —
/// сцена из мира продукта (вечер кино) собрана из тех же токенов V4:
/// акцент темы, стеклянные штрихи, глубокие тени.
struct V4ProjectorScene: View {
    let icon: String
    var accent: Color = V4.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        ZStack(alignment: .top) {
            // Пятно света на «полу» — луч упирается в веер и растекается.
            Ellipse()
                .fill(accent.opacity(0.30))
                .frame(width: 170, height: 38)
                .blur(radius: 13)
                .offset(y: 122)
                .opacity(lit ? 1 : 0)

            // Широкий мягкий конус — атмосфера.
            V4ProjectorBeamShape()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.80), accent.opacity(0.32), accent.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 176, height: 152)
                .blur(radius: 9)
                .opacity(lit ? 1 : 0)

            // Ядро луча — яркий белёсый свет у самой линзы.
            V4ProjectorBeamShape()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.75), accent.opacity(0.30), accent.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 78, height: 144)
                .blur(radius: 7)
                .opacity(lit ? 1 : 0)

            // Линза проектора — точка, из которой бьёт свет.
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .shadow(color: .white.opacity(0.9), radius: 4)
                .shadow(color: accent.opacity(0.95), radius: 9)
                .shadow(color: accent.opacity(0.55), radius: 20)
                .offset(y: -2)

            // Пылинки в луче — медленный дрейф; статичны при reduce motion.
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.5))
                    .frame(width: i == 1 ? 3 : 2, height: i == 1 ? 3 : 2)
                    .offset(x: [-22, 14, 30][i], y: [46, 30, 66][i])
                    .opacity(lit ? 0.7 : 0)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: [2.8, 3.6, 3.1][i])
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.5),
                        value: lit
                    )
            }

            posterFan
                .padding(.top, 56)
        }
        .frame(width: 200, height: 152)
        .onAppear {
            guard !lit else { return }
            if reduceMotion { lit = true } else {
                withAnimation(.easeOut(duration: 0.7)) { lit = true }
            }
        }
        .accessibilityHidden(true)
    }

    /// Веер из трёх постеров: боковые — «афиши» с плашками названий,
    /// центральный несёт знак контекста (иконку экрана).
    private var posterFan: some View {
        ZStack {
            posterCard(rotation: -11, offset: CGSize(width: -34, height: 10), dim: true)
            posterCard(rotation: 11, offset: CGSize(width: 34, height: 10), dim: true)
            posterCard(rotation: 0, offset: .zero, dim: false)
        }
    }

    private func posterCard(rotation: Double, offset: CGSize, dim: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 0) {
            if dim {
                Spacer()
                // Плашки-строки афиши — намёк на название и мету.
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white.opacity(0.30)).frame(width: 24, height: 3)
                    Capsule().fill(.white.opacity(0.16)).frame(width: 15, height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 46, height: 64)
        .background(
            LinearGradient(
                colors: dim
                    ? [Color.white.opacity(0.10), accent.opacity(0.10)]
                    : [accent.opacity(0.85), accent.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            ),
            in: shape
        )
        .overlay(shape.strokeBorder(.white.opacity(dim ? 0.14 : 0.32), lineWidth: 1))
        .shadow(color: .black.opacity(dim ? 0.30 : 0.45), radius: dim ? 8 : 14, y: 7)
        .rotationEffect(.degrees(rotation))
        .offset(offset)
        .opacity(dim ? 0.82 : 1)
    }
}

/// Подпись пустых «Чатов» — не значок в кружке, а сами пузыри Плинка:
/// та же форма V5BubbleShape и те же заливки, что в переписке. Экран
/// показывает, чем он станет, вместо метафоры поверх пустоты. Во входящем
/// бьются точки набора — «сейчас тебе напишут», приглашение, а не констатация.
///
/// 26.08.2026: сменил V4OrbitScene (facepile из двух силуэтов и медальона).
/// Тот говорил про людей — то есть про соседнюю вкладку, — а его акцентный
/// «+» изображал кнопку, которой не был: вторая цель в композиции с одной
/// настоящей кнопкой внизу.
struct V4BubblesScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false
    @State private var beat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Отправленная реплика — широкая, у правого края.
            shell(width: 118, height: 32, outgoing: true) { Color.clear }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(lit ? 1 : 0)
                .offset(y: lit ? 0 : 7)

            // Ответ на подходе — узкий пузырь набора, как в живом чате.
            shell(width: 64, height: 34, outgoing: false) { dots }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(lit ? 1 : 0)
                .offset(y: lit ? 0 : 11)
        }
        .frame(width: 196)
        .onAppear {
            guard !lit else { return }
            if reduceMotion {
                lit = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { lit = true }
                withAnimation(.easeOut(duration: 0.5).delay(0.12)) { beat = true }
            }
        }
        .accessibilityHidden(true)
    }

    /// Корпус пузыря: заливки и обводка один в один из DMChatView, чтобы
    /// пустой экран и первое сообщение выглядели одним материалом.
    private func shell<C: View>(width: CGFloat, height: CGFloat, outgoing: Bool,
                                @ViewBuilder content: () -> C) -> some View {
        let shape = V5BubbleShape(isOutgoing: outgoing)
        return content()
            .frame(width: width, height: height)
            .background {
                ZStack {
                    V4.raised
                    if outgoing {
                        Cinema2026.outgoingBubble
                    } else {
                        LinearGradient(
                            colors: [Color(hex: "#2B3138"), Color(hex: "#232930")],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(outgoing ? 0.20 : 0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 9, y: 5)
    }

    /// Точки набора. Полоса под хвост входящего съедает слева — сдвигаем,
    /// иначе три точки стоят не по центру корпуса.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(V4.ink.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(beat ? 1 : 0.6)
                    .opacity(beat ? 1 : 0.45)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.62)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                        value: beat
                    )
            }
        }
        .offset(x: V5BubbleShape.tailWidth / 2)
    }
}

/// Стеклянная «монета» с мягким свечением — знак хиро пейволла и мелких
/// плейсхолдеров, где сцена с лучом не помещается. Пустые состояния экранов
/// используют V4ProjectorScene.
struct V4GlassMedallion: View {
    let icon: String
    var accent: Color = V4.accent
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.32))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: size * 0.4)
            Circle()
                .stroke(accent.opacity(0.22), lineWidth: 1)
                .frame(width: size * 1.32, height: size * 1.32)
            Circle()
                .fill(accent.opacity(0.5))
                .frame(width: size * 0.066, height: size * 0.066)
                .offset(x: size * 0.6, y: -size * 0.52)
            Circle()
                .fill(accent.opacity(0.32))
                .frame(width: size * 0.04, height: size * 0.04)
                .offset(x: -size * 0.68, y: size * 0.36)
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(colors: [accent, accent.opacity(0.62)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: size, height: size)
                .plinkGlass(.control, in: Circle())
        }
        .frame(height: size * 1.32)
        .accessibilityHidden(true)
    }
}

/// Высота видимой полосы скролла — пустые состояния центруются по ней.
/// Выдуманный `minHeight` прижимал блок к шапке, и под ним оставалось
/// полэкрана пустоты: ровно то, из-за чего экран читался незакрытым.
struct V4ViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Пустое состояние V4: сцена с лучом проектора → короткий заголовок →
/// пояснение в одну мысль → одно явное действие (+ необязательный второй
/// канал через `extra`). Формула одна на всё приложение — Главная, Друзья,
/// история, пейволл.
///
/// `style: .plain` — для ошибок: луч проектора зарезервирован за «в мире
/// пока пусто», сбою он не полагается — там компактный кружок-медальон.
enum V4EmptyStyle {
    /// Сцена с лучом проектора и веером постеров — пустые кино-миры.
    case scene
    /// Пузыри переписки — пустые «Чаты»: экран показывает, чем станет,
    /// а не рисует значок в кружке.
    case bubbles
    /// Кружок-медальон без сцены — ошибки и служебные состояния.
    case plain
}

struct V4EmptyState<Extra: View>: View {
    struct Action {
        let title: String
        let icon: String
        var a11yID: String? = nil
        let run: () -> Void
    }

    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = V4.accent
    var accentInk: Color = .white
    var style: V4EmptyStyle = .scene
    var primary: Action? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(spacing: 0) {
            switch style {
            case .scene:
                V4ProjectorScene(icon: icon, accent: accent)
                    .padding(.bottom, 14)
            case .bubbles:
                V4BubblesScene()
                    .padding(.bottom, 18)
            case .plain:
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(accent.opacity(0.28), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 21, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(V4.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(V4.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3.5)
                .frame(maxWidth: 300)
                .padding(.top, 7)
            if let primary {
                Button {
                    HapticManager.impact(.medium)
                    primary.run()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primary.icon)
                            .font(.system(size: 14, weight: .bold))
                        Text(primary.title)
                    }
                }
                // Канон CTA приложения: главная кнопка — белая с чёрным
                // текстом; акцент темы остаётся сцене, а не кнопке.
                // Ширина — единая полоса до 300 pt, как у кнопок онбординга
                // ИИ: по-контентная ширина делала вторичную кнопку в слоте
                // extra шире главной, и иерархия читалась перевёрнутой.
                .buttonStyle(PlinkProminentButtonStyle(
                    tint: .white, textColor: .black,
                    height: 48, cornerRadius: 16, fillsWidth: true
                ))
                .frame(maxWidth: 300)
                .accessibilityIdentifier(primary.a11yID ?? "empty.primary")
                .padding(.top, 18)
            }
            extra()
        }
        .frame(maxWidth: .infinity)
    }
}

extension V4EmptyState where Extra == EmptyView {
    init(icon: String, title: String, subtitle: String,
         accent: Color = V4.accent, accentInk: Color = .white,
         style: V4EmptyStyle = .scene, primary: Action? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle,
                  accent: accent, accentInk: accentInk, style: style,
                  primary: primary) { EmptyView() }
    }
}

// MARK: - Fallback, когда trending пуст
struct HomeFallbackPlaceholder: View {
    let theme: V4Theme
    var openRoom: () -> Void

    var body: some View {
        V4EmptyState(
            icon: "film.stack",
            title: "Пока тихо",
            subtitle: "Подборка обновляется. Найди видео вручную — и собери первый вечер кино.",
            accent: theme.accentColor,
            accentInk: theme.buttonTextColor,
            // Вход в комнату, когда trending пуст (нет сети / пустая подборка).
            primary: .init(title: "Найти видео", icon: "magnifyingglass",
                           a11yID: "home.emptyFindVideo", run: openRoom)
        )
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .plinkGlass(.control, cornerRadius: 24)
        .padding(.horizontal, 19)
    }
}

// MARK: - Друзья онлайн
struct FriendsWatchingSection: View {
    let theme: V4Theme
    var openRoom: () -> Void

    private var onlineFriends: [Friend] {
        FriendManager.shared.friends.filter { $0.isOnline }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Сейчас онлайн")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(V4.ink)
                Spacer()
                if !onlineFriends.isEmpty {
                    Text("\(onlineFriends.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.accentInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(V4.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 19)

            if onlineFriends.isEmpty {
                Button {
                    HapticManager.impact(.light)
                    openRoom()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .foregroundStyle(V4.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Никто из друзей сейчас не онлайн")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(V4.ink)
                            Text("Загляни в комнаты — там всегда что-то идёт")
                                .font(.system(size: 11))
                                .foregroundStyle(V4.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(V4.muted)
                    }
                    .padding(14)
                    .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(V4.line))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 19)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(onlineFriends.prefix(12), id: \.id) { friend in
                            Button {
                                HapticManager.impact(.light)
                                openRoom()
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(V4.raised)
                                            .frame(width: 52, height: 52)
                                            .overlay(
                                                Text(String((friend.displayName ?? friend.username).prefix(1)).uppercased())
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(V4.accent)
                                            )
                                            .overlay(Circle().stroke(V4.line, lineWidth: 1))
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 12, height: 12)
                                            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 2))
                                    }
                                    Text(friend.displayName ?? friend.username)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(V4.muted)
                                        .lineLimit(1)
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 19)
                }
            }
        }
    }
}

// MARK: - Новое в Plink
struct NewThisWeekSection: View {
    let theme: V4Theme

    private let items: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "Умные подсказки ИИ", "Ассистент сам предлагает, что посмотреть компании"),
        ("qrcode", "Вход в комнату по коду", "Шесть символов — и ты внутри, без ссылок и поиска"),
        ("clock.arrow.circlepath", "История просмотров", "Всё, что вы смотрели вместе — теперь в профиле"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Новое в Plink")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(V4.ink)
                Spacer()
            }
            .padding(.horizontal, 19)

            VStack(spacing: 9) {
                ForEach(items, id: \.title) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(V4.accent)
                            .frame(width: 38, height: 38)
                            .background(V4.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(V4.ink)
                            Text(row.subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(V4.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(V4.cardBG.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(V4.line))
                }
            }
            .padding(.horizontal, 19)
        }
    }
}

// MARK: - Превью перед созданием комнаты
//
// 22.08.2026, «кинотеатры в приоритете»: бейдж «YouTube» перестал быть
// вшитым — карточка каталога показывает свой кинотеатр фирменным цветом,
// год, тип и рейтинг, честную подпись про вход в аккаунт и ряд
// «Где ещё смотреть» — мостик в Кинопоиск/Okko/Wink/PREMIER одним тапом.
struct TrendingPreviewSheet: View {
    let item: V4SearchResult
    let theme: V4Theme
    var onWatch: (V4WatchTarget) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Сервис карточки: бейдж и цвет. У роликов — YouTube.
    private var service: VideoService {
        if case .cinema(let s) = item.origin { return s }
        return .youtube
    }

    /// Мета без имени сервиса — оно уже на бейдже.
    private var metaLine: String {
        switch item.origin {
        case .youtube:
            var parts = [item.subtitle]
            if let duration = item.duration { parts.append(duration) }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        case .cinema:
            var parts: [String] = []
            if let year = item.year { parts.append(String(year)) }
            if let kind = item.kindLabel { parts.append(kind) }
            if let rating = item.ratingText { parts.append("★ \(rating)") }
            return parts.joined(separator: " · ")
        }
    }

    /// Кинотеатры для мостика — без сервиса самой карточки.
    private var bridgeServices: [VideoService] {
        guard case .cinema = item.origin else { return [] }
        return V4CinemaCatalog.bridgeServices.filter { $0 != service }
    }

    var body: some View {
        ZStack {
            V4.canvas.ignoresSafeArea()
            // Тема — только фон: тихий радиал акцента, как на остальных
            // экранах V4. Кнопки ниже от палитры не зависят.
            RadialGradient(
                colors: [theme.accentColor.opacity(0.10), .clear],
                center: .top, startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        // Кадр — оверлеем над Color.clear: scaledToFill-имидж
                        // сам по себе отчитывается layout-шириной 16:9 от
                        // высоты (шире шита), распирал VStack и сдвигал весь
                        // контент влево за края. Тот же приём, что в V4Hero.
                        Color.clear
                            .frame(height: 280)
                            .overlay {
                                if let url = item.artworkURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(V4.cardBG)
                                    }
                                } else {
                                    Rectangle().fill(V4.cardBG)
                                }
                            }
                            .clipped()
                            // Кадр растворяется в холсте, а не обрывается
                            // жёсткой кромкой — приём афиш Apple TV: контент
                            // и текст под ним живут на одном полотне.
                            .overlay(alignment: .bottom) {
                                LinearGradient(
                                    colors: [.clear, V4.canvas.opacity(0.62), V4.canvas],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .frame(height: 110)
                            }

                        V4SheetCloseButton { dismiss() }
                            .padding(14)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(service.title)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(service.accentColor, in: Capsule())
                            if item.isFreeOnService {
                                // Тот же изумруд, что на бейджах карточек
                                // витрины: серая капсула читалась как
                                // неактивный чип, а не как «смотри даром».
                                Text("Бесплатно")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(V4.free, in: Capsule())
                            }
                        }

                        Text(item.title)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(V4.ink)

                        if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(.system(size: 13))
                                .foregroundStyle(V4.muted)
                        }

                        Button {
                            HapticManager.impact(.medium)
                            onWatch(.native)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .heavy))
                                Text("Смотреть вместе")
                            }
                        }
                        // Белая, как Play у Apple TV и Netflix: главная CTA
                        // статична и не зависит от темы — тема остаётся фону.
                        // Акцентная заливка меняла характер кнопки с каждой
                        // палитрой и красила весь шит «в синий».
                        .buttonStyle(
                            PlinkProminentButtonStyle(
                                tint: .white,
                                textColor: .black,
                                height: 52,
                                cornerRadius: 16
                            )
                        )
                        // Единственная кнопка, которая реально создаёт
                        // комнату из Главной. Без идентификатора UI-смоук
                        // воронки искал «Создать комнату» на самой Главной,
                        // не находил её (такой кнопки в продукте нет) и падал.
                        .accessibilityIdentifier("preview.watchTogether")
                        .padding(.top, 10)
                        // Третьей кнопки закрытия здесь нет намеренно: шит
                        // закрывают крестик и свайп вниз, «Может позже» была
                        // ещё одним способом сделать то же самое.

                        if case .cinema = item.origin {
                            Text("Комната откроет страницу «\(service.title)». Вы входите в свой аккаунт — Plink не предоставляет контент и не обходит защиту.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(V4.muted)
                                .lineSpacing(2.5)

                            // Запасной путь без комнаты: открыть тайтл в самом
                            // кинотеатре (universal link поднимет его
                            // приложение, если стоит). Совместный просмотр —
                            // выше, это осознанно второстепенная ссылка.
                            Button {
                                HapticManager.impact(.light)
                                AnalyticsService.shared.track(
                                    "home_preview_open_external",
                                    parameters: ["service": service.rawValue]
                                )
                                if let url = URL(string: item.watchURL) {
                                    openURL(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Открыть на «\(service.title)»")
                                        .font(.system(size: 12.5, weight: .bold))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                // Стекло вместо голого синего текста: висячая
                                // акцентная строка читалась как веб-ссылка
                                // 2010-х и зависела от темы. Тот же контрол,
                                // что капсулы «Где ещё смотреть» ниже.
                                .foregroundStyle(V4.ink)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 38)
                                .plinkGlass(.control, interactive: true)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("preview.openExternal")
                        }

                        if !bridgeServices.isEmpty {
                            Text("ГДЕ ЕЩЁ СМОТРЕТЬ")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.1)
                                .foregroundStyle(V4.muted)
                                .padding(.top, 14)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(bridgeServices) { bridge in
                                        bridgeChip(bridge)
                                    }
                                }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.track(
                "home_preview_opened",
                parameters: ["service": service.rawValue]
            )
        }
    }

    /// Капсула кинотеатра: открывает тайтл поиском на его официальной
    /// странице — прямых ссылок на карточки без их API не существует.
    @ViewBuilder
    private func bridgeChip(_ bridge: VideoService) -> some View {
        if let url = V4CinemaCatalog.searchURL(for: bridge, title: item.title) {
            Button {
                HapticManager.impact(.light)
                onWatch(.cinema(bridge, url))
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(bridge.accentColor)
                        .frame(width: 7, height: 7)
                    Text(bridge.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(V4.ink)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .plinkGlass(.control, interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Смотреть «\(item.title)» на \(bridge.title)")
        }
    }
}
