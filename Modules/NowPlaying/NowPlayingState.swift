import AppKit

struct NowPlayingState: Equatable {
    var bundleIdentifier: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false

    var duration: TimeInterval = 0

    var elapsedTime: TimeInterval = 0

    var elapsedTimestamp: Date = Date()

    var playbackRate: Double = 0

    var artwork: NSImage?

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }

    func position(at now: Date = Date()) -> TimeInterval {
        let raw: TimeInterval
        if isPlaying {
            raw = elapsedTime + playbackRate * now.timeIntervalSince(elapsedTimestamp)
        } else {
            raw = elapsedTime
        }
        guard duration > 0 else { return max(0, raw) }
        return min(max(0, raw), duration)
    }

    func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return position(at: now) / duration
    }

    static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.duration == rhs.duration
            && lhs.elapsedTime == rhs.elapsedTime
            && lhs.elapsedTimestamp == rhs.elapsedTimestamp
            && lhs.playbackRate == rhs.playbackRate
            && lhs.artwork === rhs.artwork
    }
}
