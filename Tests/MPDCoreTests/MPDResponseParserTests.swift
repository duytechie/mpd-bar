import XCTest
@testable import MPDCore

final class MPDResponseParserTests: XCTestCase {
    func testParsesFieldsAndValuesContainingColons() {
        let fields = MPDResponseParser.fields(from: [
            "state: play",
            "file: Radio: Station/stream",
            "ignored line"
        ])

        XCTAssertEqual(fields["state"], "play")
        XCTAssertEqual(fields["file"], "Radio: Station/stream")
    }

    func testBuildsSnapshotFromStatusAndSong() {
        let snapshot = MPDResponseParser.snapshot(
            status: [
                "state": "pause",
                "elapsed": "42.5",
                "duration": "180.0",
                "volume": "73"
            ],
            song: [
                "Artist": "Boards of Canada",
                "Title": "Dayvan Cowboy",
                "Album": "The Campfire Headphase"
            ]
        )

        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.song?.displayTitle, "Boards of Canada — Dayvan Cowboy")
        XCTAssertEqual(snapshot.elapsed, 42.5)
        XCTAssertEqual(snapshot.duration, 180)
        XCTAssertEqual(snapshot.volume, 73)
    }

    func testUsesFilenameWhenMetadataHasNoTitle() {
        let snapshot = MPDResponseParser.snapshot(
            status: ["state": "play"],
            song: ["file": "Music/Ambient/track-01.flac"]
        )

        XCTAssertEqual(snapshot.song?.title, "track-01")
    }
}
