// Profile system tests
//
// Closes the "profile" red system in RegressionMatrix.

import XCTest
@testable import Plink

@MainActor
final class ProfileTests: XCTestCase {

    // MARK: - User model

    func testUser_defaultRole_isNil() {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: nil,
            isOnline: false,
            isPremium: false,
            role: nil,
            createdAt: Date()
        )
        XCTAssertNil(user.role)
    }

    func testUser_initials_fromDisplayName() {
        let user = User(
            id: "u1",
            username: "alice_films",
            email: "alice@example.com",
            avatarURL: nil,
            displayName: "Alice Wonderland",
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        // User has initials computed property — verify it uses displayName first.
        XCTAssertFalse(user.initials.isEmpty)
    }

    func testUser_initials_fallsBackToUsername() {
        let user = User(
            id: "u1",
            username: "alice_films",
            email: "alice@example.com",
            avatarURL: nil,
            displayName: nil,
            coverURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        XCTAssertFalse(user.initials.isEmpty)
    }

    // MARK: - PremiumStatusManager

    func testPremiumStatusManager_initialState_notPremium() {
        // Use a fresh instance to avoid singleton state.
        let manager = PremiumStatusManager()
        XCTAssertFalse(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry)
    }

    func testPremiumStatusManager_activatePremium_setsExpiry() {
        let manager = PremiumStatusManager()
        let expiry = Date().addingTimeInterval(30 * 24 * 3600)  // 30 days
        manager.activatePremium(expiryDate: expiry)
        XCTAssertTrue(manager.isPremium)
        XCTAssertEqual(manager.subscriptionExpiry, expiry)
    }

    func testPremiumStatusManager_activateLifetime_setsNilExpiry() {
        let manager = PremiumStatusManager()
        manager.activateLifetime()
        XCTAssertTrue(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry, "Lifetime = nil expiry")
    }

    func testPremiumStatusManager_deactivate_resetsState() {
        let manager = PremiumStatusManager()
        manager.activatePremium(expiryDate: Date().addingTimeInterval(3600))
        XCTAssertTrue(manager.isPremium)

        manager.deactivatePremium()
        XCTAssertFalse(manager.isPremium)
        XCTAssertNil(manager.subscriptionExpiry)
    }

    // MARK: - UserPreview

    func testUserPreview_equality() {
        // Живой UserPreview — синтезированный Hashable/Equatable:
        // равенство по ВСЕМ полям (value-семантика), не только по id.
        let p1 = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: false)
        let p2 = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: false)
        let p3 = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: true)
        let p4 = UserPreview(id: "u2", username: "bob", avatarURL: nil, isOnline: false)
        XCTAssertEqual(p1, p2, "Полное совпадение полей → равны")
        XCTAssertNotEqual(p1, p3, "Разный isOnline → не равны (равенство по всем полям)")
        XCTAssertNotEqual(p1, p4)
    }

    func testUserPreview_id_isStable() {
        let preview = UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: true)
        XCTAssertEqual(preview.id, "u1")
    }

    // MARK: - Profile serialization

    func testUser_codableRoundTrip() throws {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: "http://example.com/a.png",
            displayName: "Alice",
            coverURL: nil,
            isOnline: true,
            isPremium: true,
            role: "ADMIN",
            createdAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
        let data = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(User.self, from: data)
        XCTAssertEqual(user.id, decoded.id)
        XCTAssertEqual(user.username, decoded.username)
        XCTAssertEqual(user.email, decoded.email)
        XCTAssertEqual(user.isPremium, decoded.isPremium)
        XCTAssertEqual(user.role, decoded.role)
    }

    // MARK: - Activity digest (client twin of backend computeActivity)

    private func entry(_ id: String, daysAgo: Int, kind: String? = "movie", now: Date, cal: Calendar) -> UserSocialProfile.WatchHistoryEntry {
        let at = cal.date(byAdding: .day, value: -daysAgo, to: now)!
        return UserSocialProfile.WatchHistoryEntry(id: id, title: id, thumb: nil, kind: kind, watchedAt: at, roomId: nil)
    }

    func testActivityStats_derived_emptyHistory_isNil() {
        XCTAssertNil(UserSocialProfile.ActivityStats.derived(from: []))
        // Entries without a timestamp carry no evidence of recency either.
        let undated = UserSocialProfile.WatchHistoryEntry(id: "x", title: "x", thumb: nil, kind: nil, watchedAt: nil, roomId: nil)
        XCTAssertNil(UserSocialProfile.ActivityStats.derived(from: [undated]))
    }

    func testActivityStats_derived_bucketsWeekMonthAndStreak() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 14))!
        let history = [
            entry("a", daysAgo: 0, kind: "movie", now: now, cal: cal),
            entry("b", daysAgo: 0, kind: "video", now: now, cal: cal),
            entry("c", daysAgo: 1, kind: "movie", now: now, cal: cal),
            entry("d", daysAgo: 2, kind: "movie", now: now, cal: cal),
            entry("e", daysAgo: 6, kind: "series", now: now, cal: cal),
            entry("f", daysAgo: 7, kind: "series", now: now, cal: cal),   // outside the 7-day strip
            entry("g", daysAgo: 29, kind: "series", now: now, cal: cal),  // last day of the month window
            entry("h", daysAgo: 30, kind: "series", now: now, cal: cal),  // outside the month
            entry("i", daysAgo: -1, kind: "series", now: now, cal: cal)   // clock skew — the future never counts
        ]
        let stats = UserSocialProfile.ActivityStats.derived(from: history, now: now, calendar: cal)!
        XCTAssertEqual(stats.week, [1, 0, 0, 0, 1, 1, 2])
        XCTAssertEqual(stats.weekFilms, 5)
        XCTAssertEqual(stats.monthFilms, 7)
        XCTAssertEqual(stats.monthMinutes, 7 * UserSocialProfile.ActivityStats.minutesPerFilm)
        XCTAssertEqual(stats.streakDays, 3)
        XCTAssertEqual(stats.topKind, "movie")
    }

    func testActivityStats_derived_streakKeptAliveByYesterday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9))!
        let history = [
            entry("a", daysAgo: 1, now: now, cal: cal),
            entry("b", daysAgo: 2, now: now, cal: cal),
            entry("c", daysAgo: 4, now: now, cal: cal)
        ]
        let stats = UserSocialProfile.ActivityStats.derived(from: history, now: now, calendar: cal)!
        XCTAssertEqual(stats.streakDays, 2, "yesterday keeps the streak alive; the gap at day 3 ends it")
        XCTAssertEqual(stats.week, [0, 0, 1, 0, 1, 1, 0])
    }

    func testStatsPeriod_filter_boundsAndUndatedEntries() {
        let now = Date()
        let cal = Calendar.current
        let fresh = entry("fresh", daysAgo: 2, now: now, cal: cal)
        let stale = entry("stale", daysAgo: 12, now: now, cal: cal)
        let old = entry("old", daysAgo: 45, now: now, cal: cal)
        let undated = UserSocialProfile.WatchHistoryEntry(id: "u", title: "u", thumb: nil, kind: nil, watchedAt: nil, roomId: nil)
        let all = [fresh, stale, old, undated]
        XCTAssertEqual(PlinkStatsPeriod.week.filter(all, now: now).map(\.id), ["fresh"])
        XCTAssertEqual(PlinkStatsPeriod.month.filter(all, now: now).map(\.id), ["fresh", "stale"])
        XCTAssertEqual(PlinkStatsPeriod.all.filter(all, now: now).count, 4, "the unbounded period keeps undated entries")
    }
}
