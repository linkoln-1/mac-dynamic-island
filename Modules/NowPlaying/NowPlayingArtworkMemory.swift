import AppKit

struct NowPlayingArtworkMemory {
    private struct Entry {
        var key: String
        var state: NowPlayingState
    }

    private var entries: [Entry] = []
    private let capacity: Int

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    mutating func remember(_ state: NowPlayingState) {
        guard !state.isEmpty, let artwork = state.artwork else { return }
        let key = Self.key(for: state)
        entries.removeAll { $0.key == key }
        var stored = state
        stored.artwork = artwork
        entries.append(Entry(key: key, state: stored))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func artwork(for state: NowPlayingState) -> NSImage? {
        guard !state.isEmpty else { return nil }
        let key = Self.key(for: state)
        if let exact = entries.last(where: { $0.key == key }) {
            return exact.state.artwork
        }
        return entries.last(where: { MediaItemIdentity.matches($0.state, state) })?.state.artwork
    }

    func restoring(_ state: NowPlayingState) -> NowPlayingState {
        guard state.artwork == nil, let remembered = artwork(for: state) else { return state }
        var restored = state
        restored.artwork = remembered
        return restored
    }

    private static func key(for state: NowPlayingState) -> String {
        MediaItemIdentity.key(title: state.title, artist: state.artist, duration: state.duration)
    }
}
