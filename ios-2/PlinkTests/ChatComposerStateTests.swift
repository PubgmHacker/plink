// PlinkTests/ChatComposerStateTests.swift — Commit Group 4
//
// Unit tests for ChatComposerState — the pure, testable state extracted
// from WatchChatComposer. No UI, no model dependencies, no async.
//
// Coverage:
//   - canSend truth table (connected × empty/whitespace/non-empty)
//   - trimmedText strips leading/trailing/newlines
//   - isOverLength triggers at 2001 chars, not 2000
//   - insertAtCursor at beginning / middle / end / out-of-bounds
//   - insertAtCursor truncates when exceeding maxLength
//   - insertAtCursor handles empty insertion as no-op
//   - clearAfterSend resets both text and cursor
//   - setText moves cursor to end, truncates at maxLength
//   - UTF16 cursor advancement for multi-byte emoji (✅, 🇺🇸)
//   - Round-trip: type + insert + clear + type again

import XCTest
@testable import Plink

@MainActor
final class ChatComposerStateTests: XCTestCase {

    // MARK: - canSend

    func testCanSend_falseWhenDisconnectedEvenWithText() {
        var state = ChatComposerState()
        state.text = "hello"
        XCTAssertFalse(state.canSend(connected: false),
                       "canSend must be false when disconnected")
    }

    func testCanSend_falseWhenConnectedButEmpty() {
        var state = ChatComposerState()
        state.text = ""
        XCTAssertFalse(state.canSend(connected: true),
                       "canSend must be false when text is empty")
    }

    func testCanSend_falseWhenConnectedButOnlyWhitespace() {
        var state = ChatComposerState()
        state.text = "   \n\t  "
        XCTAssertFalse(state.canSend(connected: true),
                       "canSend must be false when text is only whitespace")
    }

    func testCanSend_trueWhenConnectedAndNonEmpty() {
        var state = ChatComposerState()
        state.text = "  hello world  "
        XCTAssertTrue(state.canSend(connected: true),
                      "canSend must be true when connected and text has non-whitespace content")
    }

    // MARK: - trimmedText

    func testTrimmedText_stripsLeadingTrailingWhitespace() {
        var state = ChatComposerState()
        state.text = "  hello  "
        XCTAssertEqual(state.trimmedText, "hello")
    }

    func testTrimmedText_stripsNewlinesAndTabs() {
        var state = ChatComposerState()
        state.text = "\n\thello world\n\t"
        XCTAssertEqual(state.trimmedText, "hello world")
    }

    func testTrimmedText_preservesInternalWhitespace() {
        var state = ChatComposerState()
        state.text = "  hello   world  "
        XCTAssertEqual(state.trimmedText, "hello   world",
                       "Internal whitespace runs must be preserved")
    }

    // MARK: - isOverLength

    func testIsOverLength_falseAtExactMaxLength() {
        var state = ChatComposerState()
        state.text = String(repeating: "a", count: ChatComposerState.maxLength)
        XCTAssertFalse(state.isOverLength,
                       "Text at exactly maxLength must not be over length")
    }

    func testIsOverLength_trueAtMaxLengthPlusOne() {
        var state = ChatComposerState()
        state.text = String(repeating: "a", count: ChatComposerState.maxLength + 1)
        XCTAssertTrue(state.isOverLength,
                      "Text at maxLength+1 must be over length")
    }

    func testIsOverLength_usesTrimmedTextNotRaw() {
        var state = ChatComposerState()
        // 1998 chars + 4 spaces leading + 4 trailing = 2006 raw, 1998 trimmed
        state.text = "    " + String(repeating: "a", count: ChatComposerState.maxLength - 2) + "    "
        XCTAssertFalse(state.isOverLength,
                       "isOverLength must use trimmedText, not raw text")
    }

    // MARK: - insertAtCursor

    func testInsertAtCursor_atBeginning() {
        var state = ChatComposerState()
        state.text = "world"
        state.cursor = 0

        let inserted = state.insertAtCursor("hello ")

        XCTAssertEqual(inserted, "hello ")
        XCTAssertEqual(state.text, "hello world")
        XCTAssertEqual(state.cursor, 6,
                       "Cursor must advance past insertion (6 UTF16 units)")
    }

    func testInsertAtCursor_inMiddle() {
        var state = ChatComposerState()
        state.text = "hello world"
        state.cursor = 5  // after "hello"

        let inserted = state.insertAtCursor(" there")

        XCTAssertEqual(inserted, " there")
        XCTAssertEqual(state.text, "hello there world")
        XCTAssertEqual(state.cursor, 11,
                       "Cursor must advance past insertion (5 + 6 = 11)")
    }

    func testInsertAtCursor_atEnd() {
        var state = ChatComposerState()
        state.text = "hello"
        state.cursor = 5

        let inserted = state.insertAtCursor(" world")

        XCTAssertEqual(inserted, " world")
        XCTAssertEqual(state.text, "hello world")
        XCTAssertEqual(state.cursor, 11)
    }

    func testInsertAtCursor_outOfBoundsCursorClampsToEnd() {
        var state = ChatComposerState()
        state.text = "hello"
        state.cursor = 999  // out of bounds

        let inserted = state.insertAtCursor("!")

        XCTAssertEqual(inserted, "!")
        XCTAssertEqual(state.text, "hello!")
        XCTAssertEqual(state.cursor, 6,
                       "Out-of-bounds cursor must clamp to end, then advance")
    }

    func testInsertAtCursor_negativeCursorClampsToZero() {
        var state = ChatComposerState()
        state.text = "hello"
        state.cursor = -5

        let inserted = state.insertAtCursor("X")

        XCTAssertEqual(inserted, "X")
        XCTAssertEqual(state.text, "Xhello")
        XCTAssertEqual(state.cursor, 1)
    }

    func testInsertAtCursor_emptyInsertionIsNoOp() {
        var state = ChatComposerState()
        state.text = "hello"
        state.cursor = 3

        let inserted = state.insertAtCursor("")

        XCTAssertEqual(inserted, "")
        XCTAssertEqual(state.text, "hello")
        XCTAssertEqual(state.cursor, 3,
                       "Empty insertion must not change cursor")
    }

    // MARK: - insertAtCursor with multi-byte characters

    func testInsertAtCursor_emojiAdvancesCursorByUTF16Units() {
        var state = ChatComposerState()
        state.text = "hello "
        state.cursor = 6

        // ✅ is U+2705 — 1 UTF16 unit
        let inserted = state.insertAtCursor("✅")

        XCTAssertEqual(inserted, "✅")
        XCTAssertEqual(state.text, "hello ✅")
        XCTAssertEqual(state.cursor, 7,
                       "Single-codepoint emoji must advance cursor by 1 UTF16 unit")
    }

    func testInsertAtCursor_regionalIndicatorEmojiAdvancesByTwoUTF16Units() {
        var state = ChatComposerState()
        state.text = "flag: "
        state.cursor = 6

        // 🇺🇸 is U+1F1FA U+1F1F8 — 2 UTF16 units (a surrogate pair... actually
        // two regional indicators, each in BMP, so 2 UTF16 units total)
        let inserted = state.insertAtCursor("🇺🇸")

        XCTAssertEqual(inserted, "🇺🇸")
        XCTAssertEqual(state.text, "flag: 🇺🇸")
        XCTAssertEqual(state.cursor, 8,
                       "Regional indicator pair must advance cursor by 2 UTF16 units")
    }

    // MARK: - insertAtCursor length cap

    func testInsertAtCursor_truncatesWhenExceedingMaxLength() {
        var state = ChatComposerState()
        state.text = String(repeating: "a", count: ChatComposerState.maxLength - 3)
        state.cursor = state.text.count

        // Try to insert 10 chars; only 3 fit.
        let inserted = state.insertAtCursor("0123456789")

        XCTAssertEqual(inserted, "012",
                       "Insertion must be truncated to remaining capacity")
        XCTAssertEqual(state.text.count, ChatComposerState.maxLength)
        XCTAssertFalse(state.isOverLength,
                       "After truncation, text must be exactly at maxLength, not over")
    }

    func testInsertAtCursor_returnsEmptyWhenNoCapacity() {
        var state = ChatComposerState()
        state.text = String(repeating: "a", count: ChatComposerState.maxLength)
        state.cursor = state.text.count

        let inserted = state.insertAtCursor("X")

        XCTAssertEqual(inserted, "",
                       "Insertion at full capacity must return empty string")
        XCTAssertEqual(state.text.count, ChatComposerState.maxLength,
                       "Text must be unchanged when no capacity")
    }

    // MARK: - clearAfterSend

    func testClearAfterSend_resetsTextAndCursor() {
        var state = ChatComposerState()
        state.text = "hello world"
        state.cursor = 5

        state.clearAfterSend()

        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursor, 0)
        XCTAssertFalse(state.canSend(connected: true),
                       "After clear, canSend must be false even when connected")
    }

    // MARK: - setText

    func testSetText_movesCursorToEnd() {
        var state = ChatComposerState()
        state.text = "old"
        state.cursor = 1

        state.setText("new text")

        XCTAssertEqual(state.text, "new text")
        XCTAssertEqual(state.cursor, 8,
                       "setText must move cursor to end of new text")
    }

    func testSetText_truncatesAtMaxLength() {
        var state = ChatComposerState()

        let longText = String(repeating: "a", count: ChatComposerState.maxLength + 100)
        state.setText(longText)

        XCTAssertEqual(state.text.count, ChatComposerState.maxLength,
                       "setText must truncate to maxLength")
        XCTAssertEqual(state.cursor, ChatComposerState.maxLength,
                       "Cursor must be at end of truncated text")
        XCTAssertFalse(state.isOverLength)
    }

    func testSetText_emptyStringResetsCursorToZero() {
        var state = ChatComposerState()
        state.text = "hello"
        state.cursor = 3

        state.setText("")

        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursor, 0)
    }

    // MARK: - Round-trip

    func testRoundTrip_typeInsertClearTypeAgain() {
        var state = ChatComposerState()

        // Type "hello"
        state.setText("hello")
        XCTAssertEqual(state.text, "hello")
        XCTAssertEqual(state.cursor, 5)

        // Insert emoji at end
        state.insertAtCursor(" ✅")
        XCTAssertEqual(state.text, "hello ✅")
        XCTAssertEqual(state.cursor, 7)

        // Send + clear
        XCTAssertTrue(state.canSend(connected: true))
        state.clearAfterSend()
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursor, 0)

        // Type again
        state.setText("next message")
        XCTAssertEqual(state.text, "next message")
        XCTAssertTrue(state.canSend(connected: true))
    }

    // MARK: - Initial state

    func testInitialState_isEmpty() {
        let state = ChatComposerState()
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursor, 0)
        XCTAssertFalse(state.canSend(connected: true))
        XCTAssertFalse(state.isOverLength)
    }
}
