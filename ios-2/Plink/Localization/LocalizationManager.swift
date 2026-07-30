import Foundation
import SwiftUI
import Combine

// MARK: - App Language
/// Поддерживаемые языки приложения. Переключаются в рантайме (не системно).
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case russian = "ru"
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    /// Название языка на самом языке (для переключателя).
    var nativeName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// English name of the language.
    var englishName: String {
        switch self {
        case .russian: return "Russian"
        case .english: return "English"
        case .chinese: return "Chinese"
        }
    }

    /// Флаг для иконки.
    var flag: String {
        switch self {
        case .russian: return "🇷🇺"
        case .english: return "🇬🇧"
        case .chinese: return "🇨🇳"
        }
    }
}

// MARK: - Localization Manager
/// Менеджер локализации с переключением языка в рантайме.
/// Хранит выбор в UserDefaults, транслирует изменения через objectWillChange.
@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// Текущий язык (публикуется → UI обновляется автоматически).
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "plink_app_language"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.russian.rawValue
        currentLanguage = AppLanguage(rawValue: raw) ?? .russian
    }

    /// Nonisolated доступ к текущему языку для use-case'ов вне MainActor
    /// (например, вычисляемые свойства enum'ов). Читает напрямую из UserDefaults.
    static var sharedSafe: LanguageReader { LanguageReader() }

    /// Локализованная строка по ключу.
    func string(_ key: L10n.Key) -> String {
        L10n.table[key]?[currentLanguage] ?? key.rawValue
    }
}

/// Thread-safe read-only доступ к выбранному языку.
struct LanguageReader {
    var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "plink_app_language") ?? AppLanguage.russian.rawValue
        return AppLanguage(rawValue: raw) ?? .russian
    }
}

// MARK: - L10n (Strings Table)
/// Все строки приложения в одном месте. Добавлять новые — сюда.
enum L10n {

    enum Key: String {
        // App / Brand
        case appName = "app.name"
        case appTagline = "app.tagline"

        // Tab bar (M25)
        case tabHome = "tab.home"
        case tabRooms = "tab.rooms"
        case tabAI = "tab.ai"
        case tabFriends = "tab.friends"
        case tabProfile = "tab.profile"

        // Friends hub (M26)
        case frWatchingNow = "fr.watchingNow"
        case frOnline = "fr.online"
        case frAllFriends = "fr.allFriends"
        case frAdd = "fr.add"
        case frAccept = "fr.accept"
        case frDecline = "fr.decline"
        case frJoin = "fr.join"
        case frCantMessage = "fr.cantMessage"
        case frNoRequests = "fr.noRequests"
        case frNoRequestsSub = "fr.noRequestsSub"
        case frIncoming = "fr.incoming"
        case frOutgoing = "fr.outgoing"
        case frPending = "fr.pending"
        case frWantsToAdd = "fr.wantsToAdd"
        case frNo = "fr.no"
        case frAddByUsername = "fr.addByUsername"
        case frAddHint = "fr.addHint"
        case frOrSearch = "fr.orSearch"
        case frFriendBadge = "fr.friendBadge"
        case frSent = "fr.sent"
        case frNobodyFound = "fr.nobodyFound"
        case frEmptyTitle = "fr.emptyTitle"
        case frEmptySub = "fr.emptySub"
        case frFind = "fr.find"
        case frInviteLink = "fr.inviteLink"

        // DM chat extras (M26)
        case dmChatsBack = "dm.chatsBack"
        case dmReaction = "dm.reaction"
        case dmNoForwardFriends = "dm.noForwardFriends"
        case dmDeletedAccount = "dm.deletedAccount"
        case dmChatTheme = "dm.chatTheme"

        // Profile (M26)
        case prSignOut = "pr.signOut"
        case prEditProfile = "pr.editProfile"
        case prPlusActive = "pr.plusActive"
        case prGetPlus = "pr.getPlus"
        case prActivity = "pr.activity"
        case prDisplayName = "pr.displayName"
        case prAdmin = "pr.admin"
        case dvWatchTogether = "dv.watchTogether"
        case dvWithWhom = "dv.withWhom"
        case dvQuickRoom = "dv.quickRoom"
        case dvCreateOrJoin = "dv.createOrJoin"
        case dvContinueTogether = "dv.continueTogether"
        case dvLiveNow = "dv.liveNow"
        case dvNoRooms = "dv.noRooms"
        case dvNoRoomsSub = "dv.noRoomsSub"
        case dvLoadFailed = "dv.loadFailed"
        case pxDisplayName = "px.displayName"
        case pxNoSessions = "px.noSessions"
        case pxContactSupport = "px.contactSupport"
        case pxEmptyList = "px.emptyList"
        case pxBlockHint = "px.blockHint"
        case pxDeleteAccount = "px.deleteAccount"
        case nothingFound = "common.nothingFound"
        case roomLabel = "common.room"
        case ytTryAnother = "yt.tryAnother"
        case ytError = "yt.error"
        case ytPasteLink = "yt.pasteLink"
        case ytSelect = "yt.select"
        case ytCantEmbed = "yt.cantEmbed"
        case ytCheckOnPlay = "yt.checkOnPlay"
        case vpMyStats = "vp.myStats"
        case vpActivity = "vp.activity"
        case vpAchievementsHint = "vp.achievementsHint"
        case vpStandard = "vp.standard"
        case phPhotoLimited = "ph.photoLimited"
        case phDisplayNameHint = "ph.displayNameHint"
        case phUsernameHint = "ph.usernameHint"
        case aiCompanion = "ai.companion"
        case aiWhatToday = "ai.whatToday"
        case aiIntro = "ai.intro"
        case aiCancel = "ai.cancel"
        case pwPremium = "pw.premium"
        case pwSub = "pw.sub"
        case pwTrial = "pw.trial"
        case pwRestore = "pw.restore"
        case pwCancelAnytime = "pw.cancelAnytime"
        case sbVideoFound = "sb.videoFound"
        case sbHostAccount = "sb.hostAccount"
        case sbSignedIn = "sb.signedIn"
        case apTitle = "ap.title"
        case apSub = "ap.sub"
        case apMotion = "ap.motion"
        case apPlusPitch = "ap.plusPitch"
        case apGetPlus = "ap.getPlus"
        case frHistorySub = "fr.historySub"
        case usPrompt = "us.prompt"
        case usPromptSub = "us.promptSub"
        case jrCode = "jr.code"
        case jrPassword = "jr.password"
        case jrHasPassword = "jr.hasPassword"
        case jrJoin = "jr.join"
        case fpUnavailable = "fp.unavailable"
        case fpUnavailableSub = "fp.unavailableSub"
        case fpAchievements = "fp.achievements"
        case fpRecentlyWatched = "fp.recentlyWatched"

        // Auth flow (M27)
        case auTagline1 = "au.tagline1"
        case auTagline2 = "au.tagline2"
        case auContinue = "au.continue"
        case auHaveAccount = "au.haveAccount"
        case auSignInTitle = "au.signInTitle"
        case auSignIn = "au.signIn"
        case auStep1 = "au.step1"
        case auStep2 = "au.step2"
        case auStep3 = "au.step3"
        case auCreateAccount = "au.createAccount"
        case auWhatsYourName = "au.whatsYourName"
        case auSafety = "au.safety"
        case auOver16 = "au.over16"
        case auAcceptTerms = "au.acceptTerms"
        case auAcceptPrivacy = "au.acceptPrivacy"
        case auNotifLater = "au.notifLater"

        // Room creation (M27)
        case rcBack = "rc.back"
        case rcWhatWatch = "rc.whatWatch"
        case rcPickService = "rc.pickService"
        case rcNoServices = "rc.noServices"
        case rcRoomName = "rc.roomName"
        case rcWhoCanJoin = "rc.whoCanJoin"
        case rcCreate = "rc.create"
        case rcCreating = "rc.creating"

        // Settings (M27)
        case stDeveloper = "st.developer"
        case stPlusActive = "st.plusActive"
        case stActive = "st.active"
        case stPlusInactive = "st.plusInactive"
        case stSubscribeHint = "st.subscribeHint"
        case stManageSub = "st.manageSub"
        case stCancelSub = "st.cancelSub"
        case stSubscribe = "st.subscribe"

        // Watch room chat (M27)
        case wcReport = "wc.report"
        case wcBlock = "wc.block"
        case wcKick = "wc.kick"

        // Common
        case cancel = "common.cancel"
        case done = "common.done"
        case back = "common.back"
        case save = "common.save"
        case delete = "common.delete"
        case error = "common.error"
        case loading = "common.loading"
        case search = "common.search"

        // DM chat (Telegram-style)
        case dmTyping = "dm.typing"
        case dmEdited = "dm.edited"
        case dmEditing = "dm.editing"
        case dmEdit = "dm.edit"
        case dmDelete = "dm.delete"
        case dmDeleteTitle = "dm.deleteTitle"
        case dmDeleteForMe = "dm.deleteForMe"
        case dmDeleteForBothPrefix = "dm.deleteForBothPrefix"

        // Login
        case loginTitle = "login.title"
        case loginTagline = "login.tagline"
        case loginEmail = "login.email"
        case loginPassword = "login.password"
        case loginUsername = "login.username"
        case loginSignIn = "login.signIn"
        case loginSigningIn = "login.signingIn"
        case loginSignUp = "login.signUp"
        case loginDontHaveAccount = "login.dontHaveAccount"
        case loginAlreadyHaveAccount = "login.alreadyHaveAccount"
        case loginContinueWith = "login.continueWith"
        case loginConnecting = "login.connecting"
        case loginTerms = "login.terms"
        case loginCreateAccount = "login.createAccount"
        case loginJoinParty = "login.joinParty"

        // Home / Discover
        case homeDiscover = "home.discover"
        case homeWatchingNow = "home.watchingNow"
        case homeCreateRoom = "home.createRoom"
        case homeCreateRoomSubtitle = "home.createRoomSubtitle"
        case homeSearchRooms = "home.searchRooms"
        case homePublicRooms = "home.publicRooms"
        case homeTrending = "home.trending"
        case homeNoRooms = "home.noRooms"
        case homeLoadingRooms = "home.loadingRooms"

        // Join Room
        case joinTitle = "join.title"
        case joinSubtitle = "join.subtitle"
        case joinEnterCode = "join.enterCode"
        case joinEnter = "join.enter"
        case joinOrLink = "join.orLink"
        case joinPlaceholder = "join.placeholder"

        // Profile
        case profileTitle = "profile.title"
        case profileStatsRooms = "profile.statsRooms"
        case profileStatsHours = "profile.statsHours"
        case profileStatsFriends = "profile.statsFriends"
        case profileHistory = "profile.history"
        case profileHistoryEmpty = "profile.historyEmpty"
        case profileClear = "profile.clear"
        case profileAccount = "profile.account"
        case profileEditProfile = "profile.editProfile"
        case profileNotifications = "profile.notifications"
        case profilePrivacy = "profile.privacy"
        case profileFriends = "profile.friends"
        case profileDangerZone = "profile.dangerZone"
        case profileDeleteAccount = "profile.deleteAccount"
        case profileDeleteConfirm = "profile.deleteConfirm"
        case profileDeleteMessage = "profile.deleteMessage"
        case profileSignOut = "profile.signOut"
        case profileLanguage = "profile.language"
        case profileLanguageSubtitle = "profile.languageSubtitle"

        // Video services
        case serviceYouTube = "service.youtube"
        case serviceVK = "service.vk"
        case serviceRuTube = "service.rutube"
        case serviceCustomURL = "service.customURL"
        case serviceBrowser = "service.browser"
        case serviceCinemas = "service.cinemas"
        case serviceCinemasHint = "service.cinemasHint"
        case serviceKinopoisk = "service.kinopoisk"
        case serviceIvi = "service.ivi"
        case serviceOkko = "service.okko"
        case serviceWink = "service.wink"
        case serviceStart = "service.start"
        case servicePremier = "service.premier"
        case serviceSmotrim = "service.smotrim"
        case serviceKion = "service.kion"

        // Friends
        case friendsTitle = "friends.title"
        case friendsTab = "friends.tabFriends"
        case friendsRequests = "friends.tabRequests"
        case friendsSearch = "friends.tabSearch"
        case friendsEmpty = "friends.empty"
        case friendsAddHint = "friends.addHint"
        case friendsOnline = "friends.online"
        case friendsOffline = "friends.offline"
        case friendsNoFriends = "friends.noFriends"
        case friendsNoFriendsHint = "friends.noFriendsHint"
        case friendsIncoming = "friends.incoming"
        case friendsOutgoing = "friends.outgoing"
        case friendsNoRequests = "friends.noRequests"
        case friendsNoRequestsHint = "friends.noRequestsHint"
        case friendsSearchPlaceholder = "friends.searchPlaceholder"
        case friendsNoResults = "friends.noResults"
        case friendsNoResultsHint = "friends.noResultsHint"
        case friendsWantsToAdd = "friends.wantsToAdd"
        case friendsWaiting = "friends.waiting"
        case friendsSent = "friends.sent"

        // Room creation
        case createTitle = "create.title"
        case createSource = "create.source"
        case createRoomSettings = "create.roomSettings"
        case createInviteFriends = "create.inviteFriends"
        case createVideoLink = "create.videoLink"
        case createExtractStream = "create.extractStream"
        case createExtracting = "create.extracting"
        case createNameOptional = "create.nameOptional"
        case createReady = "create.ready"
        case createRoomName = "create.roomName"
        case createRoomNamePlaceholder = "create.roomNamePlaceholder"
        case createMaxParticipants = "create.maxParticipants"
        case createWhoCanJoin = "create.whoCanJoin"
        case createPrivateHint = "create.privateHint"
        case createInviteSelected = "create.inviteSelected"
        case createFriendsEmpty = "create.friendsEmpty"
        case createFriendsEmptyHint = "create.friendsEmptyHint"
        case createInviteHint = "create.inviteHint"
        case createBack = "create.back"
        case createNext = "create.next"
        case createLaunch = "create.launch"
        case createExtractError = "create.extractError"

        // Chat
        case chatTitle = "chat.title"
        case chatPlaceholder = "chat.placeholder"
        case chatReport = "chat.report"
        case chatBlock = "chat.block"
        case chatReportTitle = "chat.reportTitle"
        case chatBlockTitle = "chat.blockTitle"
        case chatReportMessage = "chat.reportMessage"
        case chatBlockMessage = "chat.blockMessage"

        // Room moderation
        case reportRoom = "moderation.reportRoom"
        case reportRoomSent = "moderation.reportSent"
        case blockHost = "moderation.blockHost"
        case blockHostTitle = "moderation.blockHostTitle"
        case blockHostMessage = "moderation.blockHostMessage"
        case blockHostDone = "moderation.blockHostDone"

        // Room view
        case roomConnecting = "room.connecting"
        case roomLinkCopied = "room.linkCopied"
        case roomVoiceOn = "room.voiceOn"
        case roomJoinVoice = "room.joinVoice"
        case roomChat = "room.chat"
        case roomMessagePlaceholder = "room.messagePlaceholder"
        case roomLoading = "room.loading"
        case roomPremiumActivated = "room.premiumActivated"
        case roomVoiceError = "room.voiceError"

        // Ad
        case adBreak = "ad.break"
        case adBreakSubtitle = "ad.breakSubtitle"

        // Notifications settings
        case notifTitle = "notif.title"
        case notifPush = "notif.push"
        case notifPushSubtitle = "notif.pushSubtitle"
        case notifSounds = "notif.sounds"
        case notifSoundsSubtitle = "notif.soundsSubtitle"
        case notifFriendsOnline = "notif.friendsOnline"
        case notifFriendsOnlineSubtitle = "notif.friendsOnlineSubtitle"
        case notifNewRooms = "notif.newRooms"
        case notifNewRoomsSubtitle = "notif.newRoomsSubtitle"

        // Privacy settings
        case privacyTitle = "privacy.title"
        case privacyProfileVisibility = "privacy.profileVisibility"
        case privacyProfileVisibilitySubtitle = "privacy.profileVisibilitySubtitle"
        case privacyOnlineStatus = "privacy.onlineStatus"
        case privacyOnlineStatusSubtitle = "privacy.onlineStatusSubtitle"
        case privacyReadReceipts = "privacy.readReceipts"
        case privacyReadReceiptsSubtitle = "privacy.readReceiptsSubtitle"
        case privacyClearCache = "privacy.clearCache"
        case privacyClearCacheSubtitle = "privacy.clearCacheSubtitle"
        case privacyInfo = "privacy.info"

        // Paywall
        case paywallTitle = "paywall.title"
        case paywallTagline = "paywall.tagline"
        case paywallRestore = "paywall.restore"
        case paywallSelectPlan = "paywall.selectPlan"
        case paywallSubscribe = "paywall.subscribe"
        case paywallFeatureAdShield = "paywall.featureAdShield"
        case paywallFeatureAdShieldSub = "paywall.featureAdShieldSub"
        case paywallFeature4K = "paywall.feature4K"
        case paywallFeature4KSub = "paywall.feature4KSub"
        case paywallFeatureThemes = "paywall.featureThemes"
        case paywallFeatureThemesSub = "paywall.featureThemesSub"
        case paywallFeatureNick = "paywall.featureNick"
        case paywallFeatureNickSub = "paywall.featureNickSub"
        case paywallFeatureAvatar = "paywall.featureAvatar"
        case paywallFeatureAvatarSub = "paywall.featureAvatarSub"
        case paywallMonth1 = "paywall.month1"
        case paywallMonth3 = "paywall.month3"
        case paywallMonth12 = "paywall.month12"

        // Friends extras
        case friendsAlreadyFriends = "friends.alreadyFriends"

        // Chat extras
        case chatBlockMessageWithName = "chat.blockMessageWithName"

        // YouTube search
        case searchTitle = "search.title"
        case searchPlaceholder = "search.placeholder"
        case searchButton = "search.button"
        case searchEmpty = "search.empty"
        case searchHint = "search.hint"
        case searchError = "search.error"
        case searchUseThis = "search.useThis"

        // Home extras
        case homeNoRoomsEmpty = "home.noRoomsEmpty"
        case homeNoResults = "home.noResults"
        case homeNoResultsHint = "home.noResultsHint"
        // M20: Network
        case offlineTitle = "network.offline"
        case offlineRetry = "network.retry"
        case connectionLost = "network.connectionLost"
        case msgSending = "network.msgSending"
        // M19: Groups / Chats
        case groupsEmpty = "groups.empty"
        case groupsEmptySubtitle = "groups.emptySubtitle"
        case groupsCreate = "groups.create"
        case groupsNoMessages = "groups.noMessages"
        case groupsAddFriendsHint = "groups.addFriendsHint"
        case groupsPhotoUnavailable = "groups.photoUnavailable"
        // M19: Inbox
        case inboxAllRead = "inbox.allRead"
        case inboxEmptySubtitle = "inbox.emptySubtitle"
        case inboxUnreadMessages = "inbox.unreadMessages"
        case inboxOpenFriendsHint = "inbox.openFriendsHint"
        // M19: Queue
        case queueMutedLabel = "queue.mutedLabel"
        case queueLabel = "queue.label"
        // M19: Room setup
        case roomPassword = "room.password"
        case roomCapacityUpsell = "room.capacityUpsell"
        case roomCustomThemes = "room.customThemes"
        case roomThemesSubtitle = "room.themesSubtitle"
        case roomWithTheme = "room.withTheme"
        case roomStandardTheme = "room.standardTheme"
        // M19: Home extras
        case homeNowTogether = "home.nowTogether"
        case homeAll = "home.all"
        case homeVideoPlaceholder = "home.videoPlaceholder"
        case homePopular = "home.popular"
        case homeQuickRoom = "home.quickRoom"
        case homeScheduleSession = "home.scheduleSession"
        case homeWatchLaterLabel = "home.watchLaterLabel"
        case homeRecommendations = "home.recommendations"
        case homeLive = "home.live"
        case homeHostLabel = "home.hostLabel"
        case homeContinueWatching = "home.continueWatching"
        case homeTimeLeft = "home.timeLeft"
        // M19: Paywall extras
        case plusTagline = "plus.tagline"
        case plusBenefitPremiumReactions = "plus.benefitPremiumReactions"
        case plusBenefitCustomEmoji = "plus.benefitCustomEmoji"
        case plusBenefitAiPriority = "plus.benefitAiPriority"
        case plusBenefitLiveThemes = "plus.benefitLiveThemes"
        case plusBenefitAvatarFrames = "plus.benefitAvatarFrames"
        case plusBenefitCapacity20 = "plus.benefitCapacity20"
        case plusBenefitVideoFilters = "plus.benefitVideoFilters"
        case plusBenefitCineBubbles = "plus.benefitCineBubbles"

    }

    /// Главная таблица переводов: [ключ: [язык: перевод]].
    static let table: [Key: [AppLanguage: String]] = [
        // Tab bar (M25)
        .tabHome: [.russian: "Главная", .english: "Home", .chinese: "首页"],
        .tabRooms: [.russian: "Комнаты", .english: "Rooms", .chinese: "房间"],
        .tabAI: [.russian: "ИИ", .english: "AI", .chinese: "AI"],
        .tabFriends: [.russian: "Друзья", .english: "Friends", .chinese: "好友"],
        .tabProfile: [.russian: "Профиль", .english: "Profile", .chinese: "我的"],
        // Friends hub (M26)
        .frWatchingNow: [.russian: "Сейчас смотрят", .english: "Watching now", .chinese: "正在观看"],
        .frOnline: [.russian: "В сети", .english: "Online", .chinese: "在线"],
        .frAllFriends: [.russian: "Все друзья", .english: "All friends", .chinese: "全部好友"],
        .frAdd: [.russian: "Добавить", .english: "Add", .chinese: "添加"],
        .frAccept: [.russian: "Принять", .english: "Accept", .chinese: "接受"],
        .frDecline: [.russian: "Отклонить", .english: "Decline", .chinese: "拒绝"],
        .frJoin: [.russian: "Присоединиться", .english: "Join", .chinese: "加入"],
        .frCantMessage: [.russian: "Нельзя написать", .english: "Can’t message", .chinese: "无法发送消息"],
        .frNoRequests: [.russian: "Нет заявок", .english: "No requests", .chinese: "暂无请求"],
        .frNoRequestsSub: [.russian: "Входящие и отправленные запросы появятся здесь", .english: "Incoming and sent requests will appear here", .chinese: "收到和发出的请求会显示在这里"],
        .frIncoming: [.russian: "ВХОДЯЩИЕ", .english: "INCOMING", .chinese: "收到"],
        .frOutgoing: [.russian: "ОТПРАВЛЕННЫЕ", .english: "SENT", .chinese: "已发送"],
        .frPending: [.russian: "Ожидает ответа", .english: "Pending", .chinese: "等待回复"],
        .frWantsToAdd: [.russian: "хочет добавить вас", .english: "wants to add you", .chinese: "想添加你"],
        .frNo: [.russian: "Нет", .english: "No", .chinese: "否"],
        .frAddByUsername: [.russian: "Добавить по @username", .english: "Add by @username", .chinese: "通过 @username 添加"],
        .frAddHint: [.russian: "Друг получит заявку. Открой иконку «Заявки» в шапке, чтобы принять входящие.", .english: "Your friend will get a request. Open the Requests icon in the header to accept incoming ones.", .chinese: "好友将收到请求。点击顶部的“请求”图标接受。"],
        .frOrSearch: [.russian: "Или найти", .english: "Or search", .chinese: "或搜索"],
        .frFriendBadge: [.russian: "Друг", .english: "Friend", .chinese: "好友"],
        .frSent: [.russian: "Отправлено", .english: "Sent", .chinese: "已发送"],
        .frNobodyFound: [.russian: "Никого не нашли", .english: "Nobody found", .chinese: "未找到用户"],
        .frEmptyTitle: [.russian: "Пока нет друзей", .english: "No friends yet", .chinese: "还没有好友"],
        .frEmptySub: [.russian: "Пригласи друга — и смотрите вместе", .english: "Invite a friend — and watch together", .chinese: "邀请好友一起观看"],
        .frFind: [.russian: "Найти друга", .english: "Find a friend", .chinese: "找好友"],
        .frInviteLink: [.russian: "Пригласить по ссылке", .english: "Invite via link", .chinese: "通过链接邀请"],
        // DM chat extras (M26)
        .dmChatsBack: [.russian: "Чаты", .english: "Chats", .chinese: "聊天"],
        .dmReaction: [.russian: "Реакция", .english: "Reaction", .chinese: "反应"],
        .dmNoForwardFriends: [.russian: "Нет друзей для пересылки", .english: "No friends to forward to", .chinese: "没有可转发的好友"],
        .dmDeletedAccount: [.russian: "Нельзя отправить сообщение удалённому аккаунту", .english: "Can’t message a deleted account", .chinese: "无法向已删除的账号发送消息"],
        .dmChatTheme: [.russian: "Тема чата", .english: "Chat theme", .chinese: "聊天主题"],
        // Profile (M26)
        .prSignOut: [.russian: "Выйти", .english: "Sign out", .chinese: "退出登录"],
        .prEditProfile: [.russian: "Редактировать профиль", .english: "Edit profile", .chinese: "编辑资料"],
        .prPlusActive: [.russian: "Плинк+ активен", .english: "Plink+ active", .chinese: "Plink+ 已激活"],
        .prGetPlus: [.russian: "Оформить Плинк+", .english: "Get Plink+", .chinese: "开通 Plink+"],
        .prActivity: [.russian: "Активность", .english: "Activity", .chinese: "动态"],
        .prDisplayName: [.russian: "Имя (ник)", .english: "Display name", .chinese: "昵称"],
        .prAdmin: [.russian: "АДМИН", .english: "ADMIN", .chinese: "管理员"],
        .dvWatchTogether: [.russian: "Смотрим вместе", .english: "Watch together", .chinese: "一起观看"],
        .dvWithWhom: [.russian: "С кем смотрим?", .english: "Who are we watching with?", .chinese: "和谁一起看？"],
        .dvQuickRoom: [.russian: "Быстрая комната", .english: "Quick room", .chinese: "快速房间"],
        .dvCreateOrJoin: [.russian: "Создать или войти по коду", .english: "Create or join with a code", .chinese: "创建或通过代码加入"],
        .dvContinueTogether: [.russian: "Продолжить вместе", .english: "Continue together", .chinese: "继续一起看"],
        .dvLiveNow: [.russian: "Сейчас в эфире", .english: "Live now", .chinese: "正在直播"],
        .dvNoRooms: [.russian: "Пока нет активных комнат", .english: "No active rooms yet", .chinese: "暂无活跃房间"],
        .dvNoRoomsSub: [.russian: "Создайте комнату и пригласите друзей", .english: "Create a room and invite friends", .chinese: "创建房间并邀请好友"],
        .dvLoadFailed: [.russian: "Не удалось загрузить", .english: "Failed to load", .chinese: "加载失败"],
        .pxDisplayName: [.russian: "Отображаемое имя", .english: "Display name", .chinese: "显示名称"],
        .pxNoSessions: [.russian: "Нет данных о сессиях", .english: "No session data", .chinese: "暂无会话数据"],
        .pxContactSupport: [.russian: "Написать в поддержку", .english: "Contact support", .chinese: "联系客服"],
        .pxEmptyList: [.russian: "Список пуст", .english: "List is empty", .chinese: "列表为空"],
        .pxBlockHint: [.russian: "Заблокируй пользователя долгим нажатием на сообщение в комнате.", .english: "Block a user with a long press on their message in a room.", .chinese: "在房间中长按消息即可拉黑用户。"],
        .pxDeleteAccount: [.russian: "Удалить аккаунт", .english: "Delete account", .chinese: "删除账号"],
        .nothingFound: [.russian: "Ничего не найдено", .english: "Nothing found", .chinese: "未找到结果"],
        .roomLabel: [.russian: "Комната", .english: "Room", .chinese: "房间"],
        .ytTryAnother: [.russian: "Попробуйте другой запрос", .english: "Try another query", .chinese: "换个关键词试试"],
        .ytError: [.russian: "Ошибка", .english: "Error", .chinese: "错误"],
        .ytPasteLink: [.russian: "Вставить ссылку", .english: "Paste a link", .chinese: "粘贴链接"],
        .ytSelect: [.russian: "Выбрать", .english: "Select", .chinese: "选择"],
        .ytCantEmbed: [.russian: "Нельзя встроить", .english: "Can’t embed", .chinese: "无法嵌入"],
        .ytCheckOnPlay: [.russian: "Проверим при запуске", .english: "We’ll check at playback", .chinese: "播放时再检查"],
        .vpMyStats: [.russian: "МОЯ СТАТИСТИКА", .english: "MY STATS", .chinese: "我的统计"],
        .vpActivity: [.russian: "Активность в Plink", .english: "Activity in Plink", .chinese: "Plink 动态"],
        .vpAchievementsHint: [.russian: "Достижения появятся после просмотров и друзей", .english: "Achievements appear after watching and adding friends", .chinese: "观看影片并添加好友后即可解锁成就"],
        .vpStandard: [.russian: "Стандартные", .english: "Standard", .chinese: "标准"],
        .phPhotoLimited: [.russian: "На этом устройстве доступ к фото ограничен. Если нужно — разрешите в Настройках → Плинк.", .english: "Photo access is limited on this device. Allow it in Settings → Plink if needed.", .chinese: "此设备的照片访问受限。如需使用，请在设置 → Plink 中允许。"],
        .phDisplayNameHint: [.russian: "Показывается в чате и профиле. Можно использовать пробелы и эмодзи. Пусто — использовать @username.", .english: "Shown in chat and profile. Spaces and emoji allowed. Leave empty to use @username.", .chinese: "显示在聊天和资料中。可使用空格和表情。留空则使用 @username。"],
        .phUsernameHint: [.russian: "Уникальный тег для поиска. Только латиница, цифры, _ и точка. Длина 2–15 символов.", .english: "A unique tag for search. Latin letters, digits, _ and dot only. 2–15 characters.", .chinese: "用于搜索的唯一标签。仅限拉丁字母、数字、_ 和点。长度 2–15 个字符。"],
        .aiCompanion: [.russian: "Кинокомпаньон", .english: "Movie companion", .chinese: "观影伙伴"],
        .aiWhatToday: [.russian: "Что смотрим сегодня?", .english: "What are we watching today?", .chinese: "今天看什么？"],
        .aiIntro: [.russian: "Соберу очередь, создам комнату, позову друзей после подтверждения.", .english: "I’ll build a queue, create a room, and invite friends once you confirm.", .chinese: "我会整理队列、创建房间，并在你确认后邀请好友。"],
        .aiCancel: [.russian: "Отмена", .english: "Cancel", .chinese: "取消"],
        .pwPremium: [.russian: "Премиум доступ", .english: "Premium access", .chinese: "高级会员"],
        .pwSub: [.russian: "Смотри с друзьями без ограничений", .english: "Watch with friends without limits", .chinese: "与好友无限畅享"],
        .pwTrial: [.russian: "Попробовать бесплатно 7 дней", .english: "Try 7 days free", .chinese: "免费试用 7 天"],
        .pwRestore: [.russian: "Восстановить покупку", .english: "Restore purchase", .chinese: "恢复购买"],
        .pwCancelAnytime: [.russian: "Отмена в любой момент в настройках Apple ID", .english: "Cancel anytime in Apple ID settings", .chinese: "可随时在 Apple ID 设置中取消"],
        .sbVideoFound: [.russian: "Видео найдено!", .english: "Video found!", .chinese: "找到视频！"],
        .sbHostAccount: [.russian: "Для этого сервиса host использует свой аккаунт подписки. Plink не предоставляет контент — мы только синхронизируем просмотр.", .english: "The host uses their own subscription for this service. Plink doesn’t provide content — we only sync playback.", .chinese: "该平台由房主使用自己的订阅账号。Plink 不提供内容，仅同步播放。"],
        .sbSignedIn: [.russian: "Я вошёл, продолжить", .english: "I’ve signed in, continue", .chinese: "已登录，继续"],
        .apTitle: [.russian: "Оформление", .english: "Appearance", .chinese: "外观"],
        .apSub: [.russian: "Выбери, как выглядит Plink. Темы и эффекты сохраняются между устройствами.", .english: "Choose how Plink looks. Themes and effects sync across devices.", .chinese: "选择 Plink 的外观。主题和效果会在设备间同步。"],
        .apMotion: [.russian: "Движение и доступность", .english: "Motion & accessibility", .chinese: "动效与无障碍"],
        .apPlusPitch: [.russian: "Живые темы, анимированные bubble-стили и авторские emoji-паки. Отменить можно в любой момент.", .english: "Live themes, animated bubble styles, and exclusive emoji packs. Cancel anytime.", .chinese: "动态主题、动画气泡样式和独家表情包。可随时取消。"],
        .apGetPlus: [.russian: "Оформить Plink+", .english: "Get Plink+", .chinese: "开通 Plink+"],
        .frHistorySub: [.russian: "Комнаты, где вы смотрели вместе — кто был и что крутили", .english: "Rooms you watched together — who was there and what was playing", .chinese: "你们一起看过的房间——都有谁、放了什么"],
        .usPrompt: [.russian: "Найдите видео, сервис или комнату", .english: "Find a video, service, or room", .chinese: "搜索视频、平台或房间"],
        .usPromptSub: [.russian: "Или выберите из рекомендаций на главной", .english: "Or pick from Home recommendations", .chinese: "或从首页推荐中选择"],
        .jrCode: [.russian: "КОД КОМНАТЫ", .english: "ROOM CODE", .chinese: "房间代码"],
        .jrPassword: [.russian: "ПАРОЛЬ (ЕСЛИ НУЖЕН)", .english: "PASSWORD (IF NEEDED)", .chinese: "密码（如需要）"],
        .jrHasPassword: [.russian: "Комната с паролем?", .english: "Room has a password?", .chinese: "房间需要密码？"],
        .jrJoin: [.russian: "Войти в комнату", .english: "Join room", .chinese: "加入房间"],
        .fpUnavailable: [.russian: "Этот профиль больше недоступен", .english: "This profile is no longer available", .chinese: "该资料已不可用"],
        .fpUnavailableSub: [.russian: "История чата сохраняется, но написать или пригласить этого пользователя нельзя.", .english: "Chat history is kept, but you can’t message or invite this user.", .chinese: "聊天记录会保留，但无法向该用户发消息或发出邀请。"],
        .fpAchievements: [.russian: "Достижения", .english: "Achievements", .chinese: "成就"],
        .fpRecentlyWatched: [.russian: "Недавно смотрел", .english: "Recently watched", .chinese: "最近观看"],
        // Auth flow (M27)
        .auTagline1: [.russian: "Смотреть вместе.", .english: "Watch together.", .chinese: "一起观看。"],
        .auTagline2: [.russian: "Быть рядом.", .english: "Be close.", .chinese: "彼此相伴。"],
        .auContinue: [.russian: "Продолжить", .english: "Continue", .chinese: "继续"],
        .auHaveAccount: [.russian: "У меня уже есть аккаунт", .english: "I already have an account", .chinese: "我已有账号"],
        .auSignInTitle: [.russian: "Вход", .english: "Sign in", .chinese: "登录"],
        .auSignIn: [.russian: "Войти", .english: "Sign in", .chinese: "登录"],
        .auStep1: [.russian: "Шаг 1 из 3", .english: "Step 1 of 3", .chinese: "第 1 步，共 3 步"],
        .auStep2: [.russian: "Шаг 2 из 3", .english: "Step 2 of 3", .chinese: "第 2 步，共 3 步"],
        .auStep3: [.russian: "Шаг 3 из 3", .english: "Step 3 of 3", .chinese: "第 3 步，共 3 步"],
        .auCreateAccount: [.russian: "Создайте аккаунт", .english: "Create your account", .chinese: "创建账号"],
        .auWhatsYourName: [.russian: "Как тебя зовут?", .english: "What’s your name?", .chinese: "你叫什么名字？"],
        .auSafety: [.russian: "Безопасность", .english: "Safety", .chinese: "安全"],
        .auOver16: [.russian: "Мне больше 16 лет", .english: "I’m over 16", .chinese: "我已年满16岁"],
        .auAcceptTerms: [.russian: "Я принимаю условия использования", .english: "I accept the Terms of Use", .chinese: "我接受使用条款"],
        .auAcceptPrivacy: [.russian: "Я согласен с политикой конфиденциальности", .english: "I agree to the Privacy Policy", .chinese: "我同意隐私政策"],
        .auNotifLater: [.russian: "Уведомления можно включить позже в настройках.", .english: "You can enable notifications later in Settings.", .chinese: "稍后可在设置中开启通知。"],
        // Room creation (M27)
        .rcBack: [.russian: "Назад", .english: "Back", .chinese: "返回"],
        .rcWhatWatch: [.russian: "Что смотрим?", .english: "What are we watching?", .chinese: "看什么？"],
        .rcPickService: [.russian: "Выбери сервис — пригласи друзей и смотрите вместе", .english: "Pick a service — invite friends and watch together", .chinese: "选择平台，邀请好友一起观看"],
        .rcNoServices: [.russian: "Нет сервисов под этот фильтр", .english: "No services match this filter", .chinese: "没有符合筛选的平台"],
        .rcRoomName: [.russian: "Название комнаты", .english: "Room name", .chinese: "房间名称"],
        .rcWhoCanJoin: [.russian: "Кто может войти", .english: "Who can join", .chinese: "谁可以加入"],
        .rcCreate: [.russian: "Создать комнату", .english: "Create room", .chinese: "创建房间"],
        .rcCreating: [.russian: "Создаём комнату...", .english: "Creating room...", .chinese: "正在创建房间..."],
        // Settings (M27)
        .stDeveloper: [.russian: "Разработчик", .english: "Developer", .chinese: "开发者"],
        .stPlusActive: [.russian: "Плинк+ активна", .english: "Plink+ active", .chinese: "Plink+ 已激活"],
        .stActive: [.russian: "Активна", .english: "Active", .chinese: "已激活"],
        .stPlusInactive: [.russian: "Плинк+ не активна", .english: "Plink+ inactive", .chinese: "Plink+ 未激活"],
        .stSubscribeHint: [.russian: "Оформите подписку для расширенных возможностей", .english: "Subscribe for extended features", .chinese: "订阅以解锁更多功能"],
        .stManageSub: [.russian: "Управление подпиской", .english: "Manage subscription", .chinese: "管理订阅"],
        .stCancelSub: [.russian: "Отменить подписку", .english: "Cancel subscription", .chinese: "取消订阅"],
        .stSubscribe: [.russian: "Оформить подписку", .english: "Subscribe", .chinese: "立即订阅"],
        // Watch room chat (M27)
        .wcReport: [.russian: "Пожаловаться", .english: "Report", .chinese: "举报"],
        .wcBlock: [.russian: "Заблокировать", .english: "Block", .chinese: "拉黑"],
        .wcKick: [.russian: "Кикнуть", .english: "Kick", .chinese: "踢出"],
        // DM chat (Telegram-style)
        .dmTyping: [
            .russian: "печатает…", .english: "typing…", .chinese: "正在输入…"],
        .dmEdited: [
            .russian: "изменено", .english: "edited", .chinese: "已编辑"],
        .dmEditing: [
            .russian: "Редактирование", .english: "Editing", .chinese: "编辑中"],
        .dmEdit: [
            .russian: "Изменить", .english: "Edit", .chinese: "编辑"],
        .dmDelete: [
            .russian: "Удалить", .english: "Delete", .chinese: "删除"],
        .dmDeleteTitle: [
            .russian: "Удалить сообщение?", .english: "Delete message?", .chinese: "删除消息？"],
        .dmDeleteForMe: [
            .russian: "Удалить у себя", .english: "Delete for me", .chinese: "仅为我删除"],
        .dmDeleteForBothPrefix: [
            .russian: "Удалить у себя и у", .english: "Delete for me and", .chinese: "为双方删除："],
        .appName: [
            .russian: "Плинк",
            .english: "Plink",
            .chinese: "普林克"
        ],
        .appTagline: [
            .russian: "Смотрим вместе",
            .english: "Watch together",
            .chinese: "一起观看"
        ],

        .cancel: [
            .russian: "Отмена",
            .english: "Cancel",
            .chinese: "取消"
        ],
        .done: [
            .russian: "Готово",
            .english: "Done",
            .chinese: "完成"
        ],
        .back: [
            .russian: "Назад",
            .english: "Back",
            .chinese: "返回"
        ],
        .save: [
            .russian: "Сохранить",
            .english: "Save",
            .chinese: "保存"
        ],
        .delete: [
            .russian: "Удалить",
            .english: "Delete",
            .chinese: "删除"
        ],
        .error: [
            .russian: "Ошибка",
            .english: "Error",
            .chinese: "错误"
        ],
        .loading: [
            .russian: "Загрузка...",
            .english: "Loading...",
            .chinese: "加载中..."
        ],
        .search: [
            .russian: "Поиск",
            .english: "Search",
            .chinese: "搜索"
        ],

        // Login
        .loginTitle: [
            .russian: "Плинк",
            .english: "Plink",
            .chinese: "普林克"
        ],
        .loginTagline: [
            .russian: "Смотрим вместе",
            .english: "Watch together",
            .chinese: "一起观看"
        ],
        .loginEmail: [
            .russian: "Email",
            .english: "Email",
            .chinese: "邮箱"
        ],
        .loginPassword: [
            .russian: "Пароль",
            .english: "Password",
            .chinese: "密码"
        ],
        .loginUsername: [
            .russian: "Имя пользователя",
            .english: "Username",
            .chinese: "用户名"
        ],
        .loginSignIn: [
            .russian: "Войти",
            .english: "Sign In",
            .chinese: "登录"
        ],
        .loginSigningIn: [
            .russian: "Вход...",
            .english: "Signing in...",
            .chinese: "登录中..."
        ],
        .loginSignUp: [
            .russian: "Регистрация",
            .english: "Sign Up",
            .chinese: "注册"
        ],
        .loginDontHaveAccount: [
            .russian: "Нет аккаунта? Зарегистрироваться",
            .english: "Don't have an account? Sign Up",
            .chinese: "没有账号？注册"
        ],
        .loginAlreadyHaveAccount: [
            .russian: "Уже есть аккаунт? Войти",
            .english: "Already have an account? Sign In",
            .chinese: "已有账号？登录"
        ],
        .loginContinueWith: [
            .russian: "Продолжить через",
            .english: "Continue with",
            .chinese: "继续使用"
        ],
        .loginConnecting: [
            .russian: "Подключение к",
            .english: "Connecting to",
            .chinese: "正在连接"
        ],
        .loginTerms: [
            .russian: "Продолжая, вы соглашаетесь с Условиями использования и Политикой конфиденциальности.",
            .english: "By continuing, you agree to our Terms of Service and Privacy Policy.",
            .chinese: "继续即表示您同意我们的服务条款和隐私政策。"
        ],
        .loginCreateAccount: [
            .russian: "Создать аккаунт",
            .english: "Create Account",
            .chinese: "创建账号"
        ],
        .loginJoinParty: [
            .russian: "Присоединяйся к просмотру",
            .english: "Join the watch party",
            .chinese: "加入观看派对"
        ],

        // Home
        .homeDiscover: [
            .russian: "Обзор",
            .english: "Discover",
            .chinese: "发现"
        ],
        .homeWatchingNow: [
            .russian: "Смотрят сейчас",
            .english: "Watching now",
            .chinese: "正在观看"
        ],
        .homeCreateRoom: [
            .russian: "Создать комнату",
            .english: "Create a room",
            .chinese: "创建房间"
        ],
        .homeCreateRoomSubtitle: [
            .russian: "YouTube · кинотеатры · прямая ссылка",
            .english: "YouTube · cinemas · direct link",
            .chinese: "YouTube · 影院 · 直链"
        ],
        .homeSearchRooms: [
            .russian: "Поиск комнат...",
            .english: "Search rooms...",
            .chinese: "搜索房间..."
        ],
        .homePublicRooms: [
            .russian: "Общедоступные комнаты",
            .english: "Public rooms",
            .chinese: "公共房间"
        ],
        .homeTrending: [
            .russian: "Тренды",
            .english: "Trending",
            .chinese: "热门"
        ],
        .homeNoRooms: [
            .russian: "Нет активных комнат",
            .english: "No active rooms",
            .chinese: "没有活跃房间"
        ],
        .homeLoadingRooms: [
            .russian: "Загрузка комнат...",
            .english: "Loading rooms...",
            .chinese: "加载房间中..."
        ],

        // Join
        .joinTitle: [
            .russian: "Присоединиться",
            .english: "Join",
            .chinese: "加入"
        ],
        .joinSubtitle: [
            .russian: "Введите код комнаты или ссылку",
            .english: "Enter room code or link",
            .chinese: "输入房间代码或链接"
        ],
        .joinEnterCode: [
            .russian: "Код комнаты",
            .english: "Room code",
            .chinese: "房间代码"
        ],
        .joinEnter: [
            .russian: "Войти",
            .english: "Join",
            .chinese: "加入"
        ],
        .joinOrLink: [
            .russian: "или вставьте ссылку",
            .english: "or paste a link",
            .chinese: "或粘贴链接"
        ],
        .joinPlaceholder: [
            .russian: "ABC123 или https://...",
            .english: "ABC123 or https://...",
            .chinese: "ABC123 或 https://..."
        ],

        // Profile
        .profileTitle: [
            .russian: "Профиль",
            .english: "Profile",
            .chinese: "个人资料"
        ],
        .profileStatsRooms: [
            .russian: "Комнат",
            .english: "Rooms",
            .chinese: "房间"
        ],
        .profileStatsHours: [
            .russian: "Часов",
            .english: "Hours",
            .chinese: "小时"
        ],
        .profileStatsFriends: [
            .russian: "Друзей",
            .english: "Friends",
            .chinese: "好友"
        ],
        .profileHistory: [
            .russian: "История просмотров",
            .english: "Watch history",
            .chinese: "观看历史"
        ],
        .profileHistoryEmpty: [
            .russian: "Здесь появятся просмотренные видео",
            .english: "Watched videos will appear here",
            .chinese: "观看过的视频将显示在此处"
        ],
        .profileClear: [
            .russian: "Очистить",
            .english: "Clear",
            .chinese: "清除"
        ],
        .profileAccount: [
            .russian: "Аккаунт",
            .english: "Account",
            .chinese: "账户"
        ],
        .profileEditProfile: [
            .russian: "Редактировать профиль",
            .english: "Edit profile",
            .chinese: "编辑个人资料"
        ],
        .profileNotifications: [
            .russian: "Уведомления",
            .english: "Notifications",
            .chinese: "通知"
        ],
        .profilePrivacy: [
            .russian: "Конфиденциальность",
            .english: "Privacy",
            .chinese: "隐私"
        ],
        .profileFriends: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .profileDangerZone: [
            .russian: "Опасная зона",
            .english: "Danger zone",
            .chinese: "危险区域"
        ],
        .profileDeleteAccount: [
            .russian: "Удалить аккаунт",
            .english: "Delete account",
            .chinese: "删除账户"
        ],
        .profileDeleteConfirm: [
            .russian: "Удалить аккаунт?",
            .english: "Delete account?",
            .chinese: "删除账户？"
        ],
        .profileDeleteMessage: [
            .russian: "Это действие необратимо. Все ваши данные будут удалены навсегда.",
            .english: "This action is irreversible. All your data will be permanently deleted.",
            .chinese: "此操作不可逆。您的所有数据将被永久删除。"
        ],
        .profileSignOut: [
            .russian: "Выйти",
            .english: "Sign Out",
            .chinese: "退出登录"
        ],
        .profileLanguage: [
            .russian: "Язык приложения",
            .english: "App language",
            .chinese: "应用语言"
        ],
        .profileLanguageSubtitle: [
            .russian: "Русский · English · 中文",
            .english: "Русский · English · 中文",
            .chinese: "Русский · English · 中文"
        ],

        // Video services
        .serviceYouTube: [
            .russian: "YouTube",
            .english: "YouTube",
            .chinese: "YouTube"
        ],
        .serviceVK: [
            .russian: "VK Видео",
            .english: "VK Video",
            .chinese: "VK 视频"
        ],
        .serviceRuTube: [
            .russian: "RuTube",
            .english: "RuTube",
            .chinese: "RuTube"
        ],
        .serviceCustomURL: [
            .russian: "Своя ссылка",
            .english: "Custom URL",
            .chinese: "自定义链接"
        ],
        .serviceBrowser: [
            .russian: "Браузер",
            .english: "Browser",
            .chinese: "浏览器"
        ],
        .serviceCinemas: [
            .russian: "Кинотеатры",
            .english: "Cinemas",
            .chinese: "影院"
        ],
        .serviceCinemasHint: [
            .russian: "Каждый зритель должен иметь свою подписку. Открывается в браузере с синхронизацией.",
            .english: "Each viewer needs their own subscription. Opens in browser with sync.",
            .chinese: "每位观众需有自己的订阅。在浏览器中打开并同步。"
        ],
        .serviceKinopoisk: [
            .russian: "Кинопоиск",
            .english: "Kinopoisk",
            .chinese: "Kinopoisk"
        ],
        .serviceIvi: [
            .russian: "Иви",
            .english: "Ivi",
            .chinese: "Ivi"
        ],
        .serviceOkko: [
            .russian: "Окко",
            .english: "Okko",
            .chinese: "Okko"
        ],
        .serviceWink: [
            .russian: "Wink",
            .english: "Wink",
            .chinese: "Wink"
        ],
        .serviceStart: [
            .russian: "Start",
            .english: "Start",
            .chinese: "Start"
        ],
        .servicePremier: [
            .russian: "Premier",
            .english: "Premier",
            .chinese: "Premier"
        ],
        .serviceSmotrim: [
            .russian: "Смотрим",
            .english: "Smotrim",
            .chinese: "Smotrim"
        ],
        .serviceKion: [
            .russian: "КИОН",
            .english: "KION",
            .chinese: "KION"
        ],

        // Friends
        .friendsTitle: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .friendsTab: [
            .russian: "Друзья",
            .english: "Friends",
            .chinese: "好友"
        ],
        .friendsRequests: [
            .russian: "Заявки",
            .english: "Requests",
            .chinese: "请求"
        ],
        .friendsSearch: [
            .russian: "Поиск",
            .english: "Search",
            .chinese: "搜索"
        ],
        .friendsEmpty: [
            .russian: "Друзей пока нет",
            .english: "No friends yet",
            .chinese: "还没有好友"
        ],
        .friendsAddHint: [
            .russian: "Добавить в друзья",
            .english: "Add friend",
            .chinese: "添加好友"
        ],
        .friendsOnline: [
            .russian: "В сети",
            .english: "Online",
            .chinese: "在线"
        ],
        .friendsOffline: [
            .russian: "Не в сети",
            .english: "Offline",
            .chinese: "离线"
        ],
        .friendsNoFriends: [
            .russian: "Друзей пока нет",
            .english: "No friends yet",
            .chinese: "还没有好友"
        ],
        .friendsNoFriendsHint: [
            .russian: "Найдите друзей во вкладке «Поиск»",
            .english: "Find friends in the Search tab",
            .chinese: "在搜索标签页中查找好友"
        ],
        .friendsIncoming: [
            .russian: "Входящие заявки",
            .english: "Incoming requests",
            .chinese: "收到的请求"
        ],
        .friendsOutgoing: [
            .russian: "Исходящие заявки",
            .english: "Outgoing requests",
            .chinese: "发送的请求"
        ],
        .friendsNoRequests: [
            .russian: "Нет активных заявок",
            .english: "No active requests",
            .chinese: "没有活跃请求"
        ],
        .friendsNoRequestsHint: [
            .russian: "Поделитесь ссылкой-приглашением с друзьями",
            .english: "Share an invite link with friends",
            .chinese: "与好友分享邀请链接"
        ],
        .friendsSearchPlaceholder: [
            .russian: "Поиск по имени, нику или ID...",
            .english: "Search by name, nickname or ID...",
            .chinese: "按名字、昵称或ID搜索..."
        ],
        .friendsNoResults: [
            .russian: "Ничего не найдено",
            .english: "Nothing found",
            .chinese: "未找到结果"
        ],
        .friendsNoResultsHint: [
            .russian: "Попробуйте другое имя",
            .english: "Try a different name",
            .chinese: "尝试其他名字"
        ],
        .friendsWantsToAdd: [
            .russian: "хочет добавить вас в друзья",
            .english: "wants to add you as a friend",
            .chinese: "想加你为好友"
        ],
        .friendsWaiting: [
            .russian: "ожидает подтверждения",
            .english: "awaiting confirmation",
            .chinese: "等待确认"
        ],
        .friendsSent: [
            .russian: "Отправлено",
            .english: "Sent",
            .chinese: "已发送"
        ],

        // Room creation
        .createTitle: [
            .russian: "Новая комната",
            .english: "New Room",
            .chinese: "新房间"
        ],
        .createSource: [
            .russian: "Источник видео",
            .english: "Video source",
            .chinese: "视频来源"
        ],
        .createRoomSettings: [
            .russian: "Настройки комнаты",
            .english: "Room settings",
            .chinese: "房间设置"
        ],
        .createInviteFriends: [
            .russian: "Пригласить друзей",
            .english: "Invite friends",
            .chinese: "邀请好友"
        ],
        .createVideoLink: [
            .russian: "Ссылка на видео",
            .english: "Video link",
            .chinese: "视频链接"
        ],
        .createExtractStream: [
            .russian: "Получить прямой поток",
            .english: "Get direct stream",
            .chinese: "获取直链"
        ],
        .createExtracting: [
            .russian: "Извлечение…",
            .english: "Extracting…",
            .chinese: "提取中…"
        ],
        .createNameOptional: [
            .russian: "Название (необязательно)",
            .english: "Title (optional)",
            .chinese: "标题（可选）"
        ],
        .createReady: [
            .russian: "Готово к запуску ✓",
            .english: "Ready to launch ✓",
            .chinese: "准备启动 ✓"
        ],
        .createRoomName: [
            .russian: "Название комнаты",
            .english: "Room name",
            .chinese: "房间名称"
        ],
        .createRoomNamePlaceholder: [
            .russian: "напр., Кино-ночь 🍿",
            .english: "e.g. Movie Night 🍿",
            .chinese: "例如，电影之夜 🍿"
        ],
        .createMaxParticipants: [
            .russian: "Максимум участников",
            .english: "Max participants",
            .chinese: "最多参与者"
        ],
        .createWhoCanJoin: [
            .russian: "Кто может присоединиться?",
            .english: "Who can join?",
            .chinese: "谁可以加入？"
        ],
        .createPrivateHint: [
            .russian: "Приватная комната. Друзья смогут присоединиться только по прямой ссылке после запуска.",
            .english: "Private room. Friends can join only via direct link after launch.",
            .chinese: "私密房间。好友只能在启动后通过直接链接加入。"
        ],
        .createInviteSelected: [
            .russian: "Пригласить друзей",
            .english: "Invite friends",
            .chinese: "邀请好友"
        ],
        .createFriendsEmpty: [
            .russian: "Список друзей пуст",
            .english: "Your friends list is empty",
            .chinese: "好友列表为空"
        ],
        .createFriendsEmptyHint: [
            .russian: "Добавьте друзей в профиле",
            .english: "Add friends in profile",
            .chinese: "在个人资料中添加好友"
        ],
        .createInviteHint: [
            .russian: "Выбранным друзьям будет отправлено уведомление",
            .english: "Selected friends will be notified",
            .chinese: "将通知选中的好友"
        ],
        .createBack: [
            .russian: "Назад",
            .english: "Back",
            .chinese: "返回"
        ],
        .createNext: [
            .russian: "Далее",
            .english: "Next",
            .chinese: "下一步"
        ],
        .createLaunch: [
            .russian: "🚀 Запустить вечеринку",
            .english: "🚀 Launch party",
            .chinese: "🚀 启动派对"
        ],
        .createExtractError: [
            .russian: "Не удалось извлечь видео. Возможно, оно приватное или недоступно в вашем регионе.",
            .english: "Failed to extract video. It may be private or unavailable in your region.",
            .chinese: "无法提取视频。可能是私密的或在您所在的地区不可用。"
        ],

        // Chat
        .chatTitle: [
            .russian: "Чат",
            .english: "Chat",
            .chinese: "聊天"
        ],
        .chatPlaceholder: [
            .russian: "Написать сообщение...",
            .english: "Type a message...",
            .chinese: "输入消息..."
        ],
        .chatReport: [
            .russian: "Пожаловаться",
            .english: "Report",
            .chinese: "举报"
        ],
        .chatBlock: [
            .russian: "Заблокировать",
            .english: "Block",
            .chinese: "拉黑"
        ],
        .chatReportTitle: [
            .russian: "Пожаловаться на сообщение?",
            .english: "Report message?",
            .chinese: "举报消息？"
        ],
        .chatBlockTitle: [
            .russian: "Заблокировать пользователя?",
            .english: "Block user?",
            .chinese: "拉黑用户？"
        ],
        .chatReportMessage: [
            .russian: "Выберите причину жалобы. Модерация рассмотрит обращение.",
            .english: "Select a reason. Moderators will review your report.",
            .chinese: "选择原因。管理员将审核您的举报。"
        ],
        .chatBlockMessage: [
            .russian: "Вы больше не будете видеть сообщения от этого пользователя.",
            .english: "You will no longer see messages from this user.",
            .chinese: "您将不再看到此用户的消息。"
        ],

        // Room moderation
        .reportRoom: [
            .russian: "Пожаловаться на комнату?",
            .english: "Report room?",
            .chinese: "举报房间？"
        ],
        .reportRoomSent: [
            .russian: "Жалоба отправлена",
            .english: "Report sent",
            .chinese: "举报已发送"
        ],
        .blockHost: [
            .russian: "Заблокировать хоста?",
            .english: "Block host?",
            .chinese: "拉黑房主？"
        ],
        .blockHostTitle: [
            .russian: "Заблокировать",
            .english: "Block",
            .chinese: "拉黑"
        ],
        .blockHostMessage: [
            .russian: "Комнаты от этого хоста больше не будут отображаться.",
            .english: "Rooms from this host will no longer be shown.",
            .chinese: "此房主的房间将不再显示。"
        ],
        .blockHostDone: [
            .russian: "Хост заблокирован",
            .english: "Host blocked",
            .chinese: "房主已拉黑"
        ],

        // Room view
        .roomConnecting: [
            .russian: "Подключение к комнате...",
            .english: "Connecting to room...",
            .chinese: "正在连接房间..."
        ],
        .roomLinkCopied: [
            .russian: "Ссылка скопирована!",
            .english: "Link copied!",
            .chinese: "链接已复制！"
        ],
        .roomVoiceOn: [
            .russian: "Голос вкл",
            .english: "Voice On",
            .chinese: "语音开"
        ],
        .roomJoinVoice: [
            .russian: "Голос",
            .english: "Voice",
            .chinese: "语音"
        ],
        .roomChat: [
            .russian: "Чат",
            .english: "Chat",
            .chinese: "聊天"
        ],
        .roomMessagePlaceholder: [
            .russian: "Сообщение...",
            .english: "Message...",
            .chinese: "消息..."
        ],
        .roomLoading: [
            .russian: "Загрузка...",
            .english: "Loading...",
            .chinese: "加载中..."
        ],
        .roomPremiumActivated: [
            .russian: "Premium активирован! 🎉",
            .english: "Premium activated! 🎉",
            .chinese: "Premium 已激活！ 🎉"
        ],
        .roomVoiceError: [
            .russian: "Ошибка голоса: %@",
            .english: "Voice error: %@",
            .chinese: "语音错误：%@"
        ],

        // Ad
        .adBreak: [
            .russian: "Рекламная пауза",
            .english: "Ad break",
            .chinese: "广告暂停"
        ],
        .adBreakSubtitle: [
            .russian: "Скоро продолжим просмотр",
            .english: "Resuming shortly",
            .chinese: "即将继续观看"
        ],

        // Notifications settings
        .notifTitle: [
            .russian: "Уведомления",
            .english: "Notifications",
            .chinese: "通知"
        ],
        .notifPush: [
            .russian: "Push-уведомления",
            .english: "Push notifications",
            .chinese: "推送通知"
        ],
        .notifPushSubtitle: [
            .russian: "Получать уведомления о событиях",
            .english: "Receive event notifications",
            .chinese: "接收事件通知"
        ],
        .notifSounds: [
            .russian: "Звуки уведомлений",
            .english: "Notification sounds",
            .chinese: "通知声音"
        ],
        .notifSoundsSubtitle: [
            .russian: "Воспроизводить звук при уведомлении",
            .english: "Play sound on notification",
            .chinese: "收到通知时播放声音"
        ],
        .notifFriendsOnline: [
            .russian: "Друзья онлайн",
            .english: "Friends online",
            .chinese: "好友在线"
        ],
        .notifFriendsOnlineSubtitle: [
            .russian: "Уведомлять когда друзья заходят в сеть",
            .english: "Notify when friends come online",
            .chinese: "好友上线时通知"
        ],
        .notifNewRooms: [
            .russian: "Новые комнаты",
            .english: "New rooms",
            .chinese: "新房间"
        ],
        .notifNewRoomsSubtitle: [
            .russian: "Уведомлять о новых публичных комнатах",
            .english: "Notify about new public rooms",
            .chinese: "通知新公共房间"
        ],

        // Privacy settings
        .privacyTitle: [
            .russian: "Конфиденциальность",
            .english: "Privacy",
            .chinese: "隐私"
        ],
        .privacyProfileVisibility: [
            .russian: "Видимость профиля",
            .english: "Profile visibility",
            .chinese: "个人资料可见性"
        ],
        .privacyProfileVisibilitySubtitle: [
            .russian: "Другие пользователи могут видеть ваш профиль",
            .english: "Others can see your profile",
            .chinese: "其他人可以查看您的个人资料"
        ],
        .privacyOnlineStatus: [
            .russian: "Онлайн-статус",
            .english: "Online status",
            .chinese: "在线状态"
        ],
        .privacyOnlineStatusSubtitle: [
            .russian: "Показывать когда вы в сети",
            .english: "Show when you're online",
            .chinese: "显示您在线的时间"
        ],
        .privacyReadReceipts: [
            .russian: "Отчёты о прочтении",
            .english: "Read receipts",
            .chinese: "已读回执"
        ],
        .privacyReadReceiptsSubtitle: [
            .russian: "Показывать прочитанные сообщения",
            .english: "Show read messages",
            .chinese: "显示已读消息"
        ],
        .privacyClearCache: [
            .russian: "Очистить кэш",
            .english: "Clear cache",
            .chinese: "清除缓存"
        ],
        .privacyClearCacheSubtitle: [
            .russian: "Удалить временные данные",
            .english: "Remove temporary data",
            .chinese: "删除临时数据"
        ],
        .privacyInfo: [
            .russian: "Данные хранятся локально на вашем устройстве. Мы не передаём вашу личную информацию третьим лицам.",
            .english: "Data is stored locally on your device. We don't share your personal information with third parties.",
            .chinese: "数据存储在您的设备本地。我们不会与第三方共享您的个人信息。"
        ],

        // Paywall
        .paywallTitle: [
            .russian: "SyncWatch Premium",
            .english: "SyncWatch Premium",
            .chinese: "SyncWatch Premium"
        ],
        .paywallTagline: [
            .russian: "Без рекламы. Без ограничений. Полный контроль.",
            .english: "No ads. No limits. Full control.",
            .chinese: "无广告。无限制。完全掌控。"
        ],
        .paywallRestore: [
            .russian: "Восстановить покупки",
            .english: "Restore purchases",
            .chinese: "恢复购买"
        ],
        .paywallSelectPlan: [
            .russian: "Выберите план",
            .english: "Choose a plan",
            .chinese: "选择方案"
        ],
        .paywallSubscribe: [
            .russian: "Подписаться",
            .english: "Subscribe",
            .chinese: "订阅"
        ],
        .paywallFeatureAdShield: [
            .russian: "Рекламный щит для друзей",
            .english: "Ad shield for friends",
            .chinese: "好友广告屏蔽"
        ],
        .paywallFeatureAdShieldSub: [
            .russian: "Создайте комнату — никто из гостей не увидит рекламу",
            .english: "Create a room — none of the guests will see ads",
            .chinese: "创建房间——所有嘉宾都不会看到广告"
        ],
        .paywallFeature4K: [
            .russian: "Разрешение 2K / 4K",
            .english: "2K / 4K resolution",
            .chinese: "2K / 4K 分辨率"
        ],
        .paywallFeature4KSub: [
            .russian: "Максимальное качество видео для ваших комнат",
            .english: "Maximum video quality for your rooms",
            .chinese: "房间的最高画质"
        ],
        .paywallFeatureThemes: [
            .russian: "Темы оформления комнат",
            .english: "Room themes",
            .chinese: "房间主题"
        ],
        .paywallFeatureThemesSub: [
            .russian: "Кастомные градиенты чата и неоновые рамки плеера",
            .english: "Custom chat gradients and neon player frames",
            .chinese: "自定义聊天渐变和霓虹播放器边框"
        ],
        .paywallFeatureNick: [
            .russian: "Оформление ника",
            .english: "Nickname styling",
            .chinese: "昵称样式"
        ],
        .paywallFeatureNickSub: [
            .russian: "Градиентные цвета ника в чате и бегущей строке",
            .english: "Gradient nickname colors in chat and ticker",
            .chinese: "聊天和滚动条中的渐变昵称"
        ],
        .paywallFeatureAvatar: [
            .russian: "Рамки аватара",
            .english: "Avatar frames",
            .chinese: "头像边框"
        ],
        .paywallFeatureAvatarSub: [
            .russian: "Неоновые, золотые и анимированные обводки",
            .english: "Neon, gold and animated borders",
            .chinese: "霓虹、金色和动态边框"
        ],
        .paywallMonth1: [
            .russian: "1 месяц",
            .english: "1 month",
            .chinese: "1 个月"
        ],
        .paywallMonth3: [
            .russian: "3 месяца",
            .english: "3 months",
            .chinese: "3 个月"
        ],
        .paywallMonth12: [
            .russian: "12 месяцев",
            .english: "12 months",
            .chinese: "12 个月"
        ],

        // Friends extras
        .friendsAlreadyFriends: [
            .russian: "✓ Друзья",
            .english: "✓ Friends",
            .chinese: "✓ 好友"
        ],

        // Chat extras
        .chatBlockMessageWithName: [
            .russian: "Вы больше не будете видеть сообщения от «%@».",
            .english: "You will no longer see messages from \"%@\".",
            .chinese: "您将不再看到\"%@\"的消息。"
        ],

        // YouTube search
        .searchTitle: [
            .russian: "Поиск YouTube",
            .english: "YouTube search",
            .chinese: "YouTube 搜索"
        ],
        .searchPlaceholder: [
            .russian: "Введите название ролика...",
            .english: "Type a video title...",
            .chinese: "输入视频标题..."
        ],
        .searchButton: [
            .russian: "Искать",
            .english: "Search",
            .chinese: "搜索"
        ],
        .searchEmpty: [
            .russian: "Введите запрос и нажмите «Искать»",
            .english: "Type a query and press Search",
            .chinese: "输入关键词并点击搜索"
        ],
        .searchHint: [
            .russian: "Найдём ролик вместе",
            .english: "Let's find a video together",
            .chinese: "一起找视频吧"
        ],
        .searchError: [
            .russian: "Поиск не удался. Попробуйте ещё раз.",
            .english: "Search failed. Try again.",
            .chinese: "搜索失败。请重试。"
        ],
        .searchUseThis: [
            .russian: "Выбрать этот ролик",
            .english: "Use this video",
            .chinese: "使用此视频"
        ],

        // Home extras
        .homeNoRoomsEmpty: [
            .russian: "Создай комнату и пригласи друзей!",
            .english: "Create a room and invite friends!",
            .chinese: "创建房间并邀请好友！"
        ],
        .homeNoResults: [
            .russian: "Комнаты не найдены",
            .english: "No rooms found",
            .chinese: "未找到房间"
        ],
        .homeNoResultsHint: [
            .russian: "Попробуй другой запрос",
            .english: "Try another search",
            .chinese: "尝试其他搜索"
        ],

        // M19: Groups
        .groupsEmpty: [
            .russian: "Пока нет бесед",
            .english: "No chats yet",
            .chinese: "暂无会话"
        ],
        .groupsEmptySubtitle: [
            .russian: "Создай групповой чат с друзьями — как в Telegram",
            .english: "Start a group chat with friends",
            .chinese: "与好友创建群聊"
        ],
        .groupsCreate: [
            .russian: "Создать беседу",
            .english: "New chat",
            .chinese: "新建会话"
        ],
        .groupsNoMessages: [
            .russian: "Нет сообщений",
            .english: "No messages",
            .chinese: "暂无消息"
        ],
        .groupsAddFriendsHint: [
            .russian: "Сначала добавь друзей — их можно будет позвать в беседу",
            .english: "Add friends first — invite them to a chat",
            .chinese: "先添加好友，再邀请入会话"
        ],
        .groupsPhotoUnavailable: [
            .russian: "Фото недоступно",
            .english: "Photo unavailable",
            .chinese: "照片不可用"
        ],
        // M19: Inbox
        .inboxAllRead: [
            .russian: "Всё прочитано",
            .english: "All caught up",
            .chinese: "全部已读"
        ],
        .inboxEmptySubtitle: [
            .russian: "Новые сообщения и события появятся здесь",
            .english: "New messages and events will appear here",
            .chinese: "新消息和事件将显示在此"
        ],
        .inboxUnreadMessages: [
            .russian: "Непрочитанные сообщения",
            .english: "Unread messages",
            .chinese: "未读消息"
        ],
        .inboxOpenFriendsHint: [
            .russian: "Открой вкладку «Друзья» → «Чаты»",
            .english: "Open Friends → Chats tab",
            .chinese: "打开好友→聊天选项卡"
        ],
        // M19: Queue
        .queueMutedLabel: [
            .russian: "Мут от ИИ-модератора:",
            .english: "AI muted you:",
            .chinese: "AI禁言："
        ],
        .queueLabel: [
            .russian: "Очередь",
            .english: "Queue",
            .chinese: "队列"
        ],
        // M19: Room setup
        .roomPassword: [
            .russian: "Пароль комнаты",
            .english: "Room password",
            .chinese: "房间密码"
        ],
        .roomCapacityUpsell: [
            .russian: "Нужно больше мест? С Plink+ — до",
            .english: "Need more seats? Plink+ — up to",
            .chinese: "需要更多席位？Plink+ — 最多"
        ],
        .roomCustomThemes: [
            .russian: "Кастомные темы комнаты",
            .english: "Custom room themes",
            .chinese: "自定义房间主题"
        ],
        .roomThemesSubtitle: [
            .russian: "Живой фон чата, оформление плеера, рамки — только с Плинк+",
            .english: "Live chat bg, player skin, frames — Plink+ only",
            .chinese: "实时聊天背景、播放器皮肤、边框—仅Plink+"
        ],
        .roomWithTheme: [
            .russian: "С рамкой плеера + живой фон чата",
            .english: "With player frame + live chat bg",
            .chinese: "含播放器边框+实时聊天背景"
        ],
        .roomStandardTheme: [
            .russian: "Стандартное оформление",
            .english: "Standard theme",
            .chinese: "标准主题"
        ],
        // M19: Home extras
        .homeNowTogether: [
            .russian: "Сейчас вместе",
            .english: "Watching now",
            .chinese: "正在一起观看"
        ],
        .homeAll: [
            .russian: "Все",
            .english: "All",
            .chinese: "全部"
        ],
        .homeVideoPlaceholder: [
            .russian: "Видео, сервис или комната",
            .english: "Video, service or room",
            .chinese: "视频、服务或房间"
        ],
        .homePopular: [
            .russian: "Популярное",
            .english: "Popular",
            .chinese: "热门"
        ],
        .homeQuickRoom: [
            .russian: "Быстрая комната",
            .english: "Quick room",
            .chinese: "快速房间"
        ],
        .homeScheduleSession: [
            .russian: "Запланировать сеанс",
            .english: "Schedule session",
            .chinese: "安排会话"
        ],
        .homeWatchLaterLabel: [
            .russian: "Посмотреть позже",
            .english: "Watch later",
            .chinese: "稍后观看"
        ],
        .homeRecommendations: [
            .russian: "Рекомендации",
            .english: "Recommendations",
            .chinese: "推荐"
        ],
        .homeLive: [
            .russian: "LIVE",
            .english: "LIVE",
            .chinese: "直播"
        ],
        .homeHostLabel: [
            .russian: "Хост:",
            .english: "Host:",
            .chinese: "主持人："
        ],
        .homeContinueWatching: [
            .russian: "ПРОДОЛЖИТЬ ПРОСМОТР",
            .english: "CONTINUE WATCHING",
            .chinese: "继续观看"
        ],
        .homeTimeLeft: [
            .russian: "Осталось",
            .english: "Left",
            .chinese: "剩余"
        ],
        // M20: Network
        .offlineTitle: [
            .russian: "Нет сети",
            .english: "No internet",
            .chinese: "无网络"
        ],
        .offlineRetry: [
            .russian: "Повторить",
            .english: "Retry",
            .chinese: "重试"
        ],
        .connectionLost: [
            .russian: "Связь потеряна",
            .english: "Connection lost",
            .chinese: "连接已断开"
        ],
        .msgSending: [
            .russian: "Отправка…",
            .english: "Sending…",
            .chinese: "发送中…"
        ],
        // M19: Paywall
        .plusTagline: [
            .russian: "Темы, реакции и больше друзей. Базовая синхронизация остаётся одинаково быстрой для всех.",
            .english: "Themes, reactions and more friends. Core sync stays equally fast for everyone.",
            .chinese: "主题、反应和更多好友。基本同步对所有人同样快。"
        ],
        .plusBenefitPremiumReactions: [
            .russian: "Премиум-реакции",
            .english: "Premium reactions",
            .chinese: "高级反应"
        ],
        .plusBenefitCustomEmoji: [
            .russian: "Кастомные эмодзи",
            .english: "Custom emoji",
            .chinese: "自定义表情"
        ],
        .plusBenefitAiPriority: [
            .russian: "Приоритет в очереди ИИ",
            .english: "AI queue priority",
            .chinese: "AI队列优先"
        ],
        .plusBenefitLiveThemes: [
            .russian: "Живые темы и кино-баблы",
            .english: "Live themes and cine-bubbles",
            .chinese: "动态主题和电影气泡"
        ],
        .plusBenefitAvatarFrames: [
            .russian: "Кастомные рамки аватара",
            .english: "Custom avatar frames",
            .chinese: "自定义头像边框"
        ],
        .plusBenefitCapacity20: [
            .russian: "20 участников вместо 10",
            .english: "20 members instead of 10",
            .chinese: "20人而非10人"
        ],
        .plusBenefitVideoFilters: [
            .russian: "Видео-фильтры",
            .english: "Video filters",
            .chinese: "视频滤镜"
        ],
        .plusBenefitCineBubbles: [
            .russian: "Кино-баблы и живые темы",
            .english: "Cine-bubbles and live themes",
            .chinese: "电影气泡和动态主题"
        ]
    ]
}

// MARK: - View Helper
extension View {
    /// Доступ к локализации из любого View.
    var L: LocalizationManager { LocalizationManager.shared }
}
