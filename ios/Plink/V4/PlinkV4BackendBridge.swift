// Plink/V4/PlinkV4BackendBridge.swift — P0 Roadmap
// Connects V4 pixel-perfect views to real RoomService/FriendManager/AuthService/MediaService.
// NO placeholders, NO fake data.

import SwiftUI
import UIKit
import Observation

// MARK: - V4 Rooms Store (P0.2)

@MainActor
@Observable
final class V4RoomsStore {
    enum LoadState: Sendable { case idle, loading, loaded, empty, failed(String) }
    private(set) var state: LoadState = .idle
    private(set) var rooms: [Room] = []
    private(set) var myRooms: [Room] = []
    private let roomService: RoomService

    init(roomService: RoomService) { self.roomService = roomService }

    func load() async {
        state = .loading
        do {
            // Public live rooms only (backend + client filter empty/ended)
            async let publicActive = roomService.fetchActiveRooms()
            async let mineActive = roomService.fetchMyActiveRooms()
            let pub = try await publicActive
            let mine = (try? await mineActive) ?? []
            // Merge by id — prefer fresher mine rows for host's own rooms
            var byId: [String: Room] = [:]
            for r in pub where r.isActive && r.participantCount > 0 { byId[r.id] = r }
            for r in mine where r.isActive && r.participantCount > 0 { byId[r.id] = r }
            let active = Array(byId.values).sorted { $0.createdAt > $1.createdAt }
            rooms = active
            myRooms = mine
            state = active.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(Self.userFacingLoadError(error))
        }
    }

    private static func userFacingLoadError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет подключения к интернету"
            case .timedOut:
                return "Загрузка заняла слишком много времени"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к Plink"
            default:
                return "Не удалось загрузить комнаты"
            }
        }
        return "Не удалось загрузить комнаты"
    }

    func loadMyRooms() async {
        do {
            myRooms = try await roomService.fetchMyActiveRooms()
        } catch {}
    }

    func loadHistory() async -> [Room] {
        (try? await roomService.fetchMyRoomHistory()) ?? []
    }

    func join(code: String, password: String? = nil) async throws -> Room {
        try await roomService.joinRoom(code: code, password: password)
    }

    func joinByID(_ room: Room) async throws -> Room {
        try await roomService.fetchRoom(id: room.id)
    }

    // Герой — приоритет активным комнатам друзей
    var heroRoom: Room? {
        let friendNames = Set(FriendManager.shared.friends.map { $0.username.lowercased() })
        return rooms.first(where: { $0.isActive && friendNames.contains($0.hostName.lowercased()) }) ?? rooms.first
    }
    var railRooms: [Room] { Array(rooms.filter { $0.id != heroRoom?.id }.prefix(6)) }
}

// MARK: - V4 Search Store (P0.3)

@MainActor
@Observable
final class V4SearchStore {
    enum SearchState: Sendable { case idle, loading, loaded([V4SearchResult]), empty, failed(String) }
    private(set) var state: SearchState = .idle
    private(set) var trending: [V4SearchResult] = []
    /// Причина, по которой подборка на «Главной» не загрузилась.
    ///
    /// FIX (07.08.2026): здесь с самого начала стоял пустой `catch {}`, а
    /// HTTP-статус не проверялся вовсе. Когда на сервере не был задан
    /// YOUTUBE_API_KEY, /api/media/trending отвечал 500 с телом
    /// {"error":"YOUTUBE_API_KEY not configured"} — оно не разбиралось в
    /// YouTubeSearchResponse, декодер бросал, catch глотал, и `trending`
    /// молча оставался пустым. Экран показывал заглушку «пусто», хотя на
    /// самом деле запрос падал. Ни пользователь, ни консоль об этом не знали.
    private(set) var trendingError: String?
    private var searchTask: Task<Void, Never>?
    private let apiBase = PlinkConfig.baseURLString

    // MARK: Кинокаталог Главной (22.08.2026)
    //
    // Раньше витрину наполнял /api/media/trending — общий YouTube-чарт
    // региона: музыкальные клипы, влоги, что угодно, кроме кино. Люди же
    // приходят в Plink смотреть фильмы и сериалы вместе. Роут бэкенда менять
    // нельзя (деплой не в наших руках), поэтому каталог собирается клиентом
    // поверх публичного /api/media/search: полка = чип Главной, запросы полки
    // задаёт HomeCinemaCatalog. Полки кэшируются на время жизни стора —
    // повторное переключение чипа мгновенно.

    /// Загруженные полки: чип → результаты.
    private(set) var shelves: [String: [V4SearchResult]] = [:]
    /// Полки, по которым загрузка уже завершилась (успехом или ошибкой).
    /// Пока чипа здесь нет, пустая полка значит «ещё грузим» — скелетон,
    /// а не «ничего не нашлось».
    private(set) var attemptedShelves: Set<String> = []
    /// Полки, которые грузятся прямо сейчас: быстрое переключение чипов
    /// туда-обратно не должно запускать один и тот же набор запросов дважды.
    private var shelvesInFlight: Set<String> = []
    /// Когда полка в последний раз подтверждалась сетью (или свежим кэшем).
    /// От этой даты считает автообновление refreshIfStale.
    private var shelfFreshAt: [String: Date] = [:]

    func shelf(for chip: String) -> [V4SearchResult] { shelves[chip] ?? [] }
    func hasAttemptedShelf(_ chip: String) -> Bool { attemptedShelves.contains(chip) }

    // MARK: Дисковый кэш полок (22.08.2026)
    //
    // Каталог кинотеатра меняется медленно, а полка собирается из 2–4 сетевых
    // запросов. Последняя удачная полка каждого чипа лежит в UserDefaults:
    // при заходе на Главную контент встаёт мгновенно из кэша, сеть
    // спрашивается только когда кэш старше TTL — и тогда полка обновляется
    // уже под ногами у показанного кэша, а не у скелетона.

    private struct CachedShelf: Codable {
        let savedAt: Date
        let items: [V4SearchResult]
    }
    private static let shelfCacheTTL: TimeInterval = 30 * 60
    // Версия в ключе бампается при смене формата URL в закэшированных
    // элементах — иначе полки со старыми ссылками живут ещё 30 минут:
    // v2 (22.08.2026) — artworkURL кино переехал с poster-horizontal (вшитое
    // название резалось кропом героя) на чистые кадры promo_images;
    // v3 (22.08.2026) — posterURL вырос 234×360 → 390×600 под укрупнённые
    // карточки рельс (128×192 pt на @3x).
    private static func shelfCacheKey(_ chip: String) -> String { "plink.home.shelf.v3.\(chip)" }

    /// Кэш чипа с диска; nil — кэша нет или он нечитаем.
    private func diskShelf(_ chip: String) -> CachedShelf? {
        guard let data = UserDefaults.standard.data(forKey: Self.shelfCacheKey(chip)),
              let cached = try? JSONDecoder().decode(CachedShelf.self, from: data),
              !cached.items.isEmpty else { return nil }
        return cached
    }

    private func persistShelf(_ chip: String, items: [V4SearchResult]) {
        guard !items.isEmpty,
              let data = try? JSONEncoder().encode(CachedShelf(savedAt: Date(), items: items))
        else { return }
        UserDefaults.standard.set(data, forKey: Self.shelfCacheKey(chip))
    }

    /// Осиротевшие ключи полок прошлых версий формата (v1/v2) чистятся один
    /// раз за запуск. Бампы версии (см. shelfCacheKey) оставляли старые JSON
    /// в UserDefaults навсегда — по несколько КБ на чип. Идиома — как в
    /// DMChatService.pruneForeignCaches / FriendManager.
    private static var didPurgeLegacyShelfCaches = false
    private static func purgeLegacyShelfCachesOnce() {
        guard !didPurgeLegacyShelfCaches else { return }
        didPurgeLegacyShelfCaches = true
        let currentPrefix = "plink.home.shelf.v3."
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("plink.home.shelf.") && !key.hasPrefix(currentPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Совместимость со старыми вызовами (iPad-шелл): «тренды» теперь —
    /// полка «Для вас» кинокаталога.
    func loadTrending() async {
        await loadShelf(HomeCinemaCatalog.allChip)
    }

    func loadShelf(_ chip: String, force: Bool = false) async {
        Self.purgeLegacyShelfCachesOnce()
        if !force, !shelf(for: chip).isEmpty { return }
        guard !shelvesInFlight.contains(chip) else { return }
        shelvesInFlight.insert(chip)
        defer { shelvesInFlight.remove(chip) }

        // Дисковый кэш первым: контент на экране мгновенно. Свежий кэш
        // закрывает вопрос целиком, устаревший — остаётся на экране, пока
        // сеть собирает замену (лучше вчерашняя полка, чем скелетон).
        if !force, let cached = diskShelf(chip) {
            shelves[chip] = cached.items
            attemptedShelves.insert(chip)
            shelfFreshAt[chip] = cached.savedAt
            if chip == HomeCinemaCatalog.allChip {
                trending = cached.items
                trendingError = nil
            }
            if Date().timeIntervalSince(cached.savedAt) < Self.shelfCacheTTL {
                return
            }
        }

        // Токен и база снимаются на MainActor до ухода в TaskGroup —
        // дочерние задачи ничего не трогают в сторе.
        let token = AuthTokenStore.shared.token
        let base = apiBase

        // Кинотеатры в приоритете (22.08.2026): полку открывает каталог
        // Иви — настоящие фильмы и сериалы с постерами, годом и рейтингом,
        // а не «фильм полностью» с чужих YouTube-каналов.
        // «Полку обновила сеть» — только если ЖИВОЙ источник (каталог Иви или
        // YouTube-хвост) реально что-то отдал. Кэш трендов (суточный, читается
        // без сети) за сеть не считается: иначе при мёртвой сети 6 карточек из
        // кэша трендов схлопнули бы и выселили с диска показанную полку на 20.
        let cinemaItems = await V4CinemaCatalog.fetchShelf(chip)
        var merged = cinemaItems
        var networkProduced = !cinemaItems.isEmpty
        var firstError: String?

        // Тренды Netflix (22.08.2026): «Для вас» и «Новинки» открываются
        // чередованием трендовых карточек недели с каталогом — герой-карусель
        // несёт и чарт Netflix, и свежие релизы, а не архив каталога.
        if chip == HomeCinemaCatalog.allChip || chip == HomeCinemaCatalog.freshChip {
            let trendCards = await V4TrendsCatalog.cards(apiBase: base, token: token)
            if !trendCards.isEmpty {
                merged = Self.interleaved([trendCards, merged])
            }
        }

        // YouTube остаётся хвостом: добирает полку, когда каталог дал мало
        // (узкий жанр, недоступен api.ivi.ru), и целиком подменяет её,
        // когда кинотеатр не ответил. Полка живёт при падении любого из двух.
        // «Новинкам» хвост нужен всегда: театральные премьеры года живут
        // в свежих YouTube-трейлерах, а не в открытых каталогах.
        if merged.count < 12 || chip == HomeCinemaCatalog.freshChip {
            let queries = HomeCinemaCatalog.queries(for: chip)
            var buckets = Array(repeating: [V4SearchResult](), count: queries.count)
            await withTaskGroup(of: (Int, [V4SearchResult], String?).self) { group in
                for (index, query) in queries.enumerated() {
                    group.addTask {
                        let page = await Self.searchPage(query, apiBase: base, token: token)
                        return (index, page.items, page.error)
                    }
                }
                for await (index, items, error) in group {
                    buckets[index] = items
                    if !items.isEmpty { networkProduced = true }
                    if firstError == nil { firstError = error }
                }
            }

            // Интерлив, не конкатенация: источники хвоста чередуются,
            // а не клеятся списками встык.
            var seen = Set<String>(merged.map(\.id))
            var row = 0
            while true {
                var advanced = false
                for bucket in buckets where row < bucket.count {
                    advanced = true
                    let item = bucket[row]
                    if seen.insert(item.id).inserted { merged.append(item) }
                }
                if !advanced { break }
                row += 1
            }
        }

        // Сеть ничего не дала (обе живые ветки — каталог и YouTube-хвост —
        // пусты), а на экране уже стоит контент (кэш или прежняя загрузка,
        // включая сорвавшийся офлайн pull-to-refresh) — он живее пустоты:
        // полку не перетираем и на диск не пишем. Кэш трендов в merged за сеть
        // не в счёт — иначе он бы выселил показанную полку (см. networkProduced).
        if !networkProduced, !shelf(for: chip).isEmpty { return }

        // Автообновление не должно дёргать экран впустую: если состав полки
        // не изменился, перезапись пропускается — карусели не прыгают, — но
        // свежесть подтверждается и на диске, чтобы TTL не молотил сеть.
        if merged.map(\.id) == shelf(for: chip).map(\.id), !merged.isEmpty {
            shelfFreshAt[chip] = Date()
            persistShelf(chip, items: merged)
            return
        }

        shelves[chip] = merged
        attemptedShelves.insert(chip)
        shelfFreshAt[chip] = Date()
        persistShelf(chip, items: merged)
        if chip == HomeCinemaCatalog.allChip {
            trending = merged
            trendingError = merged.isEmpty ? (firstError ?? "Не удалось загрузить подборку") : nil
        }
    }

    /// Автообновление подборок: полка перезапрашивается, только когда её
    /// свежесть старше TTL. Зовётся таймером Главной и возвратом из фона —
    /// витрина следит за трендами сама, пока приложение открыто.
    func refreshIfStale(_ chip: String) async {
        let freshAt = shelfFreshAt[chip] ?? diskShelf(chip)?.savedAt ?? .distantPast
        guard Date().timeIntervalSince(freshAt) >= Self.shelfCacheTTL else { return }
        await loadShelf(chip, force: true)
    }

    /// Интерлив с дедупликацией — тот же приём, что в V4CinemaCatalog:
    /// источники чередуются, а не клеятся встык.
    private static func interleaved(_ buckets: [[V4SearchResult]]) -> [V4SearchResult] {
        var merged: [V4SearchResult] = []
        var seen = Set<String>()
        var row = 0
        while true {
            var advanced = false
            for bucket in buckets where row < bucket.count {
                advanced = true
                let item = bucket[row]
                if seen.insert(item.id).inserted { merged.append(item) }
            }
            if !advanced { break }
            row += 1
        }
        return merged
    }

    /// Один запрос каталога. Ошибка не бросается, а возвращается текстом:
    /// полка из двух источников должна пережить падение одного из них.
    /// Не private: тем же поиском V4TrendsCatalog собирает карточки трендов.
    ///
    /// Урок от 07.08.2026 сохранён: HTTP-статус проверяется ДО декодирования,
    /// иначе тело ошибки сервера превращается в безымянный DecodingError.
    nonisolated static func searchPage(
        _ query: String, apiBase: String, token: String?, limit: Int = 14
    ) async -> (items: [V4SearchResult], error: String?) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(apiBase)/api/media/search?q=\(encoded)&limit=\(limit)") else {
            return ([], "Не удалось загрузить подборку")
        }
        var req = URLRequest(url: url)
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? "<нечитаемое тело>"
                print("[V4SearchStore] shelf «\(query)»: HTTP \(code) — \(body)")
                #endif
                return ([], "Сервер ответил \(code)")
            }
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            // Невстраиваемые ролики в полку не попадают: их всё равно нельзя
            // смотреть в комнате, а битые карточки на витрине хуже короткой полки.
            // Пустой id (бэкенд отдал элемент без id/videoId) — тоже мимо: тап по
            // такой карточке создал бы комнату с пустым видео.
            return (resp.results.map(V4SearchResult.init)
                .filter { $0.isSelectable && !$0.id.isEmpty }, nil)
        } catch is CancellationError {
            return ([], nil)
        } catch {
            #if DEBUG
            print("[V4SearchStore] shelf «\(query)» failed: \(error)")
            #endif
            return ([], userFacingTrendingError(error))
        }
    }

    /// Тот же подход, что и в V4RoomsStore.userFacingLoadError: системные
    /// описания URLError по-английски и пользователю ничего не говорят.
    /// nonisolated — чистая функция, зовётся из фоновых задач полок.
    nonisolated private static func userFacingTrendingError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет подключения к интернету"
            case .timedOut:
                return "Сервис отвечает слишком долго"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Не удалось подключиться к Plink"
            default:
                return "Не удалось загрузить подборку"
            }
        }
        if error is DecodingError {
            return "Сервер вернул неожиданный ответ"
        }
        return "Не удалось загрузить подборку"
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { state = .idle; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(trimmed)
        }
    }

    private func performSearch(_ query: String) async {
        state = .loading
        // Кино из витрины — первым. Серверный /api/media/search умеет только
        // YouTube, а у Иви рабочего публичного поиска нет (search/v7 всегда
        // пуст, common/v7 отдаёт персон и мусор — проверено 22.08.2026),
        // поэтому фильмы ищутся локально по уже собранным полкам.
        let cinema = cinemaMatches(query)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(apiBase)/api/media/search?q=\(encoded)&limit=20") else { return }
        do {
            var req = URLRequest(url: url)
            if let token = AuthTokenStore.shared.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            var seen = Set(cinema.map(\.id))
            let merged = cinema + resp.results.map(V4SearchResult.init)
                .filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            state = merged.isEmpty ? .empty : .loaded(merged)
        } catch is CancellationError {
            return
        } catch {
            // Сеть упала, но локальные кино-совпадения есть — они полезнее
            // экрана ошибки.
            state = cinema.isEmpty ? .failed(error.localizedDescription) : .loaded(cinema)
        }
    }

    /// Совпадения по названию среди кинокарточек загруженных полок.
    /// Префиксные — выше вхождений в середине; полки обходятся по
    /// отсортированным ключам, чтобы порядок не плясал между запусками.
    private func cinemaMatches(_ query: String) -> [V4SearchResult] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        var seen = Set<String>()
        var prefixHits: [V4SearchResult] = []
        var containsHits: [V4SearchResult] = []
        for chip in shelves.keys.sorted() {
            for item in shelves[chip] ?? [] where item.origin != .youtube {
                guard seen.insert(item.id).inserted else { continue }
                let title = item.title.lowercased()
                if title.hasPrefix(needle) {
                    prefixHits.append(item)
                } else if title.contains(needle) {
                    containsHits.append(item)
                }
            }
        }
        return Array((prefixHits + containsHits).prefix(8))
    }
}

// Codable — ради дискового кэша полок: карточка целиком сериализуется
// в UserDefaults и встаёт на витрину при следующем запуске без сети.
struct V4SearchResult: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let subtitle: String
    /// Широкий кадр: герой, «Рекомендации», превью.
    let artworkURL: URL?
    /// Вертикальный постер для лент; у YouTube-роликов его нет —
    /// вертикальные карточки падают обратно на artworkURL.
    let posterURL: URL?
    let duration: String?
    let isSelectable: Bool
    // Кинотеатры в приоритете (22.08.2026): витрина смешивает два
    // происхождения, и карточка знает своё — от него зависят бейдж превью,
    // страница просмотра и MediaItem будущей комнаты.
    let origin: V4ContentOrigin
    /// Страница просмотра: youtube.com/watch для роликов, ivi.ru/watch — для кино.
    let watchURL: String
    let year: Int?
    let kindLabel: String?
    let ratingText: String?
    /// AVOD-тайтл: на Иви смотрится бесплатно (с рекламой).
    let isFreeOnService: Bool
    let isSeries: Bool

    /// Карточка кинотеатрального каталога (собирает V4CinemaCatalog).
    init(
        id: String, title: String, subtitle: String,
        artworkURL: URL?, posterURL: URL?,
        duration: String?, isSelectable: Bool,
        origin: V4ContentOrigin, watchURL: String,
        year: Int?, kindLabel: String?, ratingText: String?,
        isFreeOnService: Bool, isSeries: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.posterURL = posterURL
        self.duration = duration
        self.isSelectable = isSelectable
        self.origin = origin
        self.watchURL = watchURL
        self.year = year
        self.kindLabel = kindLabel
        self.ratingText = ratingText
        self.isFreeOnService = isFreeOnService
        self.isSeries = isSeries
    }

    init(from v: YouTubeVideoSummary) {
        id = v.videoId
        title = v.title
        subtitle = v.channelTitle
        artworkURL = v.thumbnailURLString.flatMap(URL.init(string:))
        posterURL = nil
        let secs = v.durationSeconds ?? v.duration ?? 0
        if secs > 0 {
            let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
            duration = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        } else { duration = nil }
        isSelectable = v.isEmbeddable
        origin = .youtube
        watchURL = "https://www.youtube.com/watch?v=\(v.videoId)"
        year = nil
        kindLabel = nil
        ratingText = nil
        isFreeOnService = false
        isSeries = false
    }
}

// MARK: - V4 Friends Store (P1.1)

@MainActor
@Observable
final class V4FriendsStore {
    enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, empty, failed(String)
    }
    private(set) var state: LoadState = .idle
    private(set) var friends: [Friend] = []
    private(set) var requests: [FriendRequest] = []
    private(set) var outgoing: [FriendRequest] = []
    /// Exposed for Add Friend sheet (search / send)
    let friendManager: FriendManager

    init(friendManager: FriendManager) { self.friendManager = friendManager }

    func load() async {
        state = .loading
        await friendManager.loadAll()
        friends = friendManager.friends
        requests = friendManager.incomingRequests
        outgoing = friendManager.outgoingRequests
        // Chats section should show "loaded" whenever we have friends,
        // even if requests are empty (sender after accept on other phone).
        state = friends.isEmpty && requests.isEmpty && outgoing.isEmpty ? .empty : .loaded
    }

    /// Quiet refresh without full-screen loading spinner (poll / tab focus).
    func refreshQuietly() async {
        await friendManager.loadAll()
        friends = friendManager.friends
        requests = friendManager.incomingRequests
        outgoing = friendManager.outgoingRequests
        if case .loading = state { return }
        state = friends.isEmpty && requests.isEmpty && outgoing.isEmpty ? .empty : .loaded
    }

    func invite(userID: String, username: String) async {
        _ = await friendManager.sendRequest(to: userID, username: username)
        await load()
    }

    func accept(_ request: FriendRequest) async {
        await friendManager.acceptRequest(request)
        await load()
    }

    func decline(_ request: FriendRequest) async {
        await friendManager.declineRequest(request)
        await load()
    }
}

// MARK: - V4 AI Store (P0.4)

@MainActor
@Observable
final class V4AIStore {
    struct Message: Identifiable, Hashable {
        let id = UUID()
        let isOwn: Bool
        let text: String
        let isBot: Bool
        var proposedAction: AIProposedAction?
    }

    private(set) var messages: [Message] = [
        Message(isOwn: false, text: "Привет! Я Plink AI. Спроси про фильмы, попроси создать комнату или узнать что смотрят друзья.", isBot: true)
    ]
    private(set) var state: String = "Готов помочь"
    private(set) var lastSuggestions: [String] = []  // Подсказки после ответа

    // Персистентная история чата между запусками
    private struct SavedMessage: Codable { let isBot: Bool; let text: String }
    private static let historyKey = "plink.ai.history.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([SavedMessage].self, from: data),
           !saved.isEmpty {
            messages = saved.map { Message(isOwn: !$0.isBot, text: $0.text, isBot: $0.isBot) }
        }
    }

    private func persist() {
        let saved = messages.suffix(40).map { SavedMessage(isBot: $0.isBot, text: $0.text) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    // Очистить историю чата
    func clearHistory() {
        messages = [Message(isOwn: false, text: "Привет! Я Plink AI. Спроси про фильмы, попроси создать комнату или узнать что смотрят друзья.", isBot: true)]
        lastSuggestions = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    func setStatus(_ text: String) {
        state = text
    }
    private let apiBase = PlinkConfig.baseURLString

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(Message(isOwn: true, text: trimmed, isBot: false))
        persist()
        AnalyticsService.shared.track("ai_message_sent")  // Funnel
        state = "Думаю…"

        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/chat")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = AuthTokenStore.shared.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // Send full conversation history — not just the latest message.
            // Backend sends ALL messages to OpenRouter for context memory.
            let conversationMessages: [[String: String]] = messages.map { msg in
                [
                    "role": msg.isBot ? "assistant" : "user",
                    "content": msg.text
                ]
            } + [["role": "user", "content": trimmed]]
            let body: [String: Any] = [
                "messages": conversationMessages,
                "context": ["roomId": NSNull()],
                "mode": "assistant"
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let resp = try JSONDecoder().decode(AIChatResponse.self, from: data)
            messages.append(Message(
                isOwn: false,
                text: resp.message,
                isBot: true,
                proposedAction: resp.proposedAction
            ))
            lastSuggestions = resp.suggestions ?? []
            persist()
            state = "Готов помочь"
        } catch {
            messages.append(Message(isOwn: false, text: "Не удалось ответить. Попробуйте снова.", isBot: true))
            persist()
            state = "Ошибка"
        }
    }

    /// P0.4: Confirm a proposed AI action. Returns the created Room if successful.
    func confirmAction(_ action: AIProposedAction) async -> Room? {
        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/api/ai/confirm-action")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = AuthTokenStore.shared.token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "confirmationId": action.confirmationId,
                "idempotencyKey": UUID().uuidString
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let resp = try JSONDecoder().decode(ConfirmActionResponse.self, from: data)
            return resp.room
        } catch {
            return nil
        }
    }
}

struct AIChatResponse: Decodable {
    let message: String
    let suggestions: [String]?
    let proposedAction: AIProposedAction?
}

struct ConfirmActionResponse: Decodable {
    let success: Bool
    let room: Room?
}

struct AIProposedAction: Decodable, Hashable {
    let type: String
    let confirmationId: String
    let expiresAt: String?
    let payloadPreview: AIPayloadPreview?
}

struct AIPayloadPreview: Decodable, Hashable {
    let title: String?
    let privacy: String?
    let queueCount: Int?
}

// MARK: - V4 Profile Store (P1.3)

@MainActor
@Observable
final class V4ProfileStore {
    private(set) var displayName: String = "Загрузка…"
    private(set) var username: String = ""
    private(set) var email: String = ""
    private(set) var avatarURL: URL?
    /// Instant local preview (survives dismiss before AsyncImage refetch)
    private(set) var localAvatarImage: UIImage?
    private(set) var isPremium: Bool = false
    /// Серверная дата окончания Plink+ (`User.premiumUntil` из /users/me).
    /// nil = пожизненный доступ либо сервер дату не сообщил.
    private(set) var premiumUntil: Date?
    private(set) var isAdmin: Bool = false
    private(set) var selectedTheme: V4Theme = .electric
    /// Пресет обложки профиля. Хранится токеном `plink://cover/<id>` в
    /// серверном coverURL (синк между устройствами) + в defaults для
    /// мгновенной отрисовки до первого /users/me.
    private(set) var coverStyle: V4CoverStyle = .hall
    /// Своя обложка из галереи: файл на диске + data-URL в том же coverURL.
    /// customCoverImage живёт независимо от флага — после переключения на
    /// пресет фото остаётся в пикере и его можно вернуть без перевыбора.
    private(set) var customCoverImage: UIImage?
    private(set) var usesCustomCover: Bool = false
    private let authService: AuthService
    private let defaults = UserDefaults.standard

    private var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plink_avatar.jpg")
    }

    private var coverFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("plink_cover.jpg")
    }

    init(authService: AuthService) {
        self.authService = authService
        if let saved = defaults.string(forKey: "v4_theme") {
            selectedTheme = V4Theme(rawValue: saved) ?? .electric
        }
        // fromStored маппит id старых процедурных пресетов на фото.
        if let style = V4CoverStyle.fromStored(defaults.string(forKey: "plink_user_cover_style")) {
            coverStyle = style
        }
        usesCustomCover = defaults.bool(forKey: "plink_user_cover_custom")
        loadLocalCoverFile()
        // Флаг без файла (стёрли данные) — не рисовать пустоту.
        if customCoverImage == nil { usesCustomCover = false }
        loadSavedAvatar()
    }

    func load() async {
        // Prefer server user; keep local image if server URL missing
        do {
            let user = try await authService.fetchCurrentUser()
            applyUser(user)
            authService.updateCachedUser(user)
        } catch {
            if let user = await authService.currentUser() {
                applyUser(user)
            }
        }
        // Always try disk for instant paint
        if localAvatarImage == nil {
            loadLocalAvatarFile()
        }
    }

    /// Apply user fields to the profile tab (after save or notification).
    func applyUser(_ user: User) {
        displayName = (user.displayName?.isEmpty == false) ? user.displayName! : user.username
        username = user.username
        email = user.email
        isPremium = user.isPremium
        isAdmin = user.isAdmin
        // Раньше сюда уходило собственное поле
        // `premiumUntil`, которое никто никогда не заполнял → всегда nil.
        // Теперь дату приносит сам ответ сервера.
        premiumUntil = user.premiumUntil
        // Authoritative premium from server (clears sticky local Plink+ on free devices)
        PremiumStatusManager.shared.syncFromServer(
            isPremium: user.isPremium,
            expiry: user.isPremium ? user.premiumUntil : nil
        )
        if let raw = user.avatarURL, !raw.isEmpty {
            avatarURL = Self.cacheBustedURL(from: raw)
            defaults.set(avatarURL?.absoluteString, forKey: "plink_user_avatar_url")
        }
        // Обложка с сервера — только если значение распознано: nil или
        // чужой формат не сбрасывают локальный выбор (PATCH мог не доехать).
        if let raw = user.coverURL, raw.hasPrefix("data:image") {
            // Своя обложка (могла смениться с другого устройства). Файл
            // перезаписываем только при изменении данных — размер в defaults
            // дешевле сравнения содержимого.
            if let comma = raw.firstIndex(of: ","),
               let data = Data(base64Encoded: String(raw[raw.index(after: comma)...])),
               let image = UIImage(data: data) {
                if data.count != defaults.integer(forKey: "plink_user_cover_data_size") {
                    customCoverImage = image
                    try? data.write(to: coverFileURL, options: .atomic)
                    defaults.set(data.count, forKey: "plink_user_cover_data_size")
                } else if customCoverImage == nil {
                    customCoverImage = image
                }
                usesCustomCover = true
                defaults.set(true, forKey: "plink_user_cover_custom")
            }
        } else if let style = V4CoverStyle.parse(user.coverURL) {
            coverStyle = style
            usesCustomCover = false
            defaults.set(style.rawValue, forKey: "plink_user_cover_style")
            defaults.set(false, forKey: "plink_user_cover_custom")
        }
        defaults.set(displayName, forKey: "plink_current_display_name")
        defaults.set(user.role ?? "USER", forKey: "plink_current_user_role")
        defaults.set(user.id, forKey: "plink_current_user_id")
        // Force friend-list / chat avatars to refetch after profile avatar change
        PlinkAvatarURL.bumpSessionBust()
    }

    func selectTheme(_ theme: V4Theme) {
        selectedTheme = theme
        defaults.set(theme.rawValue, forKey: "v4_theme")
    }

    /// Применить пресет обложки: мгновенно локально, на сервер — фоном.
    /// PATCH одним полем безопасен: авто-Encodable опускает nil-ключи,
    /// сервер обновляет только coverURL.
    func applyCover(_ style: V4CoverStyle) {
        coverStyle = style
        usesCustomCover = false
        defaults.set(style.rawValue, forKey: "plink_user_cover_style")
        defaults.set(false, forKey: "plink_user_cover_custom")
        Task { [authService] in
            if let user = try? await authService.updateProfile(coverURL: style.remoteToken) {
                authService.updateCachedUser(user)
            }
        }
    }

    /// Применить свою обложку из галереи. Канал — тот же coverURL: колонка
    /// на сервере TEXT, поэтому data-URL едет туда как обычная строка и
    /// синкается между устройствами без нового эндпоинта. Кроп 2:1 делает
    /// пикер; здесь — компрессия под bodyLimit сервера (2 МБ на весь JSON,
    /// base64 добавляет ~33%, целимся в ~500 КБ JPEG).
    func applyCustomCover(_ image: UIImage) {
        customCoverImage = image
        usesCustomCover = true
        defaults.set(true, forKey: "plink_user_cover_custom")

        var quality: CGFloat = 0.8
        var jpeg = image.jpegData(compressionQuality: quality)
        while let d = jpeg, d.count > 500_000, quality > 0.35 {
            quality -= 0.1
            jpeg = image.jpegData(compressionQuality: quality)
        }
        guard let jpeg else { return }
        try? jpeg.write(to: coverFileURL, options: .atomic)
        defaults.set(jpeg.count, forKey: "plink_user_cover_data_size")

        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        Task { [authService] in
            if let user = try? await authService.updateProfile(coverURL: dataURL) {
                authService.updateCachedUser(user)
            }
        }
    }

    private func loadLocalCoverFile() {
        if FileManager.default.fileExists(atPath: coverFileURL.path),
           let data = try? Data(contentsOf: coverFileURL),
           let img = UIImage(data: data) {
            customCoverImage = img
        }
    }

    /// Apply avatar (local image always; server URL when available).
    func applyAvatar(image: UIImage, serverURL: URL?) {
        self.localAvatarImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: avatarFileURL, options: .atomic)
        }
        var urlString: String?
        if let serverURL, serverURL.scheme == "http" || serverURL.scheme == "https" {
            let busted = Self.cacheBustedURL(from: serverURL.absoluteString) ?? serverURL
            self.avatarURL = busted
            urlString = busted.absoluteString
            defaults.set(urlString, forKey: "plink_user_avatar_url")
        }
        if let u = authService.currentUserValue {
            let updated = User(
                id: u.id,
                username: u.username,
                email: u.email,
                avatarURL: urlString ?? u.avatarURL,
                avatarData: u.avatarData,
                displayName: u.displayName,
                coverURL: u.coverURL,
                isOnline: u.isOnline,
                isPremium: u.isPremium,
                // Копия пользователя ради аватара не должна терять серверную
                // дату Plink+ — иначе кэш профиля забывает её до следующего
                // /users/me.
                premiumUntil: u.premiumUntil,
                role: u.role,
                createdAt: u.createdAt
            )
            authService.updateCachedUser(updated)
        }
        NotificationCenter.default.post(name: ProfileViewModel.avatarChangedNotification, object: nil)
    }

    func loadSavedAvatar() {
        if let saved = defaults.string(forKey: "plink_user_avatar_url") {
            self.avatarURL = URL(string: saved)
        }
        loadLocalAvatarFile()
    }

    private func loadLocalAvatarFile() {
        if FileManager.default.fileExists(atPath: avatarFileURL.path),
           let data = try? Data(contentsOf: avatarFileURL),
           let img = UIImage(data: data) {
            localAvatarImage = img
        }
    }

    static func cacheBustedURL(from raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return URL(string: raw) }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "t" || $0.name == "v" }
        items.append(URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = items
        return components.url
    }
}

// ─────────────────────────────────────────────────────────────
// Перенесено 26.07.2026 из Views/Home/YouTubeSearchView.swift:
// экранная часть того файла мертва (0 вызовов), но эти DTO декодирует
// живой мост ниже. Перенос сделан ДО удаления файла.
// ─────────────────────────────────────────────────────────────

struct YouTubeVideoSummary: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let channel: String
    let thumbnailURL: String?
    // Backend may send `durationSeconds` (new) or `duration` (legacy).
    // Decode either; prefer durationSeconds when present.
    let durationSeconds: Int?
    let duration: Int?
    let url: String?
    let embeddable: Bool?
    let privacyStatus: String?
    let liveBroadcastContent: String?

    // Back-compat: when backend omits these, default to safe values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` may be missing if backend returns videoId only — fall back to videoId.
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .videoId)
            ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        // `channel` may be missing — fall back to channelTitle.
        self.channel = try c.decodeIfPresent(String.self, forKey: .channel)
            ?? c.decodeIfPresent(String.self, forKey: .channelTitle)
            ?? ""
        self.thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        self.durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        self.duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.embeddable = try c.decodeIfPresent(Bool.self, forKey: .embeddable)
        self.privacyStatus = try c.decodeIfPresent(String.self, forKey: .privacyStatus)
        self.liveBroadcastContent = try c.decodeIfPresent(String.self, forKey: .liveBroadcastContent)
    }

    private enum CodingKeys: String, CodingKey {
        case id, videoId, title, channel, channelTitle
        case thumbnailURL, duration, durationSeconds
        case url, embeddable, privacyStatus, liveBroadcastContent
    }

    // Convenience accessors
    var videoId: String { id }
    var channelTitle: String { channel }
    var resolvedDurationSeconds: Int? { durationSeconds ?? duration }
    var thumbnailURLString: String? { thumbnailURL }
    var resolvedLiveBroadcastContent: String { liveBroadcastContent ?? "none" }
    var resolvedEmbeddable: Bool? { embeddable }

    // Brain Revision 3: row states based on embeddable field.
    //   - true → selectable (green checkmark when selected)
    //   - false → disabled, "Нельзя встроить" label, lock icon, 50% opacity
    //   - nil → selectable but with "Проверим при запуске" hint (amber dot)
    var embeddableState: EmbeddableState {
        if let embeddable {
            return embeddable ? .embeddable : .notEmbeddable
        }
        return .unknown
    }

    enum EmbeddableState {
        case embeddable      // embeddable == true  → selectable, no badge
        case notEmbeddable   // embeddable == false → disabled, "Нельзя встроить"
        case unknown         // embeddable == nil   → selectable, "Проверим при запуске"
    }

    var isEmbeddable: Bool { embeddable != false }

    var isLive: Bool { resolvedLiveBroadcastContent == "live" }

    var durationText: String? {
        guard let seconds = resolvedDurationSeconds, seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct YouTubeSearchResponse: Decodable, Sendable {
    let results: [YouTubeVideoSummary]
}
