// Plink/V4/V4CinemaCatalog.swift
// 22.08.2026: «кинотеатры в приоритете».
//
// Витрина Главной наполнялась только YouTube-поиском через бэкенд-прокси —
// на полках стояли трейлеры и «фильм полностью» с чужих каналов. Люди же
// ждут кино из онлайн-кинотеатров. Роут бэкенда менять нельзя (деплой не в
// наших руках), поэтому кинотеатральный каталог собирается клиентом.
//
// Источник данных — публичный каталог Иви (api.ivi.ru/mobileapi): единственный
// из российских кинотеатров, который отдаёт афишу без ключа и токена. Каждая
// карточка ведёт на страницу просмотра ivi.ru — комната открывает её в
// WebView, хост входит в свой аккаунт. Кинопоиск/Okko/Wink/PREMIER открытого
// каталога не дают, поэтому они подключены «мостиком»: из превью тайтла можно
// создать комнату сразу на странице поиска этого кинотеатра (V4WatchTarget).
// Plink не предоставляет контент и не обходит защиту — только открывает
// официальные страницы.

import Foundation

// MARK: - Происхождение карточки витрины

/// Откуда карточка на витрине: YouTube-поиск или каталог кинотеатра.
/// От происхождения зависят бейдж превью, подпись героя и то, какой
/// MediaItem соберёт комната. Codable — ради дискового кэша полок.
enum V4ContentOrigin: Hashable, Sendable, Codable {
    case youtube
    case cinema(VideoService)
}

/// Что именно смотреть из превью тайтла: сам элемент («Смотреть вместе»)
/// или тот же тайтл в другом кинотеатре (ряд «Где ещё смотреть»).
enum V4WatchTarget: Hashable, Sendable {
    case native
    case cinema(VideoService, String)
}

// MARK: - Каталог кинотеатра

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

    /// Собирает кинотеатральную часть полки. Ошибки сети не бросаются:
    /// пустой результат — сигнал добрать полку YouTube-хвостом.
    static func fetchShelf(_ chip: String) async -> [V4SearchResult] {
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

// MARK: - Тренды Netflix (22.08.2026)
//
// «Следить за трендами Netflix» — без ключей и без бэкенда: Netflix сам
// публикует официальный еженедельный Top 10 открытым TSV на
// top10.netflix.com (обновляется по вторникам, файл отсортирован свежими
// неделями сверху — проверено 22.08.2026). Клиент берёт последнюю неделю,
// а карточку каждого тайтла собирает через существующий /api/media/search —
// официальный русский трейлер с YouTube, который комната умеет играть.
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
    static func cards(apiBase: String, token: String?) async -> [V4SearchResult] {
        let cached = readCache()
        if let cached, Date().timeIntervalSince(cached.savedAt) < cacheTTL {
            return cached.items
        }
        let fresh = await buildCards(apiBase: apiBase, token: token)
        guard !fresh.isEmpty else { return cached?.items ?? [] }
        writeCache(fresh)
        return fresh
    }

    private static func buildCards(apiBase: String, token: String?) async -> [V4SearchResult] {
        let titles = await latestWeekTitles()
        guard !titles.isEmpty else { return [] }
        var slots = [V4SearchResult?](repeating: nil, count: titles.count)
        await withTaskGroup(of: (Int, V4SearchResult?).self) { group in
            for (index, trend) in titles.enumerated() {
                group.addTask { (index, await card(for: trend, apiBase: apiBase, token: token)) }
            }
            for await (index, card) in group { slots[index] = card }
        }
        return slots.compactMap { $0 }
    }

    /// Трейлер тайтла ищется по-русски: чарт глобальный, а витрина — наша.
    /// id карточки — чистый YouTube videoId: комната собирает MediaItem
    /// прямо из item.id (V4HomeViewLive.createRoomFromTrending).
    private static func card(
        for trend: TrendTitle, apiBase: String, token: String?
    ) async -> V4SearchResult? {
        let page = await V4SearchStore.searchPage(
            "\(trend.title) трейлер на русском", apiBase: apiBase, token: token, limit: 3
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
