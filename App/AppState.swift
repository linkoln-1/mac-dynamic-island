import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let islandState: IslandState
    let windowController: IslandWindowController

    private(set) var isStarted = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let state = IslandState()
        islandState = state
        windowController = IslandWindowController(state: state)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        ScreenshotsModuleController.shared.activate()

        NowPlayingViewModel.shared.startIfNeeded()

        AgentsModuleController.shared.activateIfEnabled()

        Publishers.CombineLatest(
            NowPlayingViewModel.shared.$state.map { !$0.isEmpty }.removeDuplicates(),
            AgentsModuleController.shared.store.$sessions
                .map { _ in AgentsModuleController.shared.store.compactSummary }
                .removeDuplicates()
        )
        .sink { [weak self] hasMedia, agentSummary in
            guard let self else { return }
            let hasAgents = !agentSummary.isEmpty
            self.islandState.compactWidthBonus =
                (hasMedia && hasAgents) ? CompactSurfaceView.microZoneWidth * 2 : 0
            self.islandState.compactShowsAgentsOnly = !hasMedia && hasAgents
            self.islandState.setCompactAvailable(hasMedia || hasAgents)
        }
        .store(in: &cancellables)

        windowController.start()

        #if DEBUG

        if ProcessInfo.processInfo.environment["PI_DEBUG_EXPAND"] == "1" {
            islandState.expand()
        }
        #endif
    }

    func stop() {
        guard isStarted else { return }
        ScreenshotsModuleController.shared.deactivate()
    }

    func openIsland() {
        start()
        islandState.expand()
    }
}
