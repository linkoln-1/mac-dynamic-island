import Combine
import Foundation

@MainActor
final class NowPlayingCoordinator: NowPlayingProviding {
    private let primary: NowPlayingProviding
    private let arc = ArcBrowserNowPlayingProvider()
    private let arbiter: NowPlayingArbiter

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    private var primaryCancellable: AnyCancellable?
    private var tickTimer: Timer?
    private var probeTask: Task<Void, Never>?
    private var lastProbeAt: Date?

    @Published private(set) var source: NowPlayingSource?

    @Published private(set) var canSkip = true

    private static let activeProbeInterval: TimeInterval = 1.5
    private static let idleProbeInterval: TimeInterval = 5.0

    nonisolated init(primary: NowPlayingProviding, arbiter: NowPlayingArbiter = NowPlayingArbiter()) {
        self.primary = primary
        self.arbiter = arbiter
    }

    var statePublisher: AnyPublisher<NowPlayingState?, Never> {
        subject.eraseToAnyPublisher()
    }

    var canSeek: Bool {
        source == .arcBrowser ? true : primary.canSeek
    }

    func start() {
        primaryCancellable = primary.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let hadContent = self.subject.value?.isEmpty == false
                self.publish(self.arbiter.ingestMediaRemote(state))

                if state?.isEmpty != false, hadContent {
                    self.probeArcSoon(force: true)
                }
            }
        primary.start()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        primary.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        probeTask?.cancel()
        primaryCancellable = nil
    }

    private func heartbeat() {
        publish(arbiter.tick())
        guard source != .mediaRemote else { return }
        let interval = source == .arcBrowser
            ? Self.activeProbeInterval
            : Self.idleProbeInterval
        if lastProbeAt.map({ Date().timeIntervalSince($0) >= interval }) ?? true {
            probeArcSoon(force: false)
        }
    }

    private func probeArcSoon(force: Bool) {
        guard probeTask == nil || force else { return }
        probeTask?.cancel()
        lastProbeAt = Date()
        probeTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.arc.probe()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.ingestArcOutcome(outcome)
                self.probeTask = nil
            }
        }
    }

    private func ingestArcOutcome(_ outcome: ArcProbeOutcome) {
        switch outcome {
        case .snapshot(let snapshot):
            publish(arbiter.ingestArc(snapshot.nowPlayingState()))
        case .noMedia, .arcNotRunning:
            publish(arbiter.ingestArc(nil))
        case .permissionDenied, .failed:

            publish(arbiter.tick())
        }
    }

    private func publish(_ output: NowPlayingArbiter.Output) {
        if subject.value != output.state {
            subject.send(output.state)
        }
        if source != output.source {
            source = output.source
            canSkip = output.source != .arcBrowser
        }
    }

    func play() {
        routeTransport(arc: { await $0.play() }, primary: { $0.play() })
    }

    func pause() {
        routeTransport(arc: { await $0.pause() }, primary: { $0.pause() })
    }

    func togglePlayPause() {
        routeTransport(arc: { await $0.togglePlayPause() }, primary: { $0.togglePlayPause() })
    }

    func nextTrack() { primary.nextTrack() }
    func previousTrack() { primary.previousTrack() }

    func seek(to seconds: TimeInterval) {
        routeTransport(
            arc: { await $0.seek(to: seconds) },
            primary: { $0.seek(to: seconds) }
        )
    }

    private func routeTransport(
        arc arcCommand: @escaping (ArcBrowserNowPlayingProvider) async -> Void,
        primary primaryCommand: (NowPlayingProviding) -> Void
    ) {
        if source == .arcBrowser {
            let arc = self.arc
            Task { await arcCommand(arc) }
        } else {
            primaryCommand(primary)
        }
    }
}
