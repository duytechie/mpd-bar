import Foundation

public enum PlaybackState: String, Sendable, Equatable {
    case playing = "play"
    case paused = "pause"
    case stopped = "stop"
    case unknown
}

public struct MPDSong: Sendable, Equatable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let file: String?

    public init(title: String, artist: String?, album: String?, file: String?) {
        self.title = title
        self.artist = artist
        self.album = album
        self.file = file
    }

    public var displayTitle: String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(artist) — \(title)"
    }
}

public struct MPDSnapshot: Sendable, Equatable {
    public let state: PlaybackState
    public let song: MPDSong?
    public let elapsed: TimeInterval?
    public let duration: TimeInterval?
    public let volume: Int?

    public init(
        state: PlaybackState,
        song: MPDSong?,
        elapsed: TimeInterval?,
        duration: TimeInterval?,
        volume: Int?
    ) {
        self.state = state
        self.song = song
        self.elapsed = elapsed
        self.duration = duration
        self.volume = volume
    }
}

public enum MPDResponseParser {
    public static func fields(from lines: [String]) -> [String: String] {
        var result: [String: String] = [:]

        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator])
            let valueStart = line.index(after: separator)
            result[key] = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
        }

        return result
    }

    public static func snapshot(status: [String: String], song: [String: String]) -> MPDSnapshot {
        let state = PlaybackState(rawValue: status["state"] ?? "") ?? .unknown
        let songTitle = song["Title"] ?? song["Name"] ?? song["file"].map {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
        }

        let currentSong = songTitle.map {
            MPDSong(
                title: $0,
                artist: song["Artist"] ?? song["AlbumArtist"],
                album: song["Album"],
                file: song["file"]
            )
        }

        return MPDSnapshot(
            state: state,
            song: currentSong,
            elapsed: status["elapsed"].flatMap(TimeInterval.init),
            duration: status["duration"].flatMap(TimeInterval.init),
            volume: status["volume"].flatMap(Int.init)
        )
    }
}
