// Plink/Features/WatchRoom/ChatComposerState.swift — Commit Group 4
//
// Pure, testable state for WatchChatComposer. Extracted from the View to
// enable unit testing without constructing a full WatchRoomModel (which
// has too many dependencies — RealtimeClient, PlaybackCoordinator, etc.).
//
// Responsibilities:
//   - text: the raw input buffer (bound to TextField)
//   - cursor: UTF16 offset for cursor positioning (used for emoji insertion
//     at cursor, future message editing, and @-mention completion)
//   - trimmedText: whitespace-trimmed version used for canSend check
//   - canSend(connected:): pure function — true iff trimmed non-empty AND
//     connected
//   - insert(atCursor:): inserts a string at the cursor position, advances
//     the cursor past the insertion, returns the new state
//   - clearAfterSend(): resets text and cursor to empty
//
// UTF16 offsets are used (not Character offsets) because SwiftUI's
// TextField cursor position APIs work in UTF16. This matches NSTextView,
// UITextField, and JavaScript's Selection API conventions.
//
// Length cap: 2000 characters (matches backend ChatSendSchema in
// plink-backend/src/realtime/schemas.ts — chat.send rejects >2000 chars).

import Foundation

@MainActor
struct ChatComposerState: Equatable, Sendable {
    /// Raw input text (may have leading/trailing whitespace).
    var text: String = ""

    /// UTF16 offset of the cursor within `text`. 0 = before first char,
    /// text.utf16.count = after last char. Maintained alongside `text`
    /// so emoji insertion / mention completion can position correctly.
    var cursor: Int = 0

    /// Maximum allowed message length. Matches backend ChatSendSchema.
    static let maxLength = 2000

    /// Whitespace-trimmed text. Used for canSend and for the actual
    /// outgoing message payload.
    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True iff the trimmed text is non-empty AND the connection is up.
    /// Pure function — no side effects, safe to call from tests.
    func canSend(connected: Bool) -> Bool {
        connected && !trimmedText.isEmpty
    }

    /// True iff the trimmed text exceeds the length cap. UI uses this to
    /// show a "Message too long" hint and disable send.
    var isOverLength: Bool {
        trimmedText.count > Self.maxLength
    }

    /// Insert a string at the cursor position. Advances the cursor past
    /// the insertion. Used by:
    ///   - emoji picker (insert emoji glyph)
    ///   - mention picker (insert @username)
    ///   - future GIPHY sticker insertion
    ///
    /// If the resulting text would exceed maxLength, the insertion is
    /// truncated to fit.
    @discardableResult
    mutating func insertAtCursor(_ insertion: String) -> String {
        guard !insertion.isEmpty else { return "" }

        let utf16 = text.utf16
        let safeCursor = min(max(0, cursor), utf16.count)

        // Convert UTF16 offset to String.Index for the actual splice.
        guard let idx = utf16.index(utf16.startIndex, offsetBy: safeCursor, limitedBy: utf16.endIndex) else {
            return ""
        }
        let swiftIndex = String.Index(idx, within: text) ?? text.endIndex

        // Truncate insertion if it would exceed maxLength.
        let remainingCapacity = max(0, Self.maxLength - text.count)
        let truncated = String(insertion.prefix(remainingCapacity))
        guard !truncated.isEmpty else { return "" }

        text.insert(contentsOf: truncated, at: swiftIndex)
        // Advance cursor by the inserted UTF16 length.
        cursor = safeCursor + truncated.utf16.count

        return truncated
    }

    /// Clear text and reset cursor. Called after a successful send.
    mutating func clearAfterSend() {
        text = ""
        cursor = 0
    }

    /// Replace the entire text and move cursor to the end. Used for
    /// draft restoration and future message editing.
    mutating func setText(_ newText: String) {
        let truncated = String(newText.prefix(Self.maxLength))
        text = truncated
        cursor = truncated.utf16.count
    }
}
