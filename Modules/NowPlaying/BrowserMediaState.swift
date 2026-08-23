import Foundation

enum NowPlayingSource: String, Equatable {
    case mediaRemote
    case arcBrowser
}

struct BrowserMediaSnapshot: Equatable {
    var tabID: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var hasMedia: Bool = false
    var isMuted: Bool = false
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Double = 0
    var sampledAt: Date = Date()

    func nowPlayingState() -> NowPlayingState {
        var state = NowPlayingState()
        state.bundleIdentifier = ArcBrowser.bundleID
        state.title = title
        state.artist = artist
        state.album = album
        state.isPlaying = isPlaying
        state.duration = duration
        state.elapsedTime = elapsed
        state.elapsedTimestamp = sampledAt
        state.playbackRate = isPlaying ? max(playbackRate, 0.01) : 0
        return state
    }
}

enum ArcBrowser {
    static let bundleID = "company.thebrowser.Browser"
}

enum BrowserMediaNormalizer {

    struct TabProbe: Decodable {
        struct Element: Decodable {
            var paused: Bool
            var ended: Bool
            var ct: Double?
            var dur: Double?
            var rs: Int
            var muted: Bool?
            var rate: Double?
        }
        struct Meta: Decodable {
            var title: String?
            var artist: String?
            var album: String?
        }
        var media: [Element]
        var meta: Meta?
        var dt: String?
    }

    static func normalize(
        tabID: String,
        probeJSON: Data,
        sampledAt: Date = Date()
    ) -> BrowserMediaSnapshot? {
        guard let probe = try? JSONDecoder().decode(TabProbe.self, from: probeJSON) else {
            return nil
        }

        let usable = probe.media.filter { $0.rs > 0 && !$0.ended }
        guard let element = usable.min(by: { rank($0) < rank($1) }) else {
            return probe.media.isEmpty ? nil : emptySnapshot(tabID: tabID, probe: probe, sampledAt: sampledAt)
        }

        var snapshot = BrowserMediaSnapshot()
        snapshot.tabID = tabID
        snapshot.hasMedia = true
        snapshot.sampledAt = sampledAt
        snapshot.isPlaying = !element.paused && !element.ended
        snapshot.isMuted = element.muted ?? false
        snapshot.elapsed = sanitize(element.ct)
        snapshot.duration = sanitize(element.dur)
        snapshot.playbackRate = sanitize(element.rate, fallback: 1)

        let metaTitle = probe.meta?.title?.trimmingCharacters(in: .whitespaces) ?? ""
        if !metaTitle.isEmpty {
            snapshot.title = metaTitle
            snapshot.artist = probe.meta?.artist ?? ""
            snapshot.album = probe.meta?.album ?? ""
        } else {
            snapshot.title = Self.titleFromDocument(probe.dt ?? "")
        }
        guard !snapshot.title.isEmpty else { return nil }
        return snapshot
    }

    private static func emptySnapshot(
        tabID: String, probe: TabProbe, sampledAt: Date
    ) -> BrowserMediaSnapshot? {
        var snapshot = BrowserMediaSnapshot()
        snapshot.tabID = tabID
        snapshot.hasMedia = true
        snapshot.isPlaying = false
        snapshot.sampledAt = sampledAt
        snapshot.title = probe.meta?.title ?? Self.titleFromDocument(probe.dt ?? "")
        snapshot.artist = probe.meta?.artist ?? ""
        return snapshot.title.isEmpty ? nil : snapshot
    }

    private static func rank(_ element: TabProbe.Element) -> Int {
        var value = 0
        if element.paused { value += 2 }
        if element.muted == true { value += 1 }
        return value
    }

    private static func sanitize(_ value: Double?, fallback: Double = 0) -> Double {
        guard let value, value.isFinite, value >= 0 else { return fallback }
        return value
    }

    static func titleFromDocument(_ documentTitle: String) -> String {
        let trimmed = documentTitle.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: " - YouTube", options: [.backwards]) else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}

enum BrowserCandidateRanking {

    static func best(
        of snapshots: [BrowserMediaSnapshot],
        currentTabID: String?
    ) -> BrowserMediaSnapshot? {
        snapshots.enumerated().min { lhs, rhs in
            score(lhs.element, index: lhs.offset, currentTabID: currentTabID)
                < score(rhs.element, index: rhs.offset, currentTabID: currentTabID)
        }?.element
    }

    private static func score(
        _ snapshot: BrowserMediaSnapshot, index: Int, currentTabID: String?
    ) -> Int {
        var value = index
        if !snapshot.isPlaying { value += 1000 }
        if snapshot.isMuted { value += 100 }
        if let currentTabID, snapshot.tabID == currentTabID { value -= 500 }
        return value
    }
}

enum MediaItemIdentity {
    static func key(title: String, artist: String, duration: TimeInterval) -> String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let bucket = duration > 0 ? Int((duration / 2).rounded()) : 0
        return "\(normalizedTitle)|\(normalizedArtist)|\(bucket)"
    }

    static func matches(_ lhs: NowPlayingState, _ rhs: NowPlayingState) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if key(title: lhs.title, artist: lhs.artist, duration: lhs.duration)
            == key(title: rhs.title, artist: rhs.artist, duration: rhs.duration) {
            return true
        }

        return lhs.title.lowercased() == rhs.title.lowercased() && !lhs.title.isEmpty
    }
}
