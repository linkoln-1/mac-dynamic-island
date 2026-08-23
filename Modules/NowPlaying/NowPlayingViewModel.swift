import AppKit
import Combine

@MainActor
final class NowPlayingViewModel: ObservableObject {
    static let shared = NowPlayingViewModel()

    struct ProviderFactory {
        var runAdapterTest: () async -> Bool
        var makeAdapter: (_ onPermanentFailure: @escaping () -> Void) -> NowPlayingProviding
        var makeFallback: () -> NowPlayingProviding
    }

    @Published private(set) var state = NowPlayingState()
    @Published private(set) var canSeek = false

    @Published private(set) var canSkip = true
    private(set) var isUsingFallback = false
    private(set) var isStarted = false

    private let factory: ProviderFactory
    private var provider: NowPlayingProviding?
    private var stateCancellable: AnyCancellable?
    private var capabilityCancellable: AnyCancellable?
    private var terminationObserver: NSObjectProtocol?

    init(factory: ProviderFactory? = nil) {
        self.factory = factory ?? .live

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.provider?.stop() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    @discardableResult
    func startIfNeeded() -> Task<Void, Never>? {
        guard !isStarted else { return nil }
        isStarted = true
        return Task { await self.activateProvider() }
    }

    func activateProvider() async {
        if await factory.runAdapterTest() {
            let adapter = factory.makeAdapter { [weak self] in
                Task { @MainActor in self?.switchToFallback() }
            }
            attach(adapter, isFallback: false)
        } else {
            attach(factory.makeFallback(), isFallback: true)
        }
    }

    func switchToFallback() {
        guard !isUsingFallback else { return }
        Log.nowPlaying.error("adapter provider failed permanently — switching to AppleScript fallback")
        provider?.stop()
        attach(factory.makeFallback(), isFallback: true)
    }

    private func attach(_ newProvider: NowPlayingProviding, isFallback: Bool) {
        isUsingFallback = isFallback
        provider = newProvider
        canSeek = newProvider.canSeek
        stateCancellable = newProvider.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState ?? NowPlayingState()
            }

        if let coordinator = newProvider as? NowPlayingCoordinator {
            capabilityCancellable = coordinator.$source
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak coordinator] _ in
                    guard let self, let coordinator else { return }
                    self.canSeek = coordinator.canSeek
                    self.canSkip = coordinator.canSkip
                }
        } else {
            capabilityCancellable = nil
            canSkip = true
        }
        newProvider.start()
        Log.nowPlaying.info(
            "Now Playing provider active: \(isFallback ? "AppleScript fallback" : "MediaRemote adapter", privacy: .public)"
        )
    }

    func togglePlayPause() { provider?.togglePlayPause() }
    func nextTrack() { provider?.nextTrack() }
    func previousTrack() { provider?.previousTrack() }

    func seek(to seconds: TimeInterval) {
        guard !state.isEmpty, canSeek else { return }
        provider?.seek(to: seconds)

        state.elapsedTime = state.duration > 0 ? min(max(0, seconds), state.duration) : max(0, seconds)
        state.elapsedTimestamp = Date()
    }
}

extension NowPlayingViewModel.ProviderFactory {

    static var live: Self {
        Self(
            runAdapterTest: {
                guard let paths = adapterPaths else {
                    Log.nowPlaying.error("adapter artifacts missing from bundle — using fallback")
                    return false
                }
                return await MediaRemoteAdapterProvider.runFunctionalTest(
                    scriptPath: paths.script, frameworkPath: paths.framework,
                    testClientPath: paths.testClient, timeout: 5
                )
            },
            makeAdapter: { onPermanentFailure in
                guard let paths = adapterPaths else {
                    return NowPlayingCoordinator(primary: ScriptingPlayerProvider())
                }
                let adapter = MediaRemoteAdapterProvider(
                    scriptPath: paths.script, frameworkPath: paths.framework,
                    testClientPath: paths.testClient
                )
                adapter.onPermanentFailure = onPermanentFailure

                return NowPlayingCoordinator(primary: adapter)
            },
            makeFallback: { NowPlayingCoordinator(primary: ScriptingPlayerProvider()) }
        )
    }

    private static var adapterPaths: (script: String, framework: String, testClient: String?)? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path,
              let frameworksDir = Bundle.main.privateFrameworksPath
        else { return nil }
        let framework = frameworksDir + "/MediaRemoteAdapter.framework"
        guard FileManager.default.fileExists(atPath: framework) else { return nil }
        let testClient = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path
        return (script, framework, testClient)
    }
}
