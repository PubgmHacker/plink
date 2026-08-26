
// Plink/V5/PlinkAdminRoot.swift — админ-панель поверх /api/admin.
//
// Панель открывается из профиля («Администрирование» → «Админ-панель») и
// видна только ролям ADMIN/FOUNDER. Раньше весь экран был на английском
// внутри русского приложения, а половина запросов не сходилась с сервером:
// поиск слал ?query вместо ?search, флаги декодировались полем enabled,
// которого в таблице нет, метрики Plink+ читались под чужими именами,
// «Разобрать»/«Отклонить» обе дёргали удаление сообщения по id ЖАЛОБЫ.
// Здесь контракты сведены с backend/src/routes/admin.ts один в один.
import SwiftUI

// MARK: - Shared networking helper

final class AdminAPI {
    static let shared = AdminAPI()

    /// Своя сессия вместо URLSession.shared: у общей таймаут 60 с, и админ
    /// смотрел на бесконечный спиннер, когда сервис лежал.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private init() {}

    private var auth: String { AuthTokenStore.shared.token ?? "" }

    /// Ошибка с текстом сервера. Раньше любой 4xx/5xx превращался в
    /// URLError(.badServerResponse), и экран писал «Load failed» даже там,
    /// где сервер прямо отвечал «Reason is required».
    struct AdminError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private func request(_ path: String, method: String, body: [String: Any]?) -> URLRequest {
        var req = URLRequest(url: URL(string: PlinkConfig.apiURLString + path)!)
        req.httpMethod = method
        req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func check(_ data: Data, _ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, http.statusCode >= 400 else { return }
        let server = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw AdminError(status: http.statusCode, message: server ?? "Сервер ответил \(http.statusCode)")
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, resp) = try await session.data(for: request(path, method: "GET", body: nil))
        try check(data, resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let (data, resp) = try await session.data(for: request(path, method: "POST", body: body))
        try check(data, resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// POST без разбора тела — для действий, где важен только факт успеха
    /// (бан, смена роли, закрытие комнаты, удаление сообщения, обслуживание).
    @discardableResult
    func postIgnoringResponse(_ path: String, body: [String: Any]) async throws -> Bool {
        let (data, resp) = try await session.data(for: request(path, method: "POST", body: body))
        try check(data, resp)
        return true
    }
}

// MARK: - DTO под реальные ответы /api/admin

/// `select` в /admin/users отдаёт ровно эти поля. Флага `banned` там нет —
/// бан виден по `bannedUntil`, поэтому плашка «БАН» раньше не появлялась
/// никогда.
struct AdminUser: Identifiable, Decodable {
    let id: String
    let username: String
    let email: String
    let role: String
    let isPremium: Bool?
    let isOnline: Bool?
    let bannedUntil: String?
    let createdAt: String?

    var isBanned: Bool { (bannedUntil ?? "").isEmpty == false }
    var isStaff: Bool { ["ADMIN", "FOUNDER", "MODERATOR"].contains(role.uppercased()) }

    var roleTitle: String {
        switch role.uppercased() {
        case "FOUNDER": return "Основатель"
        case "ADMIN": return "Админ"
        case "MODERATOR": return "Модератор"
        default: return "Пользователь"
        }
    }
}
struct AdminUsersResp: Decodable { let users: [AdminUser]; let count: Int? }

/// /admin/rooms отдаёт сырые строки Room плюс `_count.participants`.
/// Плоского `participantCount` в ответе нет.
struct AdminRoom: Identifiable, Decodable {
    struct Counts: Decodable { let participants: Int? }
    let id: String
    let name: String
    let hostName: String?
    let code: String?
    let privacy: String?
    let isActive: Bool?
    let hidden: Bool?
    let createdAt: String?
    let counts: Counts?

    enum CodingKeys: String, CodingKey {
        case id, name, hostName, code, privacy, isActive, hidden, createdAt
        case counts = "_count"
    }

    var participants: Int? { counts?.participants }
    var privacyTitle: String { (privacy ?? "public") == "private" ? "Закрытая" : "Открытая" }
}
struct AdminRoomsResp: Decodable { let rooms: [AdminRoom]; let count: Int? }

/// Очередь модерации — это строки Report со связанным `reporter.username`.
/// Поля `targetPreview` сервер не отдаёт, поэтому карточка жалобы всегда
/// показывала «(no preview)».
struct AdminReportItem: Identifiable, Decodable {
    struct Reporter: Decodable { let username: String? }
    let id: String
    let reason: String
    let comment: String?
    let targetType: String?
    let targetID: String?
    let status: String?
    let createdAt: String?
    let dueAt: String?
    let reporter: Reporter?

    var targetTitle: String {
        switch (targetType ?? "room") {
        case "message": return "Сообщение"
        case "user": return "Пользователь"
        default: return "Комната"
        }
    }
    /// Удалить можно только сообщение и только по id САМОГО сообщения.
    var deletableMessageID: String? {
        guard targetType == "message", let t = targetID, !t.isEmpty else { return nil }
        return t
    }
}
struct AdminReportsResp: Decodable { let reports: [AdminReportItem]?; let count: Int? }

/// Таблица FeatureFlag: ключ + строковое значение. Поля `enabled: Bool` в ней
/// нет — на нём декодер падал целиком, и раздел всегда писал ошибку загрузки.
struct AdminFlagItem: Identifiable, Decodable {
    let key: String
    let value: String
    let updatedAt: String?
    let updatedBy: String?

    var id: String { key }
    var isOn: Bool { ["true", "1", "on", "enabled"].contains(value.lowercased()) }
}
struct AdminFlagsResp: Decodable { let flags: [AdminFlagItem]? }

struct AdminAuditItem: Identifiable, Decodable {
    let id: String
    let userId: String?
    let action: String
    let ip: String?
    let createdAt: String?
    let metadata: AnyCodable?
}
struct AdminAuditResp: Decodable { let logs: [AdminAuditItem]?; let count: Int? }

/// p50/p95 дрейфа сервер отдаёт жёстким нулём — карточки «0 мс» выглядели
/// измерением, которого нет, поэтому их здесь не читаем.
struct AdminAnalyticsResp: Decodable {
    let totalUsers: Int?
    let dau: Int?
    let mau: Int?
    let activeRooms: Int?
    let messages24h: Int?
}

/// /admin/system/health отвечает статусом процесса. Массива `services`
/// в ответе нет — заголовок «Services» рисовался над пустотой.
struct AdminHealthResp: Decodable {
    let status: String?
    let version: String?
    let uptime: Double?
    let nodeEnv: String?
    let timestamp: String?
}

/// Рассылки хранятся как записи аудита с action = admin.broadcast.send,
/// текст лежит в metadata.title/body.
struct AdminBroadcastItem: Identifiable, Decodable {
    let id: String
    let action: String
    let createdAt: String?
    let metadata: AnyCodable?

    private var dict: [String: Any] { (metadata?.value as? [String: Any]) ?? [:] }
    var title: String? { dict["title"] as? String }
    var text: String? { dict["body"] as? String }
}
struct AdminBroadcastsResp: Decodable { let broadcasts: [AdminBroadcastItem]?; let count: Int? }

/// Метрики Plink+ приходят как activePremium/lifetime/transactions30d.
/// Старые имена (activeSubs/trialCount/churnedToday) молча давали «--».
struct AdminPremiumResp: Decodable {
    let activePremium: Int?
    let lifetime: Int?
    let transactions30d: Int?
}

// AnyCodable shim
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues(\.value) }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let b as Bool: try c.encode(b)
        default: try c.encodeNil()
        }
    }
}

// MARK: - Форматирование

enum AdminFormat {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let out: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    static func date(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let parsed = iso.date(from: raw) ?? isoPlain.date(from: raw)
        guard let parsed else { return raw }
        return out.string(from: parsed)
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let total = Int(seconds)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d) д \(h) ч" }
        if h > 0 { return "\(h) ч \(m) мин" }
        return "\(m) мин"
    }
}

// MARK: - Module enum

// Раздела «Флаги» здесь нет намеренно: ручка /admin/flags отдаёт те же
// pending-жалобы, что и /admin/moderation/queue, а настоящие фиче-флаги
// живут в /admin/system/flags — они показаны в разделе «Система».

internal enum AdminModule: String, CaseIterable, Identifiable {
    case overview, users, rooms, moderation, analytics, system, audit, broadcasts, premium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Сводка"
        case .users: return "Пользователи"
        case .rooms: return "Комнаты"
        case .moderation: return "Жалобы"
        case .analytics: return "Аналитика"
        case .system: return "Система"
        case .audit: return "Журнал"
        case .broadcasts: return "Рассылки"
        case .premium: return "Plink+"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "rectangle.3.group"
        case .users: return "person.2"
        case .rooms: return "tv"
        case .moderation: return "shield.lefthalf.filled"
        case .analytics: return "chart.bar"
        case .system: return "gearshape"
        case .audit: return "doc.text.magnifyingglass"
        case .broadcasts: return "megaphone.fill"
        case .premium: return "crown.fill"
        }
    }
}

// MARK: - Root

internal struct AdminRootView: View {
    @State private var module: AdminModule = .overview

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(AdminModule.allCases) { mod in
                    Button { module = mod } label: {
                        HStack {
                            Image(systemName: mod.icon)
                                .foregroundStyle(module == mod ? V4.accent : V4.muted)
                                .frame(width: 20)
                            Text(mod.title)
                                .foregroundStyle(module == mod ? V4.ink : V4.muted)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(module == mod ? V4.accent.opacity(0.15) : Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red:0.06,green:0.07,blue:0.10))
            .navigationTitle("Админ")
        } detail: {
            ZStack {
                Color(red:0.05,green:0.06,blue:0.09).ignoresSafeArea()
                moduleContent
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch module {
        case .overview: AdminOverviewView()
        case .users: AdminUsersView()
        case .rooms: AdminRoomsView()
        case .moderation: AdminModerationView()
        case .analytics: AdminAnalyticsView()
        case .system: AdminSystemView()
        case .audit: AdminAuditView()
        case .broadcasts: AdminBroadcastsView()
        case .premium: AdminPremiumView()
        }
    }
}

// MARK: - Общая оболочка раздела

struct AdminShell<Content: View>: View {
    let title: String
    var isLoading: Bool = false
    var errorMsg: String? = nil
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.title2.bold()).foregroundStyle(V4.ink)
                    Spacer()
                    if let refresh = onRefresh {
                        Button { Task { await refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(V4.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Обновить")
                    }
                    if isLoading { ProgressView().tint(.white).scaleEffect(0.7) }
                }
                if let err = errorMsg {
                    Text(err).font(.caption).foregroundStyle(.red.opacity(0.85))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                content
            }
            .padding(20)
        }
    }
}

/// Плитка показателя.
struct StatCard: View {
    let label: String; let value: String; var accent: Color = V4.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .heavy)).foregroundStyle(V4.ink)
            Text(label).font(.caption).foregroundStyle(V4.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.2)))
    }
}

/// Пустое состояние раздела — одна строка вместо самодельных заглушек.
struct AdminEmptyLine: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(V4.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }
}

// MARK: - 1. Сводка

struct AdminOverviewView: View {
    @State private var health: AdminHealthResp? = nil
    @State private var analytics: AdminAnalyticsResp? = nil
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Сводка", isLoading: loading, errorMsg: err, onRefresh: load) {
            if let a = analytics {
                LazyVGrid(columns: [.init(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    StatCard(label: "Сегодня в сети", value: a.dau.map(String.init) ?? "—")
                    StatCard(label: "За 30 дней", value: a.mau.map(String.init) ?? "—")
                    StatCard(label: "Всего аккаунтов", value: a.totalUsers.map(String.init) ?? "—")
                    StatCard(label: "Комнат в эфире", value: a.activeRooms.map(String.init) ?? "—", accent: .green)
                    StatCard(label: "Сообщений за сутки", value: a.messages24h.map(String.init) ?? "—", accent: .yellow)
                }
            }
            if let h = health {
                Text("Сервер").font(.headline).foregroundStyle(V4.ink).padding(.top, 8)
                VStack(spacing: 0) {
                    AdminKeyValueRow(key: "Состояние",
                                     value: (h.status ?? "—").uppercased(),
                                     tint: h.status == "ok" ? .green : .red)
                    AdminKeyValueRow(key: "Версия", value: h.version ?? "—")
                    AdminKeyValueRow(key: "Аптайм", value: AdminFormat.uptime(h.uptime))
                    AdminKeyValueRow(key: "Окружение", value: h.nodeEnv ?? "—")
                }
                .plinkGlass(.control, cornerRadius: 10)
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; err = nil
        async let h: AdminHealthResp? = try? AdminAPI.shared.get("/admin/system/health")
        async let a: AdminAnalyticsResp? = try? AdminAPI.shared.get("/admin/analytics/overview")
        let (hr, ar) = await (h, a)
        health = hr; analytics = ar
        if hr == nil && ar == nil { err = "Не удалось загрузить сводку" }
        loading = false
    }
}

/// Строка «ключ — значение» для системных блоков.
struct AdminKeyValueRow: View {
    let key: String
    let value: String
    var tint: Color = V4.ink
    var body: some View {
        HStack {
            Text(key).font(.subheadline).foregroundStyle(V4.muted)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 2. Пользователи

struct AdminUsersView: View {
    /// Что именно подтверждаем. Сервер требует причину (минимум 3 символа)
    /// и для бана, и для разбана — раньше клиент подставлял «admin action»
    /// молча, и в журнале оседала бессмысленная строка.
    private enum PendingAction: Identifiable {
        case ban(AdminUser)
        case unban(AdminUser)
        case role(AdminUser)

        var id: String {
            switch self {
            case .ban(let u): return "ban-" + u.id
            case .unban(let u): return "unban-" + u.id
            case .role(let u): return "role-" + u.id
            }
        }
        var user: AdminUser {
            switch self { case .ban(let u), .unban(let u), .role(let u): return u }
        }
    }

    @State private var query = ""
    @State private var users: [AdminUser] = []
    @State private var loading = false
    @State private var err: String? = nil
    @State private var pending: PendingAction? = nil
    @State private var reason = ""
    @State private var banHours = 0            // 0 = навсегда
    @State private var newRole = "MODERATOR"

    var body: some View {
        AdminShell(title: "Пользователи", isLoading: loading, errorMsg: err, onRefresh: { await search() }) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(V4.muted)
                TextField("Ник или почта", text: $query)
                    .foregroundStyle(V4.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button { query = ""; Task { await search() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(V4.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Очистить поиск")
                }
            }
            .padding(10)
            .plinkGlass(.control, cornerRadius: 10)

            ForEach(users) { user in
                userRow(user)
            }
            if users.isEmpty && !loading {
                AdminEmptyLine(text: query.isEmpty ? "Пользователей нет" : "Никого не найдено")
            }
        }
        .sheet(item: $pending) { action in
            actionSheet(action)
                .presentationDetents([.height(320)])
                .presentationBackground(Color(red: 0.06, green: 0.07, blue: 0.10))
        }
        .task { await search() }
    }

    @ViewBuilder
    private func userRow(_ user: AdminUser) -> some View {
        HStack {
            Circle()
                .fill(LinearGradient(colors: [V4.accent, Color(red:0.28,green:1.0,blue:0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
                .overlay(Text(String(user.username.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(.black))
                .overlay(alignment: .bottomTrailing) {
                    if user.isOnline == true {
                        Circle().fill(.green).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(red:0.05,green:0.06,blue:0.09), lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(user.username).font(.subheadline.bold()).foregroundStyle(V4.ink)
                    if user.isPremium == true {
                        Image(systemName: "crown.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                    }
                }
                Text(user.email).font(.caption).foregroundStyle(V4.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(user.roleTitle).font(.caption2.bold())
                    .foregroundStyle(user.isStaff ? V4.accent : V4.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((user.isStaff ? V4.accent : Color.white).opacity(0.1), in: Capsule())
                if user.isBanned {
                    Text("БАН до \(AdminFormat.date(user.bannedUntil))")
                        .font(.caption2.bold()).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .plinkGlass(.control, cornerRadius: 10)
        .contextMenu {
            if user.isBanned {
                Button("Снять бан") { open(.unban(user)) }
            } else {
                Button("Забанить", role: .destructive) { open(.ban(user)) }
            }
            Button("Сменить роль") { open(.role(user)) }
        }
    }

    private func open(_ action: PendingAction) {
        reason = ""
        banHours = 0
        newRole = action.user.role.uppercased() == "MODERATOR" ? "ADMIN" : "MODERATOR"
        pending = action
    }

    @ViewBuilder
    private func actionSheet(_ action: PendingAction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sheetTitle(action)).font(.headline).foregroundStyle(V4.ink)

            if case .role = action {
                Picker("Роль", selection: $newRole) {
                    Text("Пользователь").tag("USER")
                    Text("Модератор").tag("MODERATOR")
                    Text("Админ").tag("ADMIN")
                }
                .pickerStyle(.segmented)
            } else {
                TextField("Причина (минимум 3 символа)", text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(10)
                    .plinkGlass(.control, cornerRadius: 10)
                    .foregroundStyle(V4.ink)
            }

            if case .ban = action {
                Picker("Срок", selection: $banHours) {
                    Text("Навсегда").tag(0)
                    Text("24 часа").tag(24)
                    Text("7 дней").tag(168)
                }
                .pickerStyle(.segmented)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Отмена") { pending = nil }
                    .buttonStyle(.bordered)
                Spacer()
                Button(confirmTitle(action), role: destructive(action) ? .destructive : nil) {
                    let captured = action
                    pending = nil
                    Task { await perform(captured) }
                }
                .buttonStyle(.borderedProminent)
                .tint(destructive(action) ? .red : V4.accent)
                .disabled(needsReason(action) && reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
            }
        }
        .padding(20)
    }

    private func sheetTitle(_ a: PendingAction) -> String {
        switch a {
        case .ban(let u): return "Забанить @\(u.username)"
        case .unban(let u): return "Снять бан с @\(u.username)"
        case .role(let u): return "Роль для @\(u.username)"
        }
    }
    private func confirmTitle(_ a: PendingAction) -> String {
        switch a {
        case .ban: return "Забанить"
        case .unban: return "Снять бан"
        case .role: return "Назначить"
        }
    }
    private func destructive(_ a: PendingAction) -> Bool { if case .ban = a { return true }; return false }
    private func needsReason(_ a: PendingAction) -> Bool { if case .role = a { return false }; return true }

    private func perform(_ action: PendingAction) async {
        err = nil
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch action {
            case .ban(let u):
                var body: [String: Any] = ["reason": text]
                if banHours > 0 { body["durationHours"] = banHours }
                try await AdminAPI.shared.postIgnoringResponse("/admin/users/\(u.id)/ban", body: body)
            case .unban(let u):
                try await AdminAPI.shared.postIgnoringResponse("/admin/users/\(u.id)/unban", body: ["reason": text])
            case .role(let u):
                // Сервер принимает только USER/MODERATOR/ADMIN/FOUNDER в верхнем
                // регистре: строчное "admin" отбивалось как 400 Invalid role.
                try await AdminAPI.shared.postIgnoringResponse("/admin/users/\(u.id)/role", body: ["role": newRole])
            }
        } catch {
            err = error.localizedDescription
        }
        await search()
    }

    private func search() async {
        loading = true; err = nil
        // Ручка читает ?search=, а не ?query= — поиск раньше просто не работал.
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = trimmed.isEmpty
            ? ""
            : "?search=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)"
        do {
            let resp: AdminUsersResp = try await AdminAPI.shared.get("/admin/users" + q)
            users = resp.users
        } catch {
            err = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 3. Комнаты

struct AdminRoomsView: View {
    @State private var rooms: [AdminRoom] = []
    @State private var loading = false
    @State private var err: String? = nil
    @State private var onlyActive = true

    private var visible: [AdminRoom] {
        onlyActive ? rooms.filter { $0.isActive == true } : rooms
    }

    var body: some View {
        AdminShell(title: "Комнаты", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            // Ручка отдаёт последние 50 комнат целиком, а не только живые:
            // заголовок «Live Rooms» врал, поэтому фильтр сделан явным.
            Picker("Показывать", selection: $onlyActive) {
                Text("Активные").tag(true)
                Text("Все").tag(false)
            }
            .pickerStyle(.segmented)

            ForEach(visible) { room in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(room.name).font(.subheadline.bold()).foregroundStyle(V4.ink)
                        Spacer()
                        if room.isActive == true {
                            Text("ЭФИР").font(.caption2.bold()).foregroundStyle(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                    }
                    HStack(spacing: 10) {
                        Label(room.hostName ?? "без хоста", systemImage: "person.fill")
                        Label("\(room.participants ?? 0)", systemImage: "person.2.fill")
                        Text(room.privacyTitle)
                        if let code = room.code { Text("код \(code)").monospaced() }
                    }
                    .font(.caption)
                    .foregroundStyle(V4.muted)

                    HStack {
                        Text(AdminFormat.date(room.createdAt)).font(.caption2).foregroundStyle(V4.muted)
                        Spacer()
                        if room.isActive == true {
                            Button("Закрыть комнату", role: .destructive) {
                                Task { await close(room) }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(12)
                .plinkGlass(.control, cornerRadius: 12)
            }
            if visible.isEmpty && !loading {
                AdminEmptyLine(text: onlyActive ? "Активных комнат нет" : "Комнат нет")
            }
        }
        .task { await load() }
    }

    private func close(_ room: AdminRoom) async {
        err = nil
        do {
            try await AdminAPI.shared.postIgnoringResponse("/admin/rooms/\(room.id)/close", body: [:])
        } catch {
            err = error.localizedDescription
        }
        await load()
    }

    private func load() async {
        loading = true; err = nil
        do {
            let resp: AdminRoomsResp = try await AdminAPI.shared.get("/admin/rooms")
            rooms = resp.rooms
        } catch {
            err = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 4. Жалобы

struct AdminModerationView: View {
    @State private var reports: [AdminReportItem] = []
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Жалобы", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(report.targetTitle).font(.caption2.bold())
                            .foregroundStyle(V4.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(V4.accent.opacity(0.12), in: Capsule())
                        Spacer()
                        Text(AdminFormat.date(report.createdAt))
                            .font(.caption2).foregroundStyle(V4.muted)
                    }

                    Text(report.reason).font(.subheadline.bold()).foregroundStyle(V4.ink)

                    if let comment = report.comment, !comment.isEmpty {
                        Text(comment).font(.caption).foregroundStyle(V4.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Label(report.reporter?.username ?? "аноним", systemImage: "flag")
                        if let due = report.dueAt {
                            Label("до \(AdminFormat.date(due))", systemImage: "clock")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(V4.muted)

                    HStack(spacing: 8) {
                        // Обе прежние кнопки — Resolve и Dismiss — били в одну и
                        // ту же ручку и делали ровно одно: status = resolved.
                        Button("Закрыть жалобу") { Task { await resolve(report) } }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)

                        if let messageID = report.deletableMessageID {
                            Button("Удалить сообщение", role: .destructive) {
                                Task { await deleteMessage(messageID, report: report) }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                }
                .padding(12)
                .plinkGlass(.control, cornerRadius: 12)
            }
            if reports.isEmpty && !loading {
                AdminEmptyLine(text: "Очередь пуста")
            }
        }
        .task { await load() }
    }

    private func resolve(_ report: AdminReportItem) async {
        err = nil
        do {
            try await AdminAPI.shared.postIgnoringResponse("/admin/flags/\(report.id)/resolve", body: [:])
        } catch {
            err = error.localizedDescription
        }
        await load()
    }

    private func deleteMessage(_ messageID: String, report: AdminReportItem) async {
        err = nil
        do {
            try await AdminAPI.shared.postIgnoringResponse("/admin/moderation/messages/\(messageID)/delete", body: [:])
            try await AdminAPI.shared.postIgnoringResponse("/admin/flags/\(report.id)/resolve", body: [:])
        } catch {
            err = error.localizedDescription
        }
        await load()
    }

    private func load() async {
        loading = true; err = nil
        do {
            let resp: AdminReportsResp = try await AdminAPI.shared.get("/admin/moderation/queue")
            reports = resp.reports ?? []
        } catch {
            err = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 5. Аналитика

struct AdminAnalyticsView: View {
    @State private var data: AdminAnalyticsResp? = nil
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Аналитика", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(label: "Всего", value: "\(data?.totalUsers ?? 0)")
                StatCard(label: "DAU", value: "\(data?.dau ?? 0)")
                StatCard(label: "MAU", value: "\(data?.mau ?? 0)")
                StatCard(label: "Комнат в эфире", value: "\(data?.activeRooms ?? 0)")
            }
            AdminKeyValueRow(key: "Сообщений за 24 часа", value: "\(data?.messages24h ?? 0)")
            Text("DAU считается по флагу «сейчас в сети», MAU — по активности за 30 дней.")
                .font(.caption2)
                .foregroundStyle(V4.muted)
                .padding(.top, 2)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; err = nil
        do { data = try await AdminAPI.shared.get("/admin/analytics/overview") }
        catch { err = error.localizedDescription }
        loading = false
    }
}

// MARK: - 6. Система

struct AdminSystemView: View {
    @State private var health: AdminHealthResp? = nil
    @State private var flags: [AdminFlagItem] = []
    @State private var loading = false
    @State private var err: String? = nil
    @State private var busy = false

    private var maintenanceOn: Bool {
        flags.first(where: { $0.key == "maintenance_mode" })?.isOn ?? false
    }

    var body: some View {
        AdminShell(title: "Система", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(label: "Статус", value: (health?.status ?? "—").uppercased())
                StatCard(label: "Версия", value: health?.version ?? "—")
                StatCard(label: "Аптайм", value: AdminFormat.uptime(health?.uptime))
                StatCard(label: "Среда", value: health?.nodeEnv ?? "—")
            }

            // Тумблер двусторонний: состояние читается из feature-флага
            // maintenance_mode, а не из локальной переменной, которая
            // сбрасывалась при каждом открытии раздела.
            Toggle(isOn: Binding(
                get: { maintenanceOn },
                set: { newValue in Task { await setMaintenance(newValue) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Режим обслуживания").font(.subheadline.bold()).foregroundStyle(V4.ink)
                    Text(maintenanceOn ? "Включён" : "Выключен").font(.caption).foregroundStyle(V4.muted)
                }
            }
            .tint(.orange)
            .disabled(busy)
            .padding(12)
            .plinkGlass(.control, cornerRadius: 12)

            if !flags.isEmpty {
                Text("Флаги").font(.caption.bold()).foregroundStyle(V4.muted)
                ForEach(flags) { flag in
                    HStack {
                        Text(flag.key).font(.caption.monospaced()).foregroundStyle(V4.ink)
                        Spacer()
                        Text(flag.value)
                            .font(.caption2.bold())
                            .foregroundStyle(flag.isOn ? .green : V4.muted)
                        Text(AdminFormat.date(flag.updatedAt))
                            .font(.caption2).foregroundStyle(V4.muted)
                    }
                    .padding(10)
                    .plinkGlass(.control, cornerRadius: 10)
                }
            }
        }
        .task { await load() }
    }

    private func setMaintenance(_ enabled: Bool) async {
        busy = true; err = nil
        do { try await AdminAPI.shared.postIgnoringResponse("/admin/system/maintenance", body: ["enabled": enabled]) }
        catch { err = error.localizedDescription }
        busy = false
        await load()
    }

    private func load() async {
        loading = true; err = nil
        do {
            health = try await AdminAPI.shared.get("/admin/system/health")
            let resp: AdminFlagsResp = try await AdminAPI.shared.get("/admin/system/flags")
            flags = resp.flags ?? []
        } catch {
            err = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 7. Журнал

struct AdminAuditView: View {
    @State private var logs: [AdminAuditItem] = []
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Журнал", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.action).font(.caption.bold().monospaced()).foregroundStyle(V4.accent)
                        Spacer()
                        Text(AdminFormat.date(log.createdAt)).font(.caption2).foregroundStyle(V4.muted)
                    }
                    if let summary = summary(log), !summary.isEmpty {
                        Text(summary).font(.caption2).foregroundStyle(V4.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if let uid = log.userId { Text("админ \(uid.prefix(8))") }
                        if let ip = log.ip { Text(ip) }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(V4.muted)
                }
                .padding(10)
                .plinkGlass(.control, cornerRadius: 10)
            }
            if logs.isEmpty && !loading { AdminEmptyLine(text: "Записей нет") }
        }
        .task { await load() }
    }

    private func summary(_ log: AdminAuditItem) -> String? {
        guard let dict = log.metadata?.value as? [String: Any] else { return nil }
        return dict.keys.sorted().compactMap { key -> String? in
            let raw = dict[key]
            if raw is NSNull { return nil }
            return "\(key): \(raw ?? "")"
        }.joined(separator: " · ")
    }

    private func load() async {
        loading = true; err = nil
        do {
            let resp: AdminAuditResp = try await AdminAPI.shared.get("/admin/audit")
            logs = resp.logs ?? []
        } catch { err = error.localizedDescription }
        loading = false
    }
}

// MARK: - 8. Рассылки

struct AdminBroadcastsView: View {
    @State private var title = ""
    @State private var text = ""
    @State private var history: [AdminBroadcastItem] = []
    @State private var loading = false
    @State private var sending = false
    @State private var err: String? = nil
    @State private var sentInfo: String? = nil

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !sending
    }

    var body: some View {
        AdminShell(title: "Рассылки", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            VStack(alignment: .leading, spacing: 10) {
                // Поля заголовка раньше не было вовсе, а сервер требует и
                // title, и body: отправка всегда возвращала 400.
                TextField("Заголовок", text: $title)
                    .padding(10)
                    .plinkGlass(.control, cornerRadius: 10)
                    .foregroundStyle(V4.ink)

                TextField("Текст уведомления", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(10)
                    .plinkGlass(.control, cornerRadius: 10)
                    .foregroundStyle(V4.ink)

                // Выбор аудитории убран: pushBroadcast рассылает на все
                // зарегистрированные токены, сегмента на сервере нет.
                Text("Пуш уйдёт на все устройства с включёнными уведомлениями.")
                    .font(.caption2).foregroundStyle(V4.muted)

                if let sentInfo {
                    Text(sentInfo).font(.caption.bold()).foregroundStyle(.green)
                }

                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        if sending { ProgressView().controlSize(.small) }
                        Text(sending ? "Отправка…" : "Отправить")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(V4.accent)
                .disabled(!canSend)
            }
            .padding(12)
            .plinkGlass(.control, cornerRadius: 12)

            Text("История").font(.caption.bold()).foregroundStyle(V4.muted)
            ForEach(history) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? "Без заголовка").font(.subheadline.bold()).foregroundStyle(V4.ink)
                    if let body = item.text {
                        Text(body).font(.caption).foregroundStyle(V4.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(AdminFormat.date(item.createdAt)).font(.caption2).foregroundStyle(V4.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .plinkGlass(.control, cornerRadius: 10)
            }
            if history.isEmpty && !loading { AdminEmptyLine(text: "Рассылок ещё не было") }
        }
        .task { await load() }
    }

    private func send() async {
        sending = true; err = nil; sentInfo = nil
        do {
            struct Resp: Decodable { let pushed: Int? }
            let resp: Resp = try await AdminAPI.shared.post(
                "/admin/broadcasts/send",
                body: ["title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                       "body": text.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
            sentInfo = "Отправлено на \(resp.pushed ?? 0) устройств"
            title = ""; text = ""
        } catch {
            err = error.localizedDescription
        }
        sending = false
        await load()
    }

    private func load() async {
        loading = true; err = nil
        do {
            let resp: AdminBroadcastsResp = try await AdminAPI.shared.get("/admin/broadcasts/history")
            history = resp.broadcasts ?? []
        } catch { err = error.localizedDescription }
        loading = false
    }
}

// MARK: - 9. Plink+

struct AdminPremiumView: View {
    @State private var data: AdminPremiumResp? = nil
    @State private var loading = false
    @State private var err: String? = nil
    @State private var userID = ""
    @State private var days = 30
    @State private var granting = false
    @State private var grantInfo: String? = nil

    var body: some View {
        AdminShell(title: "Plink+", isLoading: loading, errorMsg: err, onRefresh: { await load() }) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCard(label: "Активных подписок", value: "\(data?.activePremium ?? 0)")
                StatCard(label: "Пожизненных", value: "\(data?.lifetime ?? 0)")
            }
            AdminKeyValueRow(key: "Транзакций за 30 дней", value: "\(data?.transactions30d ?? 0)")

            VStack(alignment: .leading, spacing: 10) {
                Text("Выдать подписку").font(.subheadline.bold()).foregroundStyle(V4.ink)

                TextField("ID пользователя", text: $userID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .plinkGlass(.control, cornerRadius: 10)
                    .foregroundStyle(V4.ink)

                Picker("Срок", selection: $days) {
                    Text("7 дней").tag(7)
                    Text("30 дней").tag(30)
                    Text("365 дней").tag(365)
                }
                .pickerStyle(.segmented)

                if let grantInfo {
                    Text(grantInfo).font(.caption.bold()).foregroundStyle(.green)
                }

                Button {
                    Task { await grant() }
                } label: {
                    HStack {
                        if granting { ProgressView().controlSize(.small) }
                        Text(granting ? "Выдача…" : "Выдать")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(V4.accent)
                .disabled(userID.trimmingCharacters(in: .whitespaces).isEmpty || granting)
            }
            .padding(12)
            .plinkGlass(.control, cornerRadius: 12)
        }
        .task { await load() }
    }

    private func grant() async {
        granting = true; err = nil; grantInfo = nil
        do {
            try await AdminAPI.shared.postIgnoringResponse(
                "/admin/premium/comp",
                body: ["userId": userID.trimmingCharacters(in: .whitespaces), "days": days]
            )
            grantInfo = "Подписка выдана на \(days) дн."
            userID = ""
        } catch {
            err = error.localizedDescription
        }
        granting = false
        await load()
    }

    private func load() async {
        loading = true; err = nil
        do { data = try await AdminAPI.shared.get("/admin/premium/metrics") }
        catch { err = error.localizedDescription }
        loading = false
    }
}
