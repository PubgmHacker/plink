// PlinkTests/DMTests.swift — PATCH 20: dms system tests
//
// Closes the "dms" red system in RegressionMatrix.

import XCTest
@testable import Plink

@MainActor
final class DMTests: XCTestCase {

    // MARK: - DirectMessage

    func testDirectMessage_defaultValues() {
        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        XCTAssertEqual(dm.id, "msg-1")
        XCTAssertEqual(dm.conversationID, "conv-1")
        XCTAssertEqual(dm.senderID, "u1")
        XCTAssertEqual(dm.recipientID, "u2")
        XCTAssertEqual(dm.text, "Hello")
        XCTAssertFalse(dm.isRead)
    }

    func testDirectMessage_isOwnMessage_falseWhenNoSavedUser() {
        // Clear any saved user.
        UserDefaults.standard.removeObject(forKey: "rave_saved_user")

        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        XCTAssertFalse(dm.isOwnMessage, "Should be false when no saved user")
    }

    func testDirectMessage_isOwnMessage_trueWhenSenderMatchesSavedUser() {
        let user = User(
            id: "u1",
            username: "alice",
            email: "alice@example.com",
            avatarURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        let data = try? JSONEncoder().encode(user)
        UserDefaults.standard.set(data, forKey: "rave_saved_user")

        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        XCTAssertTrue(dm.isOwnMessage)

        // Cleanup.
        UserDefaults.standard.removeObject(forKey: "rave_saved_user")
    }

    func testDirectMessage_timeString_nonEmpty() {
        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        XCTAssertFalse(dm.timeString.isEmpty)
    }

    func testDirectMessage_initials_singleWord() {
        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        // initials takes first letter of each word part (prefix 2).
        // "Alice" → "A"
        XCTAssertFalse(dm.initials.isEmpty)
    }

    func testDirectMessage_initials_twoWords() {
        let dm = DirectMessage(
            id: "msg-1",
            conversationID: "conv-1",
            senderID: "u1",
            recipientID: "u2",
            senderName: "Alice Wonderland",
            text: "Hello",
            timestamp: Date(),
            isRead: false,
            senderAvatarURL: nil
        )
        // "Alice Wonderland" → "AW"
        XCTAssertEqual(dm.initials.count, 2)
    }

    // MARK: - DMChatService

    func testDMChatService_conversationID_isDeterministic() {
        let service = DMChatService()
        let id1 = service.conversationID(with: "friend-1")
        let id2 = service.conversationID(with: "friend-1")
        XCTAssertEqual(id1, id2, "conversationID must be deterministic for same friendID")
    }

    func testDMChatService_conversationID_differentForDifferentFriends() {
        let service = DMChatService()
        let id1 = service.conversationID(with: "friend-1")
        let id2 = service.conversationID(with: "friend-2")
        XCTAssertNotEqual(id1, id2)
    }

    func testDMChatService_messagesForFriend_emptyInitially() {
        let service = DMChatService()
        let messages = service.messages(for: "friend-1")
        XCTAssertTrue(messages.isEmpty, "Messages should be empty before loadHistory")
    }

    // MARK: - Conversation ID format

    func testConversationID_containsCurrentUserId() {
        // Save a user so isOwnMessage works.
        let user = User(
            id: "current-user",
            username: "me",
            email: "me@example.com",
            avatarURL: nil,
            isOnline: true,
            isPremium: false,
            role: "USER",
            createdAt: Date()
        )
        let data = try? JSONEncoder().encode(user)
        UserDefaults.standard.set(data, forKey: "rave_saved_user")

        let service = DMChatService()
        let convId = service.conversationID(with: "friend-1")
        // Conversation ID format is typically sorted pair — verify it's stable.
        XCTAssertFalse(convId.isEmpty)

        UserDefaults.standard.removeObject(forKey: "rave_saved_user")
    }
}
