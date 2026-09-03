// PlinkTests/RoomDecodingTests.swift
//
// A rooms list must survive one room whose media item this client cannot decode:
// that room lists as "no video yet" instead of blanking the whole list (and the
// "return to room" capsule with it).

import XCTest
@testable import Plink

final class RoomDecodingTests: XCTestCase {

    private let json = """
    [
      {"id":"r1","name":"Partial media","hostID":"u1","hostName":"Host","code":"AAAA11",
       "isActive":true,"privacy":"public",
       "mediaItem":{"id":"yt:abc","title":"Written by another client","service":"youtube",
                    "url":"https://youtu.be/abc","duration":120},
       "_count":{"participants":1}},
      {"id":"r2","name":"Full media","hostID":"u1","hostName":"Host","code":"BBBB22",
       "isActive":true,"privacy":"link",
       "mediaItem":{"id":"yt:def","title":"Complete","streamURL":"https://www.youtube.com/watch?v=def",
                    "duration":212,"mediaType":"video","source":"youtube","videoId":"def"},
       "_count":{"participants":2}},
      {"id":"r3","name":"No media","hostID":"u1","code":"CCCC33","mediaItem":null}
    ]
    """

    func testUndecodableMediaItemDoesNotDropTheRoom() throws {
        let rooms = try JSONDecoder().decode([Room].self, from: Data(json.utf8))
        XCTAssertEqual(rooms.map(\.id), ["r1", "r2", "r3"])

        XCTAssertNil(rooms[0].mediaItem, "a partial media item decodes as 'no video yet'")
        XCTAssertEqual(rooms[0].participantCount, 1)
        XCTAssertTrue(rooms[0].isActive)

        let full = try XCTUnwrap(rooms[1].mediaItem)
        XCTAssertEqual(full.source, .youtube)
        XCTAssertEqual(full.mediaType, .video)
        XCTAssertEqual(full.videoId, "def")
        XCTAssertEqual(rooms[1].participantCount, 2)
        XCTAssertEqual(rooms[1].privacy, .byLink)

        XCTAssertNil(rooms[2].mediaItem)
        XCTAssertEqual(rooms[2].participantCount, 0)
    }
}
