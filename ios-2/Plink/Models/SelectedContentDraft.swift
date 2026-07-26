// Plink/Models/SelectedContentDraft.swift — Brain Phase 4
//
// Typed intent for room creation. Replaces the loose `Bool createPresented`
// with a sum type that distinguishes:
//   - .chooseService — user tapped the persistent Create button (no content preselected)
//   - .selectedContent(draft) — user tapped a trending/hero video; RoomCreationView
//     opens RoomSetupView immediately with the draft pre-filled.
//
// Brain Phase 4 spec: trending tap must pre-fill RoomSetup, not just open
// the empty Create flow. Existing room cards still join the room.

import Foundation

/// A piece of content the user has selected to start a room with.
/// Sendable + Hashable so it can live in @State and cross actor boundaries.
struct SelectedContentDraft: Identifiable, Hashable, Sendable {
    let id: String
    let service: VideoService
    let contentURL: String
    let title: String
    let thumbnailURL: String?

    init(
        id: String,
        service: VideoService,
        contentURL: String,
        title: String,
        thumbnailURL: String?
    ) {
        self.id = id
        self.service = service
        self.contentURL = contentURL
        self.title = title
        self.thumbnailURL = thumbnailURL
    }
}

/// Sum type for the create-room intent.
/// `.chooseService` → start at service selection.
/// `.selectedContent` → skip to RoomSetup with the draft pre-filled.
enum CreateRoomIntent: Identifiable, Hashable {
    case chooseService
    case selectedContent(SelectedContentDraft)

    var id: String {
        switch self {
        case .chooseService:
            return "chooseService"
        case .selectedContent(let draft):
            return "content:\(draft.id)"
        }
    }
}
