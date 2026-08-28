import Foundation

final class NowPlayingArbiter {
    struct Output: Equatable {
        var state: NowPlayingState?
        var source: NowPlayingSource?
    }

    struct Config {

        var switchDebounce: TimeInterval = 1.5

        var emptyGrace: TimeInterval = 3.0

        var arcSnapshotLifetime: TimeInterval = 6.0
    }

    private let config: Config
    private let now: () -> Date

    private var mediaRemoteState: NowPlayingState?
    private var arcState: NowPlayingState?
    private var arcSampledAt: Date?
    private var artworkMemory = NowPlayingArtworkMemory()

    private var authority: NowPlayingSource?
    private var lastSwitchAt: Date?
    private var lastGoodState: NowPlayingState?
    private var lastGoodSource: NowPlayingSource?
    private var graceStartedAt: Date?

    init(config: Config = Config(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    private(set) var currentOutput = Output(state: nil, source: nil)

    @discardableResult
    func ingestMediaRemote(_ state: NowPlayingState?) -> Output {
        mediaRemoteState = state.flatMap(withRememberedArtwork)
        return evaluate()
    }

    @discardableResult
    func ingestArc(_ snapshot: NowPlayingState?) -> Output {
        if let snapshot = snapshot.flatMap(withRememberedArtwork) {
            arcState = snapshot
            arcSampledAt = now()
        } else {
            arcState = nil
            arcSampledAt = nil
        }
        return evaluate()
    }

    @discardableResult
    func tick() -> Output {
        evaluate()
    }

    private func withRememberedArtwork(_ state: NowPlayingState) -> NowPlayingState? {
        guard !state.isEmpty else { return nil }
        artworkMemory.remember(state)
        return artworkMemory.restoring(state)
    }

    private func evaluate() -> Output {
        let moment = now()

        if let sampledAt = arcSampledAt,
           moment.timeIntervalSince(sampledAt) > config.arcSnapshotLifetime {
            arcState = nil
            arcSampledAt = nil
        }

        let candidate = pickAuthority(at: moment)

        if let candidate {
            let switched = applyAuthorityIfAllowed(candidate, at: moment)
            if switched || authority == candidate.source {
                graceStartedAt = nil
                lastGoodState = candidate.state
                lastGoodSource = candidate.source
                currentOutput = Output(state: candidate.state, source: candidate.source)
                return currentOutput
            }

            currentOutput = Output(state: lastGoodState, source: lastGoodSource)
            return currentOutput
        }

        if let lastGoodState {
            if graceStartedAt == nil {
                graceStartedAt = moment
                Log.nowPlaying.info("now-playing grace started (all sources empty)")
            }
            if let started = graceStartedAt,
               moment.timeIntervalSince(started) <= config.emptyGrace {
                currentOutput = Output(state: lastGoodState, source: lastGoodSource)
                return currentOutput
            }
            Log.nowPlaying.info("now-playing grace expired — Nothing Playing")
            self.lastGoodState = nil
            lastGoodSource = nil
        }
        authority = nil
        currentOutput = Output(state: nil, source: nil)
        return currentOutput
    }

    private struct Candidate {
        var state: NowPlayingState
        var source: NowPlayingSource
    }

    private func pickAuthority(at moment: Date) -> Candidate? {
        if let mediaRemoteState {
            return Candidate(state: mediaRemoteState, source: .mediaRemote)
        }
        if let arcState {
            return Candidate(state: arcState, source: .arcBrowser)
        }
        return nil
    }

    private func applyAuthorityIfAllowed(_ candidate: Candidate, at moment: Date) -> Bool {
        guard authority != candidate.source else { return true }

        if candidate.source != .mediaRemote,
           let lastSwitchAt,
           moment.timeIntervalSince(lastSwitchAt) < config.switchDebounce,
           authority != nil {
            return false
        }

        let previous = authority?.rawValue ?? "none"
        authority = candidate.source
        lastSwitchAt = moment
        Log.nowPlaying.info(
            "now-playing authority changed \(previous, privacy: .public) → \(candidate.source.rawValue, privacy: .public)"
        )
        return true
    }
}
