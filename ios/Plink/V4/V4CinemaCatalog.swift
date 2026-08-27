// Plink/V4/V4CinemaCatalog.swift
// 22.08.2026: «кинотеатры в приоритете».
//
// Витрина Главной наполнялась только YouTube-поиском через бэкенд-прокси —
// на полках стояли трейлеры и «фильм полностью» с чужих каналов. Люди же
// ждут кино из онлайн-кинотеатров. Роут бэкенда менять нельзя (деплой не в
// наших руках), поэтому кинотеатральный каталог собирается клиентом.
//
// 26.08.2026: «витрина не должна состоять из одного Иви».
//
// Источников два, и оба публичные — это все российские кинотеатры, которые
// отдают афишу без ключа и без подписи запроса (проверено вживую 26.08.2026):
//
//   • Иви     — api.ivi.ru/mobileapi/catalogue/v7 (категории, жанры, годы);
//   • PREMIER — premier.one/uma-api/metainfo/tv   (без фильтров, см. ниже).
//
// Полка склеивается из обоих круговым интерливом: Иви → PREMIER → Иви → …,
// чтобы подпись под карточками чередовалась, а не повторяла одно название
// кинотеатра весь ряд.
//
// Почему не Кинопоиск, Окко, Смотрим и Wink — их каталог закрыт, и обойти
// это нечем: api.kinopoisk.dev требует токен, ctx.okko.tv не резолвится в DNS
// (а www.okko.tv отдаёт JS-заглушку антибота), apis.smotrim.ru/graphql
// отвечает 400, а его /api/v1/videos — только региональной новостной лентой,
// wink.ru и more.tv закрыты 403. Поэтому они подключены «мостиком»: из превью
// тайтла можно создать комнату сразу на странице поиска этого кинотеатра
// (V4WatchTarget). Plink не предоставляет контент и не обходит защиту —
// только открывает официальные страницы.

import Foundation

// MARK: - Происхождение карточки витрины

/// Откуда карточка на витрине: ролик видеохостинга или тайтл кинокаталога.
/// От происхождения зависят бейдж превью, подпись героя и то, какой
/// MediaItem соберёт комната. Codable — ради дискового кэша полок.
enum V4ContentOrigin: Hashable, Sendable, Codable {
    case youtube
    /// Ролик стороннего видеохостинга — RuTube, VK Видео. Подпись строится
    /// из канала и длительности, как у YouTube; год и рейтинг у роликов
    /// отсутствуют, а «Где ещё смотреть» к ним неприменимо.
    case video(VideoService)
    case cinema(VideoService)

    /// Сервис карточки: он же бейдж превью и цвет.
    var service: VideoService {
        switch self {
        case .youtube: return .youtube
        case .video(let s), .cinema(let s): return s
        }
    }

    /// Ролик, а не тайтл каталога: мета берётся из канала и длительности.
    var isClip: Bool {
        if case .cinema = self { return false }
        return true
    }
}

/// Что именно смотреть из превью тайтла: сам элемент («Смотреть вместе»)
/// или тот же тайтл в другом кинотеатре (ряд «Где ещё смотреть»).
enum V4WatchTarget: Hashable, Sendable {
    case native
    case cinema(VideoService, String)
}

// MARK: - Каталог кинотеатров (агрегатор + Иви)

/// Фасад витрины: снаружи виден только `fetchShelf` — что внутри одного
/// кинотеатра, двух или пяти, вызывающая сторона не знает. Здесь же лежит
/// каталог Иви; PREMIER — ниже, отдельным типом.
enum V4CinemaCatalog {
    // MARK: Запросы полок

    /// Один запрос к каталогу. Полка склеивается из нескольких запросов
    /// интерливом — как и YouTube-полки в V4SearchStore.
    struct Query: Sendable {
        var category: Int?
        var genres: [Int] = []
        var sort: String = "pop"
        var yearFrom: Int?
    }

    /// Текущий год — «новинки» считаются, а не вписаны: вписанный год
    /// протухает сам собой на следующий январь.
    static var nowYear: Int { Calendar.current.component(.year, from: Date()) }

    // Идентификаторы категорий и жанров сверены с /mobileapi/categories/v6
    // 22.08.2026: фильмы 14 (фантастика 166, фэнтези 204, ужасы 99,
    // комедии 95, аниме 418), сериалы 15 (фантастика 190, фэнтези 236,
    // комедийные 110, триллеры 128), мультфильмы 17 (аниме 125).
    //
    // Свежесть (22.08.2026, вторая волна): каждую полку открывает бакет
    // «премьеры этого/прошлого года» — интерлив ставит новинки в чётные
    // позиции, и герой-карусель всегда несёт свежие релизы, а не архив
    // 2024–2025. Сортировка нарочно pop, не new: «new» у Иви — «недавно
    // добавленное», и по свежим годам он забит региональными озвучками.
    static func queries(for chip: String) -> [Query] {
        switch chip {
        case HomeCinemaCatalog.freshChip:
            return [Query(category: 14, yearFrom: nowYear - 1),
                    Query(category: 15, yearFrom: nowYear - 1),
                    Query(category: 14, sort: "new", yearFrom: nowYear)]
        case "Фильмы":
            return [Query(category: 14, yearFrom: nowYear - 1),
                    Query(category: 14),
                    Query(category: 14, sort: "new", yearFrom: 2015)]
        case "Сериалы":
            return [Query(category: 15, yearFrom: nowYear - 1),
                    Query(category: 15),
                    Query(category: 15, sort: "new")]
        case "Мультфильмы":
            return [Query(category: 17, yearFrom: nowYear - 1),
                    Query(category: 17),
                    Query(category: 17, sort: "new")]
        case "Фантастика":
            return [Query(category: 14, genres: [166, 204], yearFrom: nowYear - 2),
                    Query(category: 14, genres: [166, 204]),
                    Query(category: 15, genres: [190, 236])]
        case "Комедии":
            return [Query(category: 14, genres: [95], yearFrom: nowYear - 2),
                    Query(category: 14, genres: [95]),
                    Query(category: 15, genres: [110])]
        case "Ужасы":
            return [Query(category: 14, genres: [99, 127], yearFrom: nowYear - 2),
                    Query(category: 14, genres: [99, 127]),
                    Query(category: 15, genres: [128])]
        case "Аниме":
            return [Query(category: 17, genres: [125]),
                    Query(category: 14, genres: [418])]
        case HomeCinemaCatalog.topWeekShelf:
            return [Query(category: 14, yearFrom: nowYear - 1),
                    Query(category: 14, yearFrom: 2019),
                    Query(category: 15, yearFrom: 2019)]
        default: // «Для вас»
            return [Query(category: 14, yearFrom: nowYear - 1),
                    Query(),
                    Query(category: 14, sort: "new", yearFrom: 2018)]
        }
    }

    // MARK: Загрузка полки

    /// Кинотеатральная часть полки: Иви и PREMIER тянутся параллельно и
    /// чередуются на ряду. Ошибки сети не бросаются — пустой результат
    /// означает «добери полку YouTube-хвостом», а отказ одного кинотеатра
    /// полку не роняет: её несёт второй.
    static func fetchShelf(_ chip: String) async -> [V4SearchResult] {
        async let ivi = fetchIviShelf(chip)
        async let premier = V4PremierCatalog.fetchShelf(chip)
        return interleaveCinemas([await ivi, await premier])
    }

    /// Круговой интерлив по кинотеатрам: Иви → PREMIER → Иви → PREMIER.
    ///
    /// Иви открывает ряд — у него глубже каталог, есть рейтинг Кинопоиска и
    /// чистый кадр для героя. PREMIER встаёт в каждую вторую позицию, пока не
    /// кончится (по узким чипам вроде «Аниме» его в каталоге просто нет),
    /// дальше ряд достраивает Иви.
    ///
    /// Дедупликация двойная: по id — от повторов внутри кинотеатра, по
    /// «название + год» — от одного тайтла, который лежит и там и там.
    /// Первым выигрывает тот, кто раньше в ряду.
    private static func interleaveCinemas(_ buckets: [[V4SearchResult]]) -> [V4SearchResult] {
        var merged: [V4SearchResult] = []
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()
        var row = 0
        while true {
            var advanced = false
            for bucket in buckets where row < bucket.count {
                advanced = true
                let item = bucket[row]
                guard seenIDs.insert(item.id).inserted else { continue }
                let titleKey = item.title.lowercased() + "|" + (item.year.map(String.init) ?? "")
                guard seenTitles.insert(titleKey).inserted else { continue }
                merged.append(item)
            }
            if !advanced { break }
            row += 1
        }
        return merged
    }

    /// Полка Иви: несколько запросов каталога параллельно, потом интерлив.
    private static func fetchIviShelf(_ chip: String) async -> [V4SearchResult] {
        let queries = queries(for: chip)
        guard !queries.isEmpty else { return [] }

        var buckets = Array(repeating: [V4SearchResult](), count: queries.count)
        await withTaskGroup(of: (Int, [V4SearchResult]).self) { group in
            for (index, query) in queries.enumerated() {
                group.addTask { (index, await fetchPage(query)) }
            }
            for await (index, items) in group {
                buckets[index] = items
            }
        }

        // Интерлив с дедупликацией: у «Фантастики» фильмы и сериалы должны
        // чередоваться, а тайтл, попавший и в pop, и в new, — стоять один раз.
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

    private static func fetchPage(_ query: Query) async -> [V4SearchResult] {
        var components = URLComponents(string: "https://api.ivi.ru/mobileapi/catalogue/v7/")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "fields", value: "id,title,year,years,kind,posters,promo_images,kp_rating,ivi_rating_10,content_paid_types"),
            URLQueryItem(name: "sort", value: query.sort),
            URLQueryItem(name: "top", value: "20"),
        ]
        if let category = query.category {
            items.append(URLQueryItem(name: "category", value: String(category)))
        }
        if !query.genres.isEmpty {
            items.append(URLQueryItem(
                name: "genre",
                value: query.genres.map(String.init).joined(separator: ",")
            ))
        }
        if let yearFrom = query.yearFrom {
            items.append(URLQueryItem(name: "year_from", value: String(yearFrom)))
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                print("[V4CinemaCatalog] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) для \(url)")
                #endif
                return []
            }
            let decoded = try JSONDecoder().decode(CatalogueResponse.self, from: data)
            return decoded.result.compactMap { mapItem($0, query: query) }
        } catch {
            #if DEBUG
            print("[V4CinemaCatalog] полка не загрузилась: \(error)")
            #endif
            return []
        }
    }

    // MARK: Маппинг в карточку витрины

    private static func mapItem(_ raw: CatalogueItem, query: Query) -> V4SearchResult? {
        guard let title = raw.title, !title.isEmpty else { return nil }
        // Региональные озвучки («…на киргизском языке…») в общероссийской
        // витрине выглядят случайными — каталог отдаёт их без гео-фильтра.
        if title.contains("языке") { return nil }

        let year = raw.year ?? raw.years?.first
        let isSeries = raw.kind == 2
        let kindLabel: String
        if query.category == 17 {
            kindLabel = isSeries ? "Мультсериал" : "Мультфильм"
        } else {
            kindLabel = isSeries ? "Сериал" : "Фильм"
        }

        // Рейтинг: Кинопоиск понятнее людям, Иви — запасной.
        var ratingText: String?
        if let kp = raw.kpRatingValue, kp >= 1 {
            ratingText = String(format: "%.1f", kp).replacingOccurrences(of: ".", with: ",")
        } else if let ivi = raw.iviRating10, ivi >= 1 {
            ratingText = String(format: "%.1f", ivi).replacingOccurrences(of: ".", with: ",")
        }

        var meta: [String] = ["Иви"]
        if let year { meta.append(String(year)) }
        meta.append(kindLabel)
        if let ratingText { meta.append("★ \(ratingText)") }

        return V4SearchResult(
            id: "ivi-\(raw.id)",
            title: title,
            subtitle: meta.joined(separator: " · "),
            // Широкий кадр — из promo_images: у poster-horizontal название
            // фильма вшито в картинку, и кроп героя резал его по живому.
            artworkURL: heroArtwork(raw) ?? poster(raw, type: "poster-horizontal", size: "1216x684"),
            // 390×600 — под карточку 128×192 pt на @3x (384×576 px): прежние
            // 234×360 растягивались в полтора раза и мылили постер.
            posterURL: poster(raw, type: "poster-vertical", size: "390x600"),
            duration: nil,
            isSelectable: true,
            origin: .cinema(.ivi),
            watchURL: "https://www.ivi.ru/watch/\(raw.id)",
            year: year,
            kindLabel: kindLabel,
            ratingText: ratingText,
            isFreeOnService: raw.contentPaidTypes?.contains("AVOD") == true,
            isSeries: isSeries
        )
    }

    /// Постер нужного типа: http → https (ATS), суффикс размера — чтобы
    /// лента не тянула оригиналы 782×1200 и 3840×2160.
    private static func poster(_ raw: CatalogueItem, type: String, size: String) -> URL? {
        guard let posters = raw.posters else { return nil }
        let match = posters.first(where: { $0.type == type }) ?? posters.first
        return sizedURL(match?.url, size: size)
    }

    /// Чистый широкий кадр для героя и превью — из promo_images.
    ///
    /// Иви помечает форматы прямо в content_format: `BackgroundImage-*` —
    /// фон карточки тайтла в их собственном приложении (без текста),
    /// `…-clean` — постер без вшитого названия, `Shots-*` — кадр из фильма.
    /// Берётся первый горизонтальный по этому приоритету; хвост цепочки —
    /// MobilePromo (текст встречается, но реже, чем в poster-horizontal,
    /// где название вшито всегда). Сравнение через lowercased не спасает от
    /// кириллической «х» в размерах («1280х720») — она в суффиксе формата,
    /// а не в искомых словах, поэтому не мешает.
    private static func heroArtwork(_ raw: CatalogueItem) -> URL? {
        guard let promos = raw.promoImages, !promos.isEmpty else { return nil }
        func firstWide(_ predicate: (String) -> Bool) -> PromoImage? {
            promos.first { p in
                guard let f = p.contentFormat, let w = p.width, let h = p.height,
                      w > h, p.url != nil else { return false }
                return predicate(f)
            }
        }
        let match = firstWide { $0.hasPrefix("BackgroundImage-") }
            ?? firstWide { $0.contains("-clean") }
            ?? firstWide { $0.hasPrefix("Shots-") }
            ?? firstWide { $0.hasPrefix("MobilePromo-") }
        return sizedURL(match?.url, size: "1216x684")
    }

    private static func sizedURL(_ urlString: String?, size: String) -> URL? {
        guard var urlString else { return nil }
        if urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst("http://".count)
        }
        if !urlString.hasSuffix("/") { urlString += "/" }
        return URL(string: urlString + size + "/")
    }

    // MARK: Мостик в другие кинотеатры

    /// Кинотеатры, где тайтл можно поискать одним тапом из превью.
    static let bridgeServices: [VideoService] = [.kinopoisk, .okko, .wink, .premier]

    /// Официальная страница поиска кинотеатра по названию тайтла.
    static func searchURL(for service: VideoService, title: String) -> String? {
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        switch service {
        case .kinopoisk: return "https://www.kinopoisk.ru/index.php?kp_query=\(query)"
        case .okko:      return "https://okko.tv/search/\(query)"
        case .wink:      return "https://wink.ru/search?query=\(query)"
        case .premier:   return "https://premier.one/search?query=\(query)"
        case .ivi:       return "https://www.ivi.ru/search/?q=\(query)"
        default:         return nil
        }
    }

    // MARK: DTO каталога

    /// Обёртка «пропусти битый элемент»: декод JSON-массива в Swift —
    /// всё или ничего, а чужой каталог Иви без гарантий схемы может
    /// прислать один аномальный тайтл. Каждый элемент декодится отдельно,
    /// неразобранный отбрасывается — страница из 20 не теряется целиком.
    private struct Safe<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    private struct CatalogueResponse: Decodable {
        let result: [CatalogueItem]

        private enum CodingKeys: String, CodingKey { case result }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let lenient = try c.decodeIfPresent([Safe<CatalogueItem>].self, forKey: .result)
            result = (lenient ?? []).compactMap(\.value)
        }
    }

    private struct CatalogueItem: Decodable {
        let id: Int
        let title: String?
        let year: Int?
        let years: [Int]?
        let kind: Int?
        let posters: [Poster]?
        let promoImages: [PromoImage]?
        let kpRating: String?
        let kpRatingNumber: Double?
        let iviRating10: Double?
        let contentPaidTypes: [String]?

        var kpRatingValue: Double? {
            kpRatingNumber ?? kpRating.flatMap(Double.init)
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, year, years, kind, posters
            case promoImages = "promo_images"
            case kpRating = "kp_rating"
            case iviRating10 = "ivi_rating_10"
            case contentPaidTypes = "content_paid_types"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id — единственное обязательное поле: карточка без него бесполезна
            // (Safe-обёртка такой элемент отбросит). Остальные поля Иви отдаёт
            // без гарантий типа, поэтому неожиданный тип гасится через try?, а
            // не роняет тайтл целиком.
            id = try c.decode(Int.self, forKey: .id)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
            year = try? c.decodeIfPresent(Int.self, forKey: .year)
            years = try? c.decodeIfPresent([Int].self, forKey: .years)
            kind = try? c.decodeIfPresent(Int.self, forKey: .kind)
            posters = try? c.decodeIfPresent([Poster].self, forKey: .posters)
            promoImages = try? c.decodeIfPresent([PromoImage].self, forKey: .promoImages)
            // kp_rating приходит строкой («6.61»), но на части карточек —
            // числом; декодируются оба варианта.
            kpRating = try? c.decodeIfPresent(String.self, forKey: .kpRating)
            kpRatingNumber = try? c.decodeIfPresent(Double.self, forKey: .kpRating)
            iviRating10 = try? c.decodeIfPresent(Double.self, forKey: .iviRating10)
            contentPaidTypes = try? c.decodeIfPresent([String].self, forKey: .contentPaidTypes)
        }
    }

    private struct Poster: Decodable {
        let type: String?
        let url: String?
    }

    private struct PromoImage: Decodable {
        let url: String?
        let contentFormat: String?
        let width: Int?
        let height: Int?

        private enum CodingKeys: String, CodingKey {
            case url, width, height
            case contentFormat = "content_format"
        }
    }
}

// MARK: - Каталог PREMIER (26.08.2026)
//
// Витрина состояла из одного Иви — и это было видно: подпись «Иви» на каждой
// карточке подряд. Второй кинотеатр с открытым каталогом нашёлся один —
// PREMIER: `premier.one/uma-api/metainfo/tv/` отдаёт афишу без ключа и без
// подписи запроса (проверено вживую 26.08.2026).
//
// У этого API нет ни поиска, ни фильтров, ни сортировки: параметры `type`,
// `ordering`, `sort`, `page_size` он молча игнорирует, `per_page` прибит к 12,
// порядок — по возрастанию id, то есть свежие тайтлы лежат в самом хвосте.
// Поля `count` тоже нет — только `has_next`. Поэтому клиент сначала находит
// номер последней страницы, потом тянет хвост пачкой и фильтрует по чипу сам.
// Пул общий для всех полок: строится один раз, живёт сутки на диске.
enum V4PremierCatalog {
    // MARK: Настройки источника

    private static let host = "https://premier.one/uma-api/metainfo/tv/"
    /// Сколько последних страниц каталога составляют пул. 16 × 12 = 192 сырых
    /// тайтла → ~159 уникальных (замер 26.08.2026), запрос всего пула — 1,9 с
    /// при шести параллельных соединениях.
    private static let poolPages = 16
    private static let maxParallel = 6
    /// С какой страницы начинается поиск хвоста на первом запуске. 603 —
    /// последняя страница на 26.08.2026; значение только затравка, дальше
    /// клиент хранит найденное сам.
    private static let seedLastPage = 603
    /// Бюджет поиска хвоста в запросах. Каталог растёт примерно на страницу в
    /// месяц: шага в одну страницу хватает, а если приложение не запускали
    /// полгода — хвост догоняется за несколько холодных стартов, каждый раз
    /// сохраняя новое приближение.
    private static let tailProbeBudget = 8

    private static let poolCacheKey = "plink.home.premier.pool.v1"
    private static let lastPageKey = "plink.home.premier.lastpage.v1"
    private static let cacheTTL: TimeInterval = 24 * 60 * 60

    // MARK: Тайтл пула

    /// Карточка витрины плюс то, по чему её отбирает чип. Жанр и тип нужны
    /// после декода, поэтому лежат в кэше рядом с готовой карточкой —
    /// пересобирать пул ради фильтра нельзя, он суточный.
    struct PooledTitle: Codable, Sendable {
        let card: V4SearchResult
        let genreIDs: [Int]
        let typeName: String
        let year: Int?
    }

    private struct CachedPool: Codable {
        let savedAt: Date
        let titles: [PooledTitle]
    }

    // MARK: Отбор под чип

    // Идентификаторы жанров сверены с /uma-api/metainfo/genre/ (26.08.2026):
    // 1 Фантастика, 3 Комедия, 12 Мистика, 14 Юмор, 16 Анимация, 17 Фэнтези,
    // 20 Ужасы, 29 Мультфильм, 34 Аниме, 45 Скетчком.
    private static func matches(_ title: PooledTitle, chip: String) -> Bool {
        func genre(_ ids: Set<Int>) -> Bool { !ids.isDisjoint(with: title.genreIDs) }
        switch chip {
        case HomeCinemaCatalog.freshChip:
            guard let year = title.year else { return false }
            return year >= V4CinemaCatalog.nowYear - 1
        case "Фильмы":       return title.typeName == "movie"
        case "Сериалы":      return title.typeName == "series"
        case "Мультфильмы":  return genre([29, 16])
        case "Фантастика":   return genre([1, 17])
        case "Комедии":      return genre([3, 14, 45])
        case "Ужасы":        return genre([20, 12])
        case "Аниме":        return genre([34])
        default:             return true // «Для вас», ™topweek
        }
    }

    /// Сколько тайтлов PREMIER отдаёт на одну полку.
    ///
    /// Без потолка широкий чип забирал весь пул: на «Для вас» вставало 159
    /// карточек PREMIER против 46 у Иви, чередование кончалось на 46-й, и
    /// дальше тянулся хвост из одного кинотеатра — ровно то, от чего уходили.
    /// 24 держат чередование по всей видимой части полки.
    private static let shelfLimit = 24

    /// Кинотеатральная часть полки от PREMIER. Ошибки наружу не идут: пустой
    /// ответ означает «полку несёт Иви», а не сбой витрины.
    static func fetchShelf(_ chip: String) async -> [V4SearchResult] {
        let pool = await Pool.shared.titles()
        return pool.lazy.filter { matches($0, chip: chip) }.prefix(shelfLimit).map(\.card)
    }

    // MARK: Пул хвоста

    /// Общий пул на все полки. Девять чипов Главной просыпаются почти
    /// одновременно — актор гарантирует, что каталог соберётся один раз, а не
    /// девять: параллельные вызовы ждут одну и ту же задачу.
    private actor Pool {
        static let shared = Pool()

        private var titlesInMemory: [PooledTitle] = []
        private var loadedAt: Date?
        private var inFlight: Task<[PooledTitle], Never>?

        func titles() async -> [PooledTitle] {
            if let loadedAt, !titlesInMemory.isEmpty,
               Date().timeIntervalSince(loadedAt) < cacheTTL {
                return titlesInMemory
            }
            if let inFlight { return await inFlight.value }

            let cached = readCache()
            if let cached, Date().timeIntervalSince(cached.savedAt) < cacheTTL {
                titlesInMemory = cached.titles
                loadedAt = cached.savedAt
                return cached.titles
            }

            let task = Task<[PooledTitle], Never> { await build() }
            inFlight = task
            let fresh = await task.value
            inFlight = nil

            // Сеть не ответила — отдаём протухший кэш: вчерашняя афиша
            // PREMIER на полке лучше, чем полка из одного Иви.
            guard !fresh.isEmpty else { return cached?.titles ?? [] }
            titlesInMemory = fresh
            loadedAt = Date()
            writeCache(fresh)
            return fresh
        }
    }

    /// Хвост каталога → уникальные тайтлы, свежие сверху.
    private static func build() async -> [PooledTitle] {
        let lastPage = await discoverLastPage()
        let pages = Array(max(1, lastPage - poolPages + 1)...max(1, lastPage))

        var byPage: [Int: [RawTitle]] = [:]
        var cursor = 0
        // Шесть соединений — потолок: при большем параллелизме premier.one
        // роняет часть запросов на TLS-рукопожатии (замер 26.08.2026).
        // Страница, которая не пришла, просто не даёт тайтлов — пул от этого
        // не рушится.
        await withTaskGroup(of: (Int, [RawTitle]).self) { group in
            func addNext() {
                guard cursor < pages.count else { return }
                let page = pages[cursor]
                cursor += 1
                group.addTask { (page, await fetchPage(page)?.results ?? []) }
            }
            for _ in 0..<min(maxParallel, pages.count) { addNext() }
            for await (page, items) in group {
                byPage[page] = items
                addNext()
            }
        }

        // Каталог отсортирован по возрастанию id, поэтому свежее — в конце:
        // страницы разворачиваются, порядок внутри страницы сохраняется.
        var seen = Set<String>()
        var result: [PooledTitle] = []
        for page in pages.reversed() {
            for raw in byPage[page] ?? [] {
                guard let mapped = map(raw) else { continue }
                // Один и тот же тайтл встречается в каталоге дважды (разные
                // id под одинаковым названием и годом) — на витрине он должен
                // стоять один раз.
                let key = mapped.card.title.lowercased() + "|" + (mapped.year.map(String.init) ?? "")
                guard seen.insert(key).inserted else { continue }
                result.append(mapped)
            }
        }
        return result
    }

    /// Номер последней страницы каталога. `count` API не отдаёт — только
    /// `has_next`, поэтому хвост ищется шагом в страницу от запомненного
    /// значения и сохраняется на следующий запуск.
    private static func discoverLastPage() async -> Int {
        let defaults = UserDefaults.standard
        let stored = defaults.object(forKey: lastPageKey) as? Int
        var page = max(1, stored ?? seedLastPage)
        var budget = tailProbeBudget

        guard var probe = await fetchPage(page) else { return page }
        budget -= 1

        if probe.results.isEmpty {
            // Ушли за край каталога — отступаем назад до живой страницы.
            while budget > 0, page > 1 {
                page -= 1
                budget -= 1
                guard let back = await fetchPage(page) else { break }
                if !back.results.isEmpty { break }
            }
        } else {
            // Каталог подрос — идём вперёд, пока API обещает продолжение.
            while budget > 0, probe.hasNext {
                guard let forward = await fetchPage(page + 1), !forward.results.isEmpty else { break }
                page += 1
                budget -= 1
                probe = forward
            }
        }

        defaults.set(page, forKey: lastPageKey)
        return page
    }

    private static func fetchPage(_ page: Int) async -> Page? {
        guard var components = URLComponents(string: host) else { return nil }
        components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                #if DEBUG
                print("[V4PremierCatalog] HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) стр. \(page)")
                #endif
                return nil
            }
            let decoded = try JSONDecoder().decode(PageResponse.self, from: data)
            return Page(results: decoded.results, hasNext: decoded.hasNext)
        } catch {
            #if DEBUG
            print("[V4PremierCatalog] стр. \(page) не загрузилась: \(error)")
            #endif
            return nil
        }
    }

    // MARK: Маппинг в карточку витрины

    private static func map(_ raw: RawTitle) -> PooledTitle? {
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        // Кроме кино каталог отдаёт `broadcast` — прямые эфиры телеканала.
        // Их нельзя поставить на паузу вдвоём, поэтому на витрину они не идут.
        guard let type = raw.type?.name, ["movie", "series", "show"].contains(type) else { return nil }
        guard let watch = watchURL(raw) else { return nil }

        let year = raw.year.flatMap(Int.init) ?? raw.yearStart.flatMap(Int.init)
        let isSeries = raw.type?.serialContent ?? (type != "movie")
        let kindLabel: String
        switch type {
        case "movie": kindLabel = "Фильм"
        case "show":  kindLabel = "Шоу"
        default:      kindLabel = "Сериал"
        }

        // У свежих тайтлов рейтинга ещё нет — приходит ноль. Ноль на карточке
        // читается как «оценили и поставили 0», поэтому звезда просто исчезает.
        var ratingText: String?
        if let kp = raw.rating?.kinopoisk, kp >= 1 {
            ratingText = String(format: "%.1f", kp).replacingOccurrences(of: ".", with: ",")
        } else if let own = raw.rating?.rating, own >= 1 {
            ratingText = String(format: "%.1f", own).replacingOccurrences(of: ".", with: ",")
        }

        var meta: [String] = ["PREMIER"]
        if let year { meta.append(String(year)) }
        meta.append(kindLabel)
        if let ratingText { meta.append("★ \(ratingText)") }

        // `poster_url` в каталоге пуст у всех тайтлов хвоста — постер живёт
        // в `pictures`. Широкий кадр берётся из фонового изображения тайтла:
        // это чистый кадр без вшитого названия, как BackgroundImage у Иви.
        let pictures = raw.pictures ?? [:]
        let poster = url(pictures["g_iconic_poster_1000x1500"]
            ?? pictures["g_iconic_poster_600x800"]
            ?? raw.posterURL)
        let hero = url(pictures["g_iconic_background_3840x2160"]
            ?? pictures["banner_landscape"]
            ?? pictures["g_iconic_poster_3840x2160"]
            ?? raw.picture)

        return PooledTitle(
            card: V4SearchResult(
                id: "premier-\(raw.id)",
                title: name,
                subtitle: meta.joined(separator: " · "),
                artworkURL: hero,
                posterURL: poster,
                duration: nil,
                isSelectable: true,
                origin: .cinema(.premier),
                watchURL: watch,
                year: year,
                kindLabel: kindLabel,
                ratingText: ratingText,
                isFreeOnService: false,
                isSeries: isSeries
            ),
            genreIDs: (raw.genres ?? []).map(\.id),
            typeName: type,
            year: year
        )
    }

    /// Страница тайтла на premier.one.
    ///
    /// `absolute_url` из каталога брать нельзя: у большинства карточек там
    /// служебный `/metainfo/tv/<id>/`, то есть адрес самого API, а не живая
    /// страница. Рабочий адрес собирается из slug, с которого снимается
    /// технический хвост `_tnt_premier_<hex>`: с ним premier.one отвечает 404,
    /// без него открывает тайтл — проверено на 20 карточках из 20 (26.08.2026).
    private static func watchURL(_ raw: RawTitle) -> String? {
        guard let slug = raw.slug, !slug.isEmpty else { return nil }
        let clean = slug.replacingOccurrences(
            of: "_tnt_premier_[0-9a-f]+$", with: "", options: [.regularExpression]
        )
        guard !clean.isEmpty else { return nil }
        return "https://premier.one/show/\(clean)"
    }

    private static func url(_ raw: String?) -> URL? {
        guard var raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") { raw = "https://" + raw.dropFirst("http://".count) }
        return URL(string: raw)
    }

    // MARK: Дисковый кэш

    private static func readCache() -> CachedPool? {
        guard let data = UserDefaults.standard.data(forKey: poolCacheKey),
              let cached = try? JSONDecoder().decode(CachedPool.self, from: data),
              !cached.titles.isEmpty else { return nil }
        return cached
    }

    private static func writeCache(_ titles: [PooledTitle]) {
        guard let data = try? JSONEncoder().encode(CachedPool(savedAt: Date(), titles: titles))
        else { return }
        UserDefaults.standard.set(data, forKey: poolCacheKey)
    }

    // MARK: DTO каталога

    private struct Page: Sendable {
        let results: [RawTitle]
        let hasNext: Bool
    }

    private struct PageResponse: Decodable {
        let results: [RawTitle]
        let hasNext: Bool

        private enum CodingKeys: String, CodingKey {
            case results
            case hasNext = "has_next"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Тот же приём, что и в каталоге Иви: один аномальный тайтл не
            // должен уносить страницу целиком.
            let lenient = try c.decodeIfPresent([SafeTitle].self, forKey: .results)
            results = (lenient ?? []).compactMap(\.value)
            hasNext = (try? c.decodeIfPresent(Bool.self, forKey: .hasNext)) ?? false
        }
    }

    private struct SafeTitle: Decodable, Sendable {
        let value: RawTitle?
        init(from decoder: Decoder) throws { value = try? RawTitle(from: decoder) }
    }

    private struct RawTitle: Decodable, Sendable {
        let id: Int
        let slug: String?
        let name: String?
        let year: String?
        let yearStart: String?
        let type: RawType?
        let genres: [RawGenre]?
        let rating: RawRating?
        let pictures: [String: String]?
        let posterURL: String?
        let picture: String?

        private enum CodingKeys: String, CodingKey {
            case id, slug, name, year, type, genres, rating, pictures, picture
            case yearStart = "year_start"
            case posterURL = "poster_url"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id обязателен — без него не собрать ни ключ карточки, ни лог.
            // Остальное каталог отдаёт без гарантий схемы, поэтому каждое поле
            // гасится через try?, а не роняет тайтл.
            id = try c.decode(Int.self, forKey: .id)
            slug = try? c.decodeIfPresent(String.self, forKey: .slug)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            // Год приходит строкой («2026»), а не числом.
            year = try? c.decodeIfPresent(String.self, forKey: .year)
            yearStart = try? c.decodeIfPresent(String.self, forKey: .yearStart)
            type = try? c.decodeIfPresent(RawType.self, forKey: .type)
            genres = try? c.decodeIfPresent([RawGenre].self, forKey: .genres)
            rating = try? c.decodeIfPresent(RawRating.self, forKey: .rating)
            pictures = try? c.decodeIfPresent([String: String].self, forKey: .pictures)
            posterURL = try? c.decodeIfPresent(String.self, forKey: .posterURL)
            picture = try? c.decodeIfPresent(String.self, forKey: .picture)
        }
    }

    private struct RawType: Decodable, Sendable {
        let name: String?
        let serialContent: Bool?

        private enum CodingKeys: String, CodingKey {
            case name
            case serialContent = "serial_content"
        }
    }

    private struct RawGenre: Decodable, Sendable {
        let id: Int
    }

    private struct RawRating: Decodable, Sendable {
        let rating: Double?
        let kinopoisk: Double?
    }
}

// MARK: - Тренды Netflix (22.08.2026)
//
// «Следить за трендами Netflix» — без ключей и без бэкенда: Netflix сам
// публикует официальный еженедельный Top 10 открытым TSV на
// top10.netflix.com (обновляется по вторникам, файл отсортирован свежими
// неделями сверху — проверено 22.08.2026). Клиент берёт последнюю неделю,
// а карточку каждого тайтла собирает тем же поиском, что и вся витрина
// (V4ClipSearch) — официальный русский трейлер с YouTube, который комната
// умеет играть.
// Итог кэшируется на сутки: чарт меняется раз в неделю, витрина обновляется
// сама, без релиза приложения и без вшитых названий.

enum V4TrendsCatalog {
    private static let tsvURL = URL(string: "https://top10.netflix.com/data/all-weeks-global.tsv")!
    private static let cacheKey = "plink.home.trends.v1"
    private static let cacheTTL: TimeInterval = 24 * 60 * 60
    /// Сколько трендовых карточек встаёт в голову «Для вас» и «Новинок».
    static let cardLimit = 6

    private struct CachedTrends: Codable {
        let savedAt: Date
        let items: [V4SearchResult]
    }

    struct TrendTitle: Sendable {
        let title: String
        let rank: Int
        let isSeries: Bool
    }

    /// Карточки трендов: суточный кэш → сеть → протухший кэш как запасной.
    /// Ошибок наружу нет — тренды украшают витрину, а не держат её.
    static func cards() async -> [V4SearchResult] {
        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.savedAt) < cacheTTL {
            return cached.items
        }
        let fresh = await buildCards()
        guard !fresh.isEmpty else { return cached?.items ?? [] }
        writeCache(fresh)
        return fresh
    }

    private static func buildCards() async -> [V4SearchResult] {
        let titles = await latestWeekTitles()
        guard !titles.isEmpty else { return [] }
        var slots = [V4SearchResult?](repeating: nil, count: titles.count)
        await withTaskGroup(of: (Int, V4SearchResult?).self) { group in
            for (index, trend) in titles.enumerated() {
                group.addTask { (index, await card(for: trend)) }
            }
            for await (index, card) in group { slots[index] = card }
        }
        return slots.compactMap { $0 }
    }

    /// Трейлер тайтла ищется по-русски: чарт глобальный, а витрина — наша.
    /// id карточки — чистый YouTube videoId: комната собирает MediaItem
    /// прямо из item.id (V4HomeViewLive.createRoomFromTrending).
    private static func card(for trend: TrendTitle) async -> V4SearchResult? {
        let page = await V4SearchStore.searchPage(
            "\(trend.title) трейлер на русском", limit: 3
        )
        guard let video = page.items.first else { return nil }
        return V4SearchResult(
            id: video.id,
            title: trend.title,
            subtitle: "Netflix · В трендах недели · №\(trend.rank)",
            artworkURL: video.artworkURL,
            posterURL: nil,
            duration: video.duration,
            isSelectable: true,
            origin: .youtube,
            watchURL: video.watchURL,
            year: nil,
            kindLabel: trend.isSeries ? "Сериал" : "Фильм",
            ratingText: nil,
            isFreeOnService: false,
            isSeries: trend.isSeries
        )
    }

    private static func latestWeekTitles() async -> [TrendTitle] {
        var request = URLRequest(url: tsvURL)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[V4TrendsCatalog] TSV Netflix не загрузился")
            #endif
            return []
        }
        return parse(tsv: text)
    }

    /// Последняя неделя чарта: фильмы и сериалы чередуются по рангу, языковые
    /// редакции («English»/«Non-English») сливаются в один ряд. Колонки
    /// ищутся по заголовку — состав TSV у Netflix уже менялся.
    static func parse(tsv: String) -> [TrendTitle] {
        var lines = tsv.split(separator: "\n", omittingEmptySubsequences: true)[...]
        guard let headerLine = lines.popFirst() else { return [] }
        let header = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let weekIdx = header.firstIndex(of: "week"),
              let categoryIdx = header.firstIndex(of: "category"),
              let rankIdx = header.firstIndex(of: "weekly_rank"),
              let titleIdx = header.firstIndex(of: "show_title") else { return [] }
        let needed = max(weekIdx, categoryIdx, rankIdx, titleIdx) + 1

        var films: [(rank: Int, title: String)] = []
        var shows: [(rank: Int, title: String)] = []
        var latestWeek = ""
        for line in lines {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= needed else { continue }
            let week = String(cols[weekIdx])
            // Свежие недели сверху: первая встреченная неделя — последняя
            // опубликованная, дальше файл можно не читать.
            if latestWeek.isEmpty { latestWeek = week }
            if week != latestWeek { break }
            let title = String(cols[titleIdx]).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, title != "N/A", let rank = Int(cols[rankIdx]) else { continue }
            if cols[categoryIdx].hasPrefix("Films") {
                films.append((rank, title))
            } else {
                shows.append((rank, title))
            }
        }
        films.sort { $0.rank < $1.rank }
        shows.sort { $0.rank < $1.rank }

        var result: [TrendTitle] = []
        var seen = Set<String>()
        for i in 0..<max(films.count, shows.count) where result.count < cardLimit {
            if i < films.count, seen.insert(films[i].title).inserted {
                result.append(TrendTitle(title: films[i].title, rank: films[i].rank, isSeries: false))
            }
            if result.count < cardLimit, i < shows.count, seen.insert(shows[i].title).inserted {
                result.append(TrendTitle(title: shows[i].title, rank: shows[i].rank, isSeries: true))
            }
        }
        return result
    }

    private static func readCache() -> CachedTrends? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedTrends.self, from: data),
              !cached.items.isEmpty else { return nil }
        return cached
    }

    private static func writeCache(_ items: [V4SearchResult]) {
        guard let data = try? JSONEncoder().encode(CachedTrends(savedAt: Date(), items: items))
        else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - Поиск роликов без ключей (26.08.2026)

// Ролики искал бэкенд через YouTube Data API. Ключ упирался в суточную квоту
// проекта — search.list стоит 100 единиц из 10 000, то есть сто поисков в
// сутки на всё приложение, — и к середине дня выдача умирала. RuTube с того же
// сервера отвечал 200 и пустым списком: у Railway не российский адрес.
//
// Оба упора снимаются одним решением: ролики ищет клиент, ровно так же, как
// уже ищет кино в Иви и PREMIER. Это не обход защиты — это те же публичные
// страницы, которые открывает браузер, и ключ им не нужен, как не нужен он
// человеку, набравшему запрос на youtube.com. Заодно поиск ходит из страны
// пользователя: RuTube отвечает ему нормально, потому что видит его адрес.
//
// Цена решения честная: разметка публичной выдачи не документирована и может
// поменяться. Поэтому парсер ничего не требует — не нашёл ролики, вернул
// пустой список, полку несёт второй источник и каталоги кинотеатров.
enum V4ClipSearch {
    /// Ролики под запрос: два видеохостинга параллельно, чередуются на ряду.
    /// Ошибки не всплывают — половина выдачи лучше экрана ошибки.
    static func search(_ query: String, limit: Int = 14) async -> [V4SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        async let youtube = V4YouTubeWebSearch.search(trimmed, limit: limit)
        async let rutube = V4RutubeSearch.search(trimmed, limit: limit)
        return interleave([await youtube, await rutube], limit: limit)
    }

    /// Круговой интерлив с дедупликацией по id — как у кинотеатров.
    private static func interleave(_ buckets: [[V4SearchResult]], limit: Int) -> [V4SearchResult] {
        var merged: [V4SearchResult] = []
        var seen = Set<String>()
        var row = 0
        while merged.count < limit {
            var advanced = false
            for bucket in buckets where row < bucket.count {
                advanced = true
                let item = bucket[row]
                guard seen.insert(item.id).inserted else { continue }
                merged.append(item)
                if merged.count >= limit { break }
            }
            if !advanced { break }
            row += 1
        }
        return merged
    }

    /// Запрос в том же виде, в каком его шлёт настольный браузер.
    /// Проверено 26.08.2026: оба хоста отвечают и без этих заголовков —
    /// это не пропуск, а страховка формы ответа. Парсер разбирает именно
    /// десктопную разметку, а незнакомому клиенту YouTube вправе отдать
    /// другую страницу; Accept-Language держит выдачу русской.
    static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                + "(KHTML, like Gecko) Chrome/126.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("ru-RU,ru;q=0.9", forHTTPHeaderField: "Accept-Language")
        return req
    }
}

// MARK: Поиск YouTube по публичной странице

/// Та же выдача, что видит человек на youtube.com/results. Ключ не нужен,
/// квоты нет: страница публичная, отдаётся без входа.
enum V4YouTubeWebSearch {
    /// `sp=EgIQAQ%3D%3D` — фильтр «только видео»: без него в выдачу лезут
    /// каналы и плейлисты, из которых комнату не собрать.
    private static let videosOnly = "EgIQAQ%3D%3D"

    static func search(_ query: String, limit: Int) async -> [V4SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)&sp=\(videosOnly)")
        else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(for: V4ClipSearch.request(url))
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let html = String(data: data, encoding: .utf8),
                  let root = initialData(in: html) else {
                #if DEBUG
                print("[V4YouTubeWebSearch] «\(query)»: страница без ytInitialData")
                #endif
                return []
            }
            return renderers(in: root).prefix(limit).compactMap(card(from:))
        } catch is CancellationError {
            return []
        } catch {
            #if DEBUG
            print("[V4YouTubeWebSearch] «\(query)» не загрузился: \(error)")
            #endif
            return []
        }
    }

    /// Выдача лежит в странице одним JSON-блоком `var ytInitialData = {…};`.
    /// Границы ищутся по тексту, а не регуляркой: блок больше мегабайта, и
    /// «ленивый» поиск подстроки по нему заметно дешевле.
    private static func initialData(in html: String) -> Any? {
        guard let start = html.range(of: "var ytInitialData = ") else { return nil }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: ";</script>") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(rest[..<end.lowerBound].utf8))
    }

    /// Ролики разбросаны по дереву разделов выдачи, поэтому оно обходится
    /// целиком: путь до videoRenderer YouTube меняет от релиза к релизу,
    /// а сам ключ держится годами.
    private static func renderers(in root: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let renderer = dict["videoRenderer"] as? [String: Any] { found.append(renderer) }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(root)
        return found
    }

    private static func card(from renderer: [String: Any]) -> V4SearchResult? {
        guard let videoId = renderer["videoId"] as? String, !videoId.isEmpty,
              let title = runs(renderer["title"]), !title.isEmpty,
              // Нет длительности — это эфир или премьера. Синхронно смотреть
              // такое нельзя: у участников разные точки входа в поток.
              let duration = (renderer["lengthText"] as? [String: Any])?["simpleText"] as? String
        else { return nil }
        let thumbnails = (renderer["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        return V4SearchResult(
            id: videoId,
            title: title,
            subtitle: runs(renderer["ownerText"]) ?? runs(renderer["longBylineText"]) ?? "YouTube",
            artworkURL: (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:)),
            posterURL: nil,
            duration: duration,
            isSelectable: true,
            origin: .youtube,
            watchURL: "https://www.youtube.com/watch?v=\(videoId)",
            year: nil,
            kindLabel: nil,
            ratingText: nil,
            isFreeOnService: false,
            isSeries: false
        )
    }

    /// Текст YouTube отдаёт кусками: `{"runs":[{"text":"…"}]}` либо
    /// `{"simpleText":"…"}`. Встречаются оба варианта в одной странице.
    private static func runs(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        guard let runs = dict["runs"] as? [[String: Any]] else { return nil }
        let text = runs.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }
}

// MARK: Поиск RuTube

/// Публичный поиск RuTube. Ключа не требует; с сервера в Европе отвечает
/// пустым списком, с устройства пользователя — нормальной выдачей.
enum V4RutubeSearch {
    private struct Page: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let title: String
        let duration: Int?
        let videoURL: String?
        let thumbnailURL: String?
        let isAdult: Bool?
        let isLivestream: Bool?
        let author: Author?

        struct Author: Decodable { let name: String? }

        private enum CodingKeys: String, CodingKey {
            case id, title, duration, author
            case videoURL = "video_url"
            case thumbnailURL = "thumbnail_url"
            case isAdult = "is_adult"
            case isLivestream = "is_livestream"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id и название обязательны: без них карточка не собирается.
            id = try c.decode(String.self, forKey: .id)
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
            videoURL = try? c.decodeIfPresent(String.self, forKey: .videoURL)
            thumbnailURL = try? c.decodeIfPresent(String.self, forKey: .thumbnailURL)
            isAdult = try? c.decodeIfPresent(Bool.self, forKey: .isAdult)
            isLivestream = try? c.decodeIfPresent(Bool.self, forKey: .isLivestream)
            author = try? c.decodeIfPresent(Author.self, forKey: .author)
        }
    }

    static func search(_ query: String, limit: Int) async -> [V4SearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://rutube.ru/api/search/video/?query=\(encoded)&limit=\(limit)")
        else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(for: V4ClipSearch.request(url))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let page = try JSONDecoder().decode(Page.self, from: data)
            return page.results.compactMap(card(from:))
        } catch is CancellationError {
            return []
        } catch {
            #if DEBUG
            print("[V4RutubeSearch] «\(query)» не загрузился: \(error)")
            #endif
            return []
        }
    }

    private static func card(from item: Item) -> V4SearchResult? {
        // Взрослое — мимо витрины: комнату видят все участники.
        // Эфир — мимо по той же причине, что и у YouTube: он не синхронизируется.
        guard !item.title.isEmpty, item.isAdult != true, item.isLivestream != true else { return nil }
        let link = item.videoURL ?? "https://rutube.ru/video/\(item.id)/"
        return V4SearchResult(
            id: "rutube-\(item.id)",
            title: item.title,
            subtitle: item.author?.name ?? "RuTube",
            artworkURL: item.thumbnailURL.flatMap(URL.init(string:)),
            posterURL: nil,
            duration: item.duration.flatMap(clock(_:)),
            isSelectable: true,
            origin: .video(.rutube),
            watchURL: link,
            year: nil,
            kindLabel: nil,
            ratingText: nil,
            isFreeOnService: false,
            isSeries: false
        )
    }

    /// Секунды → «1:23:45» / «7:12», как подписаны ролики YouTube.
    private static func clock(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
