import Foundation

// MARK: - Room Model
struct Room: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let hostID: String
    let hostName: String
    let code: String               // 6-char shareable code
    var participants: [UserPreview]
    let mediaItem: MediaItem?
    let isActive: Bool
    let maxParticipants: Int
    let hostIsPremium: Bool
    let createdAt: Date
    /// NEW: Privacy level — public (visible to all), friends (friends only), private (link only)
    var privacy: RoomPrivacy
    /// NEW: Optional password for locked rooms. nil = no password needed.
    var password: String?
    /// NEW: True if room has a password set
    var isLocked: Bool { password != nil && !(password?.isEmpty ?? true) }

    /// Pack v3: Prisma _count (когда бэкенд отдаёт include: { _count: { select: { participants: true } } })
    /// вместо массива participants. Экономит трафик — отдаёт только количество.
    var _count: RoomCount?

    var participantCount: Int {
        // Pack v3: Бэкенд отдаёт _count.participants (Prisma include),
        // а не массив participants. Поддерживаем оба варианта.
        if !participants.isEmpty {
            return participants.count
        }
        return _count?.participants ?? 0
    }

    var isFull: Bool {
        participantCount >= maxParticipants
    }

    /// Takes the viewer's id rather than reading it from a singleton: a `Room` is
    /// decoded from the API and has no notion of who "you" are, so a parameterless
    /// `isHost` could only ever guess — and the version that guessed returned
    /// false for everyone, including the actual host.
    func isHost(userId: String) -> Bool {
        hostID == userId
    }

    var formattedDate: String {
        createdAt.formatted(.dateTime.month().day().hour().minute())
    }

    /// Кастомный init для backwards compatibility (hostIsPremium может отсутствовать в JSON).
    init(id: String, name: String, hostID: String, hostName: String, code: String,
         participants: [UserPreview], mediaItem: MediaItem?, isActive: Bool,
         maxParticipants: Int, hostIsPremium: Bool, createdAt: Date,
         privacy: RoomPrivacy = .publicRoom,
         password: String? = nil) {
        self.id = id
        self.name = name
        self.hostID = hostID
        self.hostName = hostName
        self.code = code
        self.participants = participants
        self.mediaItem = mediaItem
        self.isActive = isActive
        self.maxParticipants = maxParticipants
        self.hostIsPremium = hostIsPremium
        self.createdAt = createdAt
        self.privacy = privacy
        self.password = password
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hostID = try c.decode(String.self, forKey: .hostID)
        hostName = try c.decodeIfPresent(String.self, forKey: .hostName) ?? "Unknown"
        code = try c.decode(String.self, forKey: .code)
        // Pack v3: participants может отсутствовать (бэкенд не всегда отдаёт массив)
        participants = try c.decodeIfPresent([UserPreview].self, forKey: .participants) ?? []
        // A media item this client cannot decode (e.g. written by a newer client or an
        // admin tool) must not hide the whole room: the room still lists, as "no video yet".
        mediaItem = (try? c.decodeIfPresent(MediaItem.self, forKey: .mediaItem)) ?? nil
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        maxParticipants = try c.decodeIfPresent(Int.self, forKey: .maxParticipants) ?? 10
        hostIsPremium = try c.decodeIfPresent(Bool.self, forKey: .hostIsPremium) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        // Rooms created before link-privacy existed persist "friends"; map it to
        // .byLink so an old room does not decode as public.
        let privacyRaw = try c.decodeIfPresent(String.self, forKey: .privacy) ?? "public"
        switch privacyRaw {
        case "public": privacy = .publicRoom
        case "private": privacy = .privateRoom
        case "link": privacy = .byLink
        case "friends": privacy = .friendsRoom
        default: privacy = .publicRoom
        }
        password = try c.decodeIfPresent(String.self, forKey: .password)
        // Pack v3: _count (Prisma include) — опциональное
        _count = try c.decodeIfPresent(RoomCount.self, forKey: ._count)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(hostID, forKey: .hostID)
        try c.encode(hostName, forKey: .hostName)
        try c.encode(code, forKey: .code)
        try c.encode(participants, forKey: .participants)
        try c.encodeIfPresent(mediaItem, forKey: .mediaItem)
        try c.encode(isActive, forKey: .isActive)
        try c.encode(maxParticipants, forKey: .maxParticipants)
        try c.encode(hostIsPremium, forKey: .hostIsPremium)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(privacy, forKey: .privacy)
        try c.encodeIfPresent(password, forKey: .password)
    }

    static var preview: Room {
        Room(
            id: "room_001",
            name: "Вечер кино",
            hostID: "user_001",
            hostName: "Алиса",
            code: "ABC123",
            participants: [
                UserPreview(id: "user_001", username: "Alex", avatarURL: nil, isOnline: true),
                UserPreview(id: "user_002", username: "Jordan", avatarURL: nil, isOnline: true),
                UserPreview(id: "user_003", username: "Sam", avatarURL: nil, isOnline: false),
            ],
            mediaItem: MediaItem.preview,
            isActive: true,
            maxParticipants: 10,
            hostIsPremium: false,
            createdAt: .now.addingTimeInterval(-3600)
        )
    }

    // MARK: - Mock Rooms
    // Mock rooms are DEBUG-only on purpose. Shipping them meant an empty or 401
    // response rendered as fake "active" rooms with fake participant counts, so a
    // signed-out user saw a busy app and a broken backend looked healthy. The
    // production UI has to render the empty state instead.
    #if DEBUG
    /// Mock rooms for SwiftUI previews and unit tests only.
    static var previewMockRooms: [Room] {
        let mkItem: (String, MediaItem.MediaType) -> MediaItem = { title, type in
            MediaItem(id: UUID().uuidString, title: title, artist: nil,
                      thumbnailURL: nil, streamURL: "", duration: 5400,
                      mediaType: type, source: .url)
        }
        return [
            Room(id: "preview1", name: "Preview Room", hostID: "preview_host",
                 hostName: "Preview", code: "PREV01",
                 participants: [], mediaItem: mkItem("Preview", .video),
                 isActive: true, maxParticipants: 10, hostIsPremium: false,
                 createdAt: .now),
        ]
    }
    #endif

    enum CodingKeys: String, CodingKey {
        case id, name, hostID, hostName, code
        case participants, mediaItem, isActive
        case maxParticipants, hostIsPremium, createdAt, privacy, password
        case _count
    }
}

// MARK: - Room Count (Prisma _count include)
struct RoomCount: Codable, Sendable, Hashable {
    let participants: Int
}

// MARK: - Create Room Request
struct CreateRoomRequest: Codable, Sendable {
    let name: String
    let maxParticipants: Int
    let mediaItem: MediaItem?
    let privacy: RoomPrivacy
    /// NEW: Optional password for locked rooms
    let password: String?
    /// Pack v2: hostName отправляем с клиента (бэкенд берёт из JWT,
    /// но если JWT не содержит username — fallback на это поле).
    /// Бэкенд rooms.ts: `hostName: request.user.username || body.hostName`
    let hostName: String?
}

// MARK: - Join Room Request
struct JoinRoomRequest: Codable, Sendable {
    let code: String
    /// NEW: Optional password for locked rooms
    let password: String?
}

// MARK: - Room Privacy Level (Блок 4 — Studio)
/// Режим приватности комнаты.
enum RoomPrivacy: String, CaseIterable, Identifiable, Codable, Sendable {
    case publicRoom = "public"      // видна всем на главной
    case privateRoom = "private"    // закрытая, с паролем
    case byLink = "link"            // только по ссылке, без пароля
    case friendsRoom = "friends"    // Только друзья хоста

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicRoom: return "Публичная"
        case .privateRoom: return "Приватная"
        case .byLink: return "По ссылке"
        case .friendsRoom: return "Для друзей"
        }
    }

    var subtitle: String {
        switch self {
        case .publicRoom: return "Видна всем на главной"
        case .privateRoom: return "Только по коду + паролю"
        case .byLink: return "Только по ссылке без пароля"
        case .friendsRoom: return "Только ваши друзья Plink"
        }
    }

    var icon: String {
        switch self {
        case .publicRoom: return "globe"
        case .privateRoom: return "lock.fill"
        case .byLink: return "link"
        case .friendsRoom: return "person.2.fill"
        }
    }
}
