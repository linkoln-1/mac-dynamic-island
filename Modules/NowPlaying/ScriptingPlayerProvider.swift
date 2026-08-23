import AppKit
import Combine

final class ScriptingPlayerProvider: NowPlayingProviding {
    private struct PlayerTarget {
        let bundleIdentifier: String
        let appName: String

        let durationDivisor: Double
        let supportsArtworkData: Bool
    }

    private static let targets = [
        PlayerTarget(bundleIdentifier: "com.spotify.client", appName: "Spotify",
                     durationDivisor: 1000, supportsArtworkData: false),
        PlayerTarget(bundleIdentifier: "com.apple.Music", appName: "Music",
                     durationDivisor: 1, supportsArtworkData: true),
    ]
    private static let pollInterval: TimeInterval = 2

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }
    let canSeek = true

    private let queue = DispatchQueue(label: "com.lincode.PersonalIsland.scripting-player")
    private var timer: DispatchSourceTimer?
    private var activeTarget: PlayerTarget?
    private var artworkTrackKey: String?
    private var artwork: NSImage?

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: Self.pollInterval)
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
            Log.nowPlaying.info("AppleScript fallback provider started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    deinit {
        timer?.cancel()
    }

    private func poll() {
        let runningTargets = Self.targets.filter { isRunning($0) }
        guard !runningTargets.isEmpty else {
            publish(nil, target: nil)
            return
        }
        var best: (PlayerTarget, NowPlayingState)?
        for target in runningTargets {
            guard let state = fetchState(from: target) else { continue }
            if state.isPlaying {
                best = (target, state)
                break
            }
            if best == nil { best = (target, state) }
        }
        if let (target, state) = best {
            publish(state, target: target)
        } else {
            publish(nil, target: nil)
        }
    }

    private func isRunning(_ target: PlayerTarget) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).isEmpty
    }

    private func fetchState(from target: PlayerTarget) -> NowPlayingState? {
        let source = """
        tell application "\(target.appName)"
            try
                set t to current track
                return {player state is playing, name of t, artist of t, album of t, ¬
                    player position, duration of t}
            on error
                return {false, "", "", "", 0, 0}
            end try
        end tell
        """
        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
              descriptor.numberOfItems == 6,
              let title = descriptor.atIndex(2)?.stringValue, !title.isEmpty
        else { return nil }

        var state = NowPlayingState()
        state.bundleIdentifier = target.bundleIdentifier
        state.title = title
        state.artist = descriptor.atIndex(3)?.stringValue ?? ""
        state.album = descriptor.atIndex(4)?.stringValue ?? ""
        state.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        state.elapsedTime = descriptor.atIndex(5)?.doubleValue ?? 0
        state.duration = (descriptor.atIndex(6)?.doubleValue ?? 0) / target.durationDivisor
        state.elapsedTimestamp = Date()
        state.playbackRate = state.isPlaying ? 1 : 0
        state.artwork = artworkImage(for: target, title: title, artist: state.artist)
        return state
    }

    private func artworkImage(for target: PlayerTarget, title: String, artist: String) -> NSImage? {
        let key = "\(target.bundleIdentifier)|\(title)|\(artist)"
        if key == artworkTrackKey { return artwork }
        artworkTrackKey = key
        artwork = nil
        guard target.supportsArtworkData else { return nil }
        let source = "tell application \"\(target.appName)\" to get data of artwork 1 of current track"
        var errorInfo: NSDictionary?
        if let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
           case let data = descriptor.data, !data.isEmpty,
           let image = NSImage(data: data) {
            artwork = image
        }
        return artwork
    }

    private func publish(_ state: NowPlayingState?, target: PlayerTarget?) {
        activeTarget = target
        DispatchQueue.main.async { [weak self] in self?.subject.send(state) }
    }

    private func runCommand(_ verb: String) {
        queue.async { [weak self] in
            guard let self, let target = self.activeTarget ?? Self.targets.first(where: self.isRunning) else { return }
            let source = "tell application \"\(target.appName)\" to \(verb)"
            NSAppleScript(source: source)?.executeAndReturnError(nil)
            self.poll()
        }
    }

    func play() { runCommand("play") }
    func pause() { runCommand("pause") }
    func togglePlayPause() { runCommand("playpause") }
    func nextTrack() { runCommand("next track") }
    func previousTrack() { runCommand("previous track") }

    func seek(to seconds: TimeInterval) {
        runCommand("set player position to \(seconds)")
        if var current = subject.value {
            current.elapsedTime = seconds
            current.elapsedTimestamp = Date()
            DispatchQueue.main.async { [weak self] in self?.subject.send(current) }
        }
    }
}
