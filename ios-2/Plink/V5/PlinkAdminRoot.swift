
// Plink/V5/PlinkAdminRoot.swift -- Full Admin Panel with real API calls
import SwiftUI

// MARK: - Shared networking helper

final class AdminAPI {
    static let shared = AdminAPI()
    private init() {}

    private var auth: String { KeychainHelper.read(for: "rave_auth_token") ?? "" }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: PlinkConfig.apiURLString + path)!
        var req = URLRequest(url: url)
        req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = URL(string: PlinkConfig.apiURLString + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + auth, forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - DTOs

struct AdminUser: Identifiable, Decodable {
    let id: String
    let username: String
    let email: String
    let role: String
    let banned: Bool?
    let createdAt: String?
}
struct AdminUsersResp: Decodable { let users: [AdminUser]; let total: Int? }

struct AdminRoom: Identifiable, Decodable {
    let id: String
    let name: String
    let hostName: String?
    let privacy: String?
    let participantCount: Int?
}
struct AdminRoomsResp: Decodable { let rooms: [AdminRoom]; let total: Int? }

struct AdminReportItem: Identifiable, Decodable {
    let id: String
    let reason: String?
    let targetPreview: String?
    let createdAt: String?
}
struct AdminReportsResp: Decodable { let reports: [AdminReportItem]? }

struct AdminFlagItem: Identifiable, Decodable {
    let id: String
    let key: String
    let enabled: Bool
    let owner: String?
}
struct AdminFlagsResp: Decodable { let flags: [AdminFlagItem]? }

struct AdminAuditItem: Identifiable, Decodable {
    let id: String
    let userId: String?
    let action: String
    let createdAt: String?
    let metadata: AnyCodable?
}
struct AdminAuditResp: Decodable { let logs: [AdminAuditItem]? }

struct AdminAnalyticsResp: Decodable {
    let dau: Int?; let mau: Int?; let totalUsers: Int?; let activeRooms: Int?
    let p50SyncDrift: Double?; let p95SyncDrift: Double?
}

struct AdminHealthResp: Decodable {
    let status: String?
    let services: [HealthService]?
    struct HealthService: Identifiable, Decodable {
        let id = UUID()
        let name: String; let healthy: Bool; let latencyMs: Int?
        enum CodingKeys: String, CodingKey { case name, healthy, latencyMs }
    }
}

struct AdminBroadcastItem: Identifiable, Decodable {
    let id: String
    let action: String
    let createdAt: String?
    let metadata: AnyCodable?
}
struct AdminBroadcastsResp: Decodable { let broadcasts: [AdminBroadcastItem]? }

struct AdminPremiumResp: Decodable { let activeSubs: Int?; let trialCount: Int?; let churnedToday: Int? }

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

// MARK: - Module enum

internal enum AdminModule: String, CaseIterable, Identifiable {
    case overview, users, rooms, moderation, flags, analytics, system, audit, broadcasts, premium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .users: return "Users"
        case .rooms: return "Rooms"
        case .moderation: return "Moderation"
        case .flags: return "Feature Flags"
        case .analytics: return "Analytics"
        case .system: return "System"
        case .audit: return "Audit Log"
        case .broadcasts: return "Broadcasts"
        case .premium: return "Premium"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "rectangle.3.group"
        case .users: return "person.2"
        case .rooms: return "tv"
        case .moderation: return "shield.lefthalf.filled"
        case .flags: return "flag.fill"
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
                                .foregroundStyle(module == mod ? Color(red:0.20,green:0.82,blue:0.92) : .white.opacity(0.75))
                                .frame(width: 20)
                            Text(mod.title)
                                .foregroundStyle(module == mod ? .white : .white.opacity(0.75))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(module == mod ? Color(red:0.20,green:0.82,blue:0.92).opacity(0.15) : Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red:0.06,green:0.07,blue:0.10))
            .navigationTitle("Admin")
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
        case .flags: AdminFlagsView()
        case .analytics: AdminAnalyticsView()
        case .system: AdminSystemView()
        case .audit: AdminAuditView()
        case .broadcasts: AdminBroadcastsView()
        case .premium: AdminPremiumView()
        }
    }
}

// MARK: - Shell

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
                    Text(title).font(.title2.bold()).foregroundStyle(.white)
                    Spacer()
                    if let refresh = onRefresh {
                        Button { Task { await refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.55))
                        }.buttonStyle(.plain)
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

// Stat card
struct StatCard: View {
    let label: String; let value: String; var accent: Color = Color(red:0.20,green:0.82,blue:0.92)
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.2)))
    }
}

// MARK: - 1. Overview

struct AdminOverviewView: View {
    @State private var health: AdminHealthResp? = nil
    @State private var analytics: AdminAnalyticsResp? = nil
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Overview", isLoading: loading, errorMsg: err, onRefresh: load) {
            if let a = analytics {
                LazyVGrid(columns: [.init(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    StatCard(label: "DAU", value: a.dau.map(String.init) ?? "--")
                    StatCard(label: "MAU", value: a.mau.map(String.init) ?? "--")
                    StatCard(label: "Total users", value: a.totalUsers.map(String.init) ?? "--")
                    StatCard(label: "Active rooms", value: a.activeRooms.map(String.init) ?? "--", accent: .green)
                }
            }
            if let h = health {
                Text("Services").font(.headline).foregroundStyle(.white).padding(.top, 8)
                ForEach(h.services ?? []) { svc in
                    HStack {
                        Circle().fill(svc.healthy ? .green : .red).frame(width: 8, height: 8)
                        Text(svc.name).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Text(svc.latencyMs.map { "\($0)ms" } ?? "--").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(10)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
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
        if hr == nil && ar == nil { err = "Failed to load overview" }
        loading = false
    }
}

// MARK: - 2. Users

struct AdminUsersView: View {
    @State private var query = ""
    @State private var users: [AdminUser] = []
    @State private var loading = false
    @State private var err: String? = nil
    @State private var selectedUser: AdminUser? = nil
    @State private var actionConfirm: (title: String, action: () async -> Void)? = nil

    var body: some View {
        AdminShell(title: "Users", isLoading: loading, errorMsg: err, onRefresh: { await search() }) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.4))
                TextField("Search username / email", text: $query)
                    .foregroundStyle(.white)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button { query = ""; Task { await search() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                    }.buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            ForEach(users) { user in
                HStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red:0.20,green:0.82,blue:0.92), Color(red:0.28,green:1.0,blue:0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                        .overlay(Text(String(user.username.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundStyle(.black))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username).font(.subheadline.bold()).foregroundStyle(.white)
                        Text(user.email).font(.caption).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(user.role).font(.caption2.bold())
                            .foregroundStyle(user.role == "admin" || user.role == "founder" ? Color(red:0.20,green:0.82,blue:0.92) : .white.opacity(0.5))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((user.role == "admin" || user.role == "founder" ? Color(red:0.20,green:0.82,blue:0.92) : Color.white).opacity(0.1), in: Capsule())
                        if user.banned == true {
                            Text("BANNED").font(.caption2.bold()).foregroundStyle(.red)
                        }
                    }
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contextMenu {
                    if user.banned == true {
                        Button("Unban") {
                            actionConfirm = ("Unban \(user.username)?", { await banUser(user.id, ban: false) })
                        }
                    } else {
                        Button("Ban", role: .destructive) {
                            actionConfirm = ("Ban \(user.username)?", { await banUser(user.id, ban: true) })
                        }
                    }
                    Button("Make admin") {
                        actionConfirm = ("Make \(user.username) admin?", { await setRole(user.id, role: "admin") })
                    }
                }
            }
        }
        .confirmationDialog(actionConfirm?.title ?? "", isPresented: Binding(get: { actionConfirm != nil }, set: { if !$0 { actionConfirm = nil } })) {
            Button("Confirm", role: .destructive) {
                if let a = actionConfirm { Task { await a.action(); actionConfirm = nil } }
            }
            Button("Cancel", role: .cancel) { actionConfirm = nil }
        }
        .task { await search() }
    }

    private func search() async {
        loading = true; err = nil
        let q = query.isEmpty ? "" : "?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
        do {
            let resp: AdminUsersResp = try await AdminAPI.shared.get("/admin/users" + q)
            users = resp.users
        } catch { err = "Load failed" }
        loading = false
    }
    private func banUser(_ id: String, ban: Bool) async {
        _ = try? await AdminAPI.shared.post("/admin/users/\(id)/" + (ban ? "ban" : "unban"), body: ["reason": "admin action"])
        await search()
    }
    private func setRole(_ id: String, role: String) async {
        _ = try? await AdminAPI.shared.post("/admin/users/\(id)/role", body: ["role": role, "reason": "admin action"]) as [String: Any]
        await search()
    }
}

// MARK: - 3. Rooms

struct AdminRoomsView: View {
    @State private var rooms: [AdminRoom] = []
    @State private var loading = false
    @State private var err: String? = nil
    @State private var closeTarget: AdminRoom? = nil

    var body: some View {
        AdminShell(title: "Live Rooms", isLoading: loading, errorMsg: err, onRefresh: load) {
            ForEach(rooms) { room in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name).font(.subheadline.bold()).foregroundStyle(.white)
                        Text("Host: \(room.hostName ?? "--")  |  \(room.privacy ?? "public")").font(.caption).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    if let cnt = room.participantCount {
                        Label(String(cnt), systemImage: "person.fill")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Button("Close") { closeTarget = room }
                        .buttonStyle(.bordered).tint(.red).font(.caption)
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if rooms.isEmpty && !loading {
                Text("No active rooms").font(.subheadline).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Force close room?", isPresented: Binding(get: { closeTarget != nil }, set: { if !$0 { closeTarget = nil } })) {
            Button("Close room", role: .destructive) {
                if let r = closeTarget { Task { await closeRoom(r.id); closeTarget = nil } }
            }
            Button("Cancel", role: .cancel) { closeTarget = nil }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { let r: AdminRoomsResp = try await AdminAPI.shared.get("/admin/rooms"); rooms = r.rooms }
        catch { err = "Load failed" }
        loading = false
    }
    private func closeRoom(_ id: String) async {
        _ = try? await AdminAPI.shared.post("/admin/rooms/\(id)/close", body: [:]) as [String: Any]
        await load()
    }
}

// MARK: - 4. Moderation

struct AdminModerationView: View {
    @State private var items: [AdminReportItem] = []
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Report Queue", isLoading: loading, errorMsg: err, onRefresh: load) {
            ForEach(items) { r in
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.targetPreview ?? "(no preview)").font(.subheadline).foregroundStyle(.white)
                    Text(r.reason ?? "No reason").font(.caption).foregroundStyle(.white.opacity(0.5))
                    HStack(spacing: 8) {
                        Button("Resolve") { Task { await resolve(r.id) } }
                            .buttonStyle(.borderedProminent).tint(Color(red:0.20,green:0.82,blue:0.92)).font(.caption)
                        Button("Dismiss") { Task { await resolve(r.id) } }
                            .buttonStyle(.bordered).font(.caption)
                    }
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if items.isEmpty && !loading {
                Text("Queue is empty").font(.subheadline).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { let r: AdminReportsResp = try await AdminAPI.shared.get("/admin/moderation/queue"); items = r.reports ?? [] }
        catch { err = "Load failed" }
        loading = false
    }
    private func resolve(_ id: String) async {
        _ = try? await AdminAPI.shared.post("/admin/moderation/messages/\(id)/delete", body: [:]) as [String: Any]
        await load()
    }
}

// MARK: - 5. Feature Flags

struct AdminFlagsView: View {
    @State private var flags: [AdminFlagItem] = []
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Feature Flags", isLoading: loading, errorMsg: err, onRefresh: load) {
            ForEach(flags) { f in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.key).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
                        if let owner = f.owner { Text(owner).font(.caption).foregroundStyle(.white.opacity(0.4)) }
                    }
                    Spacer()
                    Text(f.enabled ? "ON" : "OFF")
                        .font(.caption2.bold())
                        .foregroundStyle(f.enabled ? .green : .white.opacity(0.4))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((f.enabled ? Color.green : Color.white).opacity(0.1), in: Capsule())
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if flags.isEmpty && !loading {
                Text("No flags configured").font(.subheadline).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { let r: AdminFlagsResp = try await AdminAPI.shared.get("/admin/system/flags"); flags = r.flags ?? [] }
        catch { err = "Load failed" }
        loading = false
    }
}

// MARK: - 6. Analytics

struct AdminAnalyticsView: View {
    @State private var data: AdminAnalyticsResp? = nil
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Analytics", isLoading: loading, errorMsg: err, onRefresh: load) {
            if let d = data {
                LazyVGrid(columns: [.init(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    StatCard(label: "DAU", value: d.dau.map(String.init) ?? "--")
                    StatCard(label: "MAU", value: d.mau.map(String.init) ?? "--")
                    StatCard(label: "Total users", value: d.totalUsers.map(String.init) ?? "--")
                    StatCard(label: "Active rooms", value: d.activeRooms.map(String.init) ?? "--", accent: .green)
                    if let p50 = d.p50SyncDrift { StatCard(label: "p50 sync drift", value: String(format: "%.0fms", p50), accent: .yellow) }
                    if let p95 = d.p95SyncDrift { StatCard(label: "p95 sync drift", value: String(format: "%.0fms", p95), accent: .orange) }
                }
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { data = try await AdminAPI.shared.get("/admin/analytics/overview") }
        catch { err = "Load failed" }
        loading = false
    }
}

// MARK: - 7. System

struct AdminSystemView: View {
    @State private var health: AdminHealthResp? = nil
    @State private var loading = false
    @State private var err: String? = nil
    @State private var showMaintenance = false

    var body: some View {
        AdminShell(title: "System", isLoading: loading, errorMsg: err, onRefresh: load) {
            if let h = health {
                StatCard(label: "Overall status", value: h.status?.uppercased() ?? "--",
                         accent: h.status == "ok" ? .green : .red)
                Text("Services").font(.headline).foregroundStyle(.white).padding(.top, 4)
                ForEach(h.services ?? []) { svc in
                    HStack {
                        Circle().fill(svc.healthy ? .green : .red).frame(width: 8, height: 8)
                        Text(svc.name).foregroundStyle(.white)
                        Spacer()
                        Text(svc.latencyMs.map { "\($0)ms" } ?? "--")
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(10)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Divider().overlay(.white.opacity(0.1)).padding(.vertical, 4)
            Button { showMaintenance = true } label: {
                Label("Toggle Maintenance Mode", systemImage: "wrench.and.screwdriver")
                    .font(.subheadline).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Toggle maintenance mode?", isPresented: $showMaintenance) {
                Button("Enable maintenance", role: .destructive) {
                    Task { _ = try? await AdminAPI.shared.post("/admin/system/maintenance", body: ["enabled": true, "reason": "admin"]) as [String: Any] }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { health = try await AdminAPI.shared.get("/admin/system/health") }
        catch { err = "Load failed" }
        loading = false
    }
}

// MARK: - 8. Audit Log

struct AdminAuditView: View {
    @State private var logs: [AdminAuditItem] = []
    @State private var loading = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Audit Log", isLoading: loading, errorMsg: err, onRefresh: load) {
            ForEach(logs) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.action).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color(red:0.20,green:0.82,blue:0.92))
                    if let t = e.createdAt { Text(t).font(.caption2).foregroundStyle(.white.opacity(0.35)) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if logs.isEmpty && !loading {
                Text("No audit events").font(.subheadline).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { let r: AdminAuditResp = try await AdminAPI.shared.get("/admin/audit?limit=50"); logs = r.logs ?? [] }
        catch { err = "Load failed" }
        loading = false
    }
}

// MARK: - 9. Broadcasts

struct AdminBroadcastsView: View {
    @State private var message = ""
    @State private var audience = "all"
    @State private var history: [AdminBroadcastItem] = []
    @State private var loading = false
    @State private var sending = false
    @State private var sentBanner = false
    @State private var err: String? = nil

    var body: some View {
        AdminShell(title: "Broadcasts", isLoading: loading, errorMsg: err, onRefresh: loadHistory) {
            // Composer
            VStack(alignment: .leading, spacing: 10) {
                Text("New broadcast").font(.headline).foregroundStyle(.white)
                TextField("Message text", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
                Picker("Audience", selection: $audience) {
                    Text("All users").tag("all")
                    Text("Plink+ only").tag("plus")
                    Text("Free only").tag("free")
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await send() }
                } label: {
                    Label(sending ? "Sending..." : "Send push to everyone", systemImage: "megaphone.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red:0.20,green:0.82,blue:0.92))
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                if sentBanner {
                    Text("Broadcast sent!").font(.caption).foregroundStyle(.green)
                }
            }
            .padding(14)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !history.isEmpty {
                Text("Recent broadcasts").font(.headline).foregroundStyle(.white).padding(.top, 8)
                ForEach(history) { b in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.action).font(.caption.bold()).foregroundStyle(Color(red:0.20,green:0.82,blue:0.92))
                        if let t = b.createdAt { Text(t).font(.caption2).foregroundStyle(.white.opacity(0.4)) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .task { await loadHistory() }
    }
    private func send() async {
        sending = true; err = nil
        do {
            struct Resp: Decodable { let success: Bool? }
            let _: Resp = try await AdminAPI.shared.post("/admin/broadcasts/send", body: [
                "title": "Plink", "body": message, "topic": audience
            ])
            message = ""
            sentBanner = true
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); sentBanner = false }
            await loadHistory()
        } catch { err = "Failed to send" }
        sending = false
    }
    private func loadHistory() async {
        loading = true
        do { let r: AdminBroadcastsResp = try await AdminAPI.shared.get("/admin/broadcasts/history"); history = r.broadcasts ?? [] }
        catch { /* silent */ }
        loading = false
    }
}

// MARK: - 10. Premium

struct AdminPremiumView: View {
    @State private var data: AdminPremiumResp? = nil
    @State private var loading = false
    @State private var err: String? = nil
    @State private var compUserId = ""
    @State private var compDays = "30"
    @State private var compSent = false

    var body: some View {
        AdminShell(title: "Premium", isLoading: loading, errorMsg: err, onRefresh: load) {
            if let d = data {
                LazyVGrid(columns: [.init(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    StatCard(label: "Active Plink+ subs", value: d.activeSubs.map(String.init) ?? "--", accent: .yellow)
                    StatCard(label: "Trial users", value: d.trialCount.map(String.init) ?? "--")
                    StatCard(label: "Churned today", value: d.churnedToday.map(String.init) ?? "--", accent: .red)
                }
            }
            Divider().overlay(.white.opacity(0.1)).padding(.vertical, 8)
            Text("Comp subscription").font(.headline).foregroundStyle(.white)
            TextField("User ID", text: $compUserId)
                .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            HStack {
                TextField("Days (default 30)", text: $compDays)
                    .keyboardType(.numberPad)
                    .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
                Button("Grant") {
                    Task { await grantComp() }
                }
                .buttonStyle(.borderedProminent).tint(Color(red:0.20,green:0.82,blue:0.92))
                .disabled(compUserId.isEmpty)
            }
            if compSent { Text("Subscription granted!").font(.caption).foregroundStyle(.green) }
        }
        .task { await load() }
    }
    private func load() async {
        loading = true; err = nil
        do { data = try await AdminAPI.shared.get("/admin/premium/metrics") }
        catch { err = "Load failed" }
        loading = false
    }
    private func grantComp() async {
        do {
            struct R: Decodable { let success: Bool? }
            let _: R = try await AdminAPI.shared.post("/admin/premium/comp", body: [
                "userId": compUserId,
                "days": Int(compDays) ?? 30,
                "reason": "admin comp"
            ])
            compSent = true
            compUserId = ""
            Task { try? await Task.sleep(nanoseconds: 3_000_000_000); compSent = false }
        } catch { err = "Failed" }
    }
}
