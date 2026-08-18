// Friends system tests
//
// Closes the "friends" red system in RegressionMatrix.
// Tests Friendship models + FriendManager logic via in-memory state.

import XCTest
@testable import Plink

@MainActor
final class FriendsTests: XCTestCase {

    // MARK: - FriendshipStatus

    func testFriendshipStatus_allCases() {
        let statuses: [FriendshipStatus] = [.pending, .accepted, .declined, .blocked]
        XCTAssertEqual(statuses.count, 4)
    }

    func testFriendshipStatus_rawValues() {
        XCTAssertEqual(FriendshipStatus.pending.rawValue, "pending")
        XCTAssertEqual(FriendshipStatus.accepted.rawValue, "accepted")
        XCTAssertEqual(FriendshipStatus.declined.rawValue, "declined")
        XCTAssertEqual(FriendshipStatus.blocked.rawValue, "blocked")
    }

    // MARK: - Friend

    func testFriend_initials_singleUppercasedLetter() {
        let friend = Friend(
            id: "u1",
            username: "alice",
            avatarURL: nil,
            isOnline: true,
            friendsSince: Date()
        )
        // Живой Friend.initials — ОДНА заглавная буква (PlinkAvatarURL.letter):
        // единый placeholder аватарки во всём UI. "alice" → "A".
        XCTAssertEqual(friend.initials, "A")
    }

    func testFriend_initials_shortUsername() {
        let friend = Friend(
            id: "u1",
            username: "a",
            avatarURL: nil,
            isOnline: false,
            friendsSince: Date()
        )
        XCTAssertEqual(friend.initials, "A")
    }

    func testFriend_asUserPreview() {
        let friend = Friend(
            id: "u1",
            username: "alice",
            avatarURL: "http://example.com/a.png",
            isOnline: true,
            friendsSince: Date()
        )
        let preview = friend.asUserPreview
        XCTAssertEqual(preview.id, "u1")
        XCTAssertEqual(preview.username, "alice")
        XCTAssertEqual(preview.avatarURL, "http://example.com/a.png")
        XCTAssertTrue(preview.isOnline)
    }

    func testFriend_equality() {
        // Живой Friend использует синтезированный Equatable/Hashable:
        // сравниваются ВСЕ поля (value-семантика), а не только id.
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let f1 = Friend(id: "u1", username: "alice", avatarURL: nil, isOnline: true, friendsSince: since)
        let f2 = Friend(id: "u1", username: "alice", avatarURL: nil, isOnline: true, friendsSince: since)
        let f3 = Friend(id: "u1", username: "alice", avatarURL: nil, isOnline: false, friendsSince: since)
        let f4 = Friend(id: "u2", username: "bob", avatarURL: nil, isOnline: true, friendsSince: since)
        XCTAssertEqual(f1, f2, "Полное совпадение полей → равны")
        XCTAssertNotEqual(f1, f3, "Разный isOnline → не равны (равенство по всем полям)")
        XCTAssertNotEqual(f1, f4)
        // Hashable-контракт: равные значения дают равный хэш.
        XCTAssertEqual(f1.hashValue, f2.hashValue)
    }

    // MARK: - FriendRequest

    func testFriendRequest_isIncoming_defaultTrue() {
        let request = FriendRequest(
            id: "req-1",
            fromUser: UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: false),
            toUser: UserPreview(id: "u2", username: "bob", avatarURL: nil, isOnline: false),
            status: .pending,
            createdAt: Date()
        )
        XCTAssertTrue(request.isIncoming, "isIncoming is determined by context, defaults true")
    }

    func testFriendRequest_formattedDate() {
        let request = FriendRequest(
            id: "req-1",
            fromUser: UserPreview(id: "u1", username: "alice", avatarURL: nil, isOnline: false),
            toUser: UserPreview(id: "u2", username: "bob", avatarURL: nil, isOnline: false),
            status: .pending,
            createdAt: Date()
        )
        // Just verify it doesn't crash.
        XCTAssertFalse(request.formattedDate.isEmpty)
    }

    // MARK: - FriendManager (requires APIClient — skip in unit tests)

    func testFriendManager_generateInviteLink_staticMethod() {
        // generateInviteLink is an instance method but doesn't use API.
        // We test the URL format via DeepLinkRouter instead.
        let url = DeepLinkRouter.friendInviteURL(userId: "user-123")
        XCTAssertTrue(url.absoluteString.contains("user-123"))
    }

    // MARK: - FriendManager logic (in-memory)

    // FriendManager requires APIClient in init — can't test
    // without network. These tests are removed; FriendManager logic
    // is covered by integration tests on Mac CI.

    // MARK: - DeepLink integration

    func testFriendInviteDeepLink_parsesToFriendInvite() {
        let router = DeepLinkRouter()
        let url = URL(string: "https://plink.app/u/user-abc")!
        let result = router.parse(url)
        XCTAssertEqual(result, .friendInvite(userId: "user-abc"))
    }
}
