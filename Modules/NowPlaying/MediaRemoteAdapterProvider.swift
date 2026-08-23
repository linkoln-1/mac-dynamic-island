import AppKit
import Combine

struct NDJSONLineBuffer {
    private var buffer = Data()
    private static let newline: UInt8 = 0x0A

    mutating func append(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: Self.newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

final class AdapterArtworkCache {
    private var images: [Int: NSImage] = [:]
    private var insertionOrder: [Int] = []
    private let capacity = 6

    func image(for data: Data) -> NSImage? {
        let key = data.hashValue
        if let cached = images[key] { return cached }
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        images[key] = image
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            images.removeValue(forKey: insertionOrder.removeFirst())
        }
        return image
    }
}

enum AdapterLineResult {

    case ignored

    case state(NowPlayingState?)
}

final class AdapterEventProcessor {
    private var merged: [String: Any] = [:]
    private var lastState: NowPlayingState?
    private let artworkCache = AdapterArtworkCache()
    private static let isoFormatter = ISO8601DateFormatter()

    func process(line: String) -> AdapterLineResult {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return .ignored }

        if object["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull {
                    merged.removeValue(forKey: key)
                } else {
                    merged[key] = value
                }
            }
        } else {
            merged = payload.filter { !($0.value is NSNull) }
        }
        let state = mapMergedPayload()
        lastState = state
        return .state(state)
    }

    private func mapMergedPayload() -> NowPlayingState? {
        guard let title = merged["title"] as? String, !title.isEmpty else { return nil }
        var state = NowPlayingState()

        state.bundleIdentifier = (merged["parentApplicationBundleIdentifier"] as? String)
            ?? (merged["bundleIdentifier"] as? String) ?? ""
        state.title = title
        state.artist = merged["artist"] as? String ?? ""
        state.album = merged["album"] as? String ?? ""
        state.isPlaying = merged["playing"] as? Bool ?? false
        state.duration = merged["duration"] as? Double ?? 0
        state.elapsedTime = merged["elapsedTime"] as? Double ?? 0
        state.elapsedTimestamp = (merged["timestamp"] as? String)
            .flatMap { Self.isoFormatter.date(from: $0) } ?? Date()
        state.playbackRate = merged["playbackRate"] as? Double ?? (state.isPlaying ? 1 : 0)
        if let base64 = merged["artworkData"] as? String,
           let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) {
            state.artwork = artworkCache.image(for: data)
        } else if let previous = lastState, previous.title == state.title, previous.artist == state.artist {
            state.artwork = previous.artwork
        }
        return state
    }
}

final class MediaRemoteAdapterProvider: NowPlayingProviding {
    private static let perlPath = "/usr/bin/perl"
    private static let maxRestartAttempts = 5
    private static let stableUptimeResetThreshold: TimeInterval = 60
    private static let maxRestartDelay: TimeInterval = 30

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }
    let canSeek = true

    var onPermanentFailure: (() -> Void)?

    private let scriptPath: String
    private let frameworkPath: String
    private let testClientPath: String?
    private let queue = DispatchQueue(label: "com.lincode.PersonalIsland.mediaremote-adapter")
    private var process: Process?
    private var lineBuffer = NDJSONLineBuffer()
    private var processor = AdapterEventProcessor()
    private var isStopped = false
    private var restartAttempts = 0
    private var processStartDate: Date?

    init(scriptPath: String, frameworkPath: String, testClientPath: String?) {
        self.scriptPath = scriptPath
        self.frameworkPath = frameworkPath
        self.testClientPath = testClientPath

        signal(SIGPIPE, SIG_IGN)
    }

    deinit {
        queue.sync { teardown() }
    }

    static func runFunctionalTestSync(
        scriptPath: String, frameworkPath: String, testClientPath: String?, timeout: TimeInterval
    ) -> Bool {
        guard let testClientPath else { return true }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: perlPath)
        process.arguments = [scriptPath, frameworkPath, testClientPath, "test"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        do { try process.run() } catch {
            Log.nowPlaying.error("adapter test failed to launch: \(error.localizedDescription)")
            return false
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            Log.nowPlaying.error("adapter test timed out after \(timeout, format: .fixed(precision: 0))s")
            process.terminationHandler = nil
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    static func runFunctionalTest(
        scriptPath: String, frameworkPath: String, testClientPath: String?, timeout: TimeInterval = 5
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runFunctionalTestSync(
                    scriptPath: scriptPath, frameworkPath: frameworkPath,
                    testClientPath: testClientPath, timeout: timeout
                ))
            }
        }
    }

    func start() {
        queue.async { [weak self] in self?.launchStream() }
    }

    func stop() {
        queue.async { [weak self] in self?.teardown() }
    }

    private func launchStream() {
        guard process == nil, !isStopped else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)

        process.arguments = [scriptPath, frameworkPath, "stream", "--debounce=100"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(chunk) }
        }
        process.terminationHandler = { [weak self] terminated in
            let status = terminated.terminationStatus
            self?.queue.async {
                guard let self else { return }
                if self.process === terminated { self.process = nil }
                self.handleStreamTermination(status: status)
            }
        }
        do {
            try process.run()
        } catch {
            Log.nowPlaying.error("adapter stream failed to launch: \(error.localizedDescription)")
            failPermanently()
            return
        }
        self.process = process
        processStartDate = Date()
        Log.nowPlaying.info("adapter stream started (pid \(process.processIdentifier))")
    }

    private func consume(_ chunk: Data) {
        for line in lineBuffer.append(chunk) {
            if case .state(let newState) = processor.process(line: line) {
                publish(newState)
            }
        }
    }

    private func handleStreamTermination(status: Int32) {
        guard !isStopped else { return }
        if let started = processStartDate,
           Date().timeIntervalSince(started) > Self.stableUptimeResetThreshold {
            restartAttempts = 0
        }
        restartAttempts += 1
        guard restartAttempts <= Self.maxRestartAttempts else {
            Log.nowPlaying.error("adapter stream died (status \(status)); restart budget exhausted")
            failPermanently()
            return
        }
        let delay = min(pow(2, Double(restartAttempts - 1)), Self.maxRestartDelay)
        Log.nowPlaying.error(
            "adapter stream exited (status \(status)); restart #\(self.restartAttempts) in \(delay, format: .fixed(precision: 0))s"
        )
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isStopped else { return }
            if status != 0 {

                let functional = Self.runFunctionalTestSync(
                    scriptPath: self.scriptPath, frameworkPath: self.frameworkPath,
                    testClientPath: self.testClientPath, timeout: 5
                )
                guard functional else {
                    self.failPermanently()
                    return
                }
            }
            self.launchStream()
        }
    }

    private func teardown() {
        isStopped = true
        guard let process else { return }
        self.process = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private func failPermanently() {
        isStopped = true
        publish(nil)
        DispatchQueue.main.async { [weak self] in self?.onPermanentFailure?() }
    }

    private func publish(_ state: NowPlayingState?) {
        DispatchQueue.main.async { [weak self] in self?.subject.send(state) }
    }

    private func runOneShot(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = [scriptPath, frameworkPath] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in }
        do { try process.run() } catch {
            Log.nowPlaying.error("adapter command \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
        }
    }

    func play() { runOneShot(["send", "0"]) }
    func pause() { runOneShot(["send", "1"]) }
    func togglePlayPause() { runOneShot(["send", "2"]) }
    func nextTrack() { runOneShot(["send", "4"]) }
    func previousTrack() { runOneShot(["send", "5"]) }

    func seek(to seconds: TimeInterval) {
        runOneShot(["seek", String(Int(seconds * 1_000_000))])

        let bundleID = subject.value?.bundleIdentifier
        let scriptSource: String? = switch bundleID {
        case "com.apple.Music": "tell application \"Music\" to set player position to \(seconds)"
        case "com.spotify.client": "tell application \"Spotify\" to set player position to \(seconds)"
        default: nil
        }
        if let scriptSource {
            DispatchQueue.global(qos: .userInitiated).async {
                NSAppleScript(source: scriptSource)?.executeAndReturnError(nil)
            }
        }

        if var current = subject.value {
            current.elapsedTime = seconds
            current.elapsedTimestamp = Date()
            publish(current)
        }
    }
}
