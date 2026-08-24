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

        islandState.livePolicy = { AppSettings.shared.hoverPolicy }
        islandState.hoverOpenProvider = { AppSettings.shared.hoverOpenEnabled }
        AttentionStore.shared.liveMaxAge = { AppSettings.shared.attentionRetentionDays * 86400 }
        AgentsModuleController.shared.store.liveFinishedRetention = {
            AppSettings.shared.agentAutoClearSeconds
        }
        ScreenshotsModuleController.shared.buffer.liveLimit = {
            AppSettings.shared.screenshotBufferLimit
        }

        ScreenshotsModuleController.shared.activate()

        ClipboardModuleController.shared.activate()

        NowPlayingViewModel.shared.startIfNeeded()

        AgentsModuleController.shared.activateIfEnabled()

        Publishers.CombineLatest3(
            NowPlayingViewModel.shared.$state.map { !$0.isEmpty }.removeDuplicates(),
            AgentsModuleController.shared.store.$sessions
                .map { _ in AgentsModuleController.shared.store.compactSummary }
                .removeDuplicates(),
            AttentionStore.shared.$items
                .map { _ in AttentionStore.shared.highPriorityUnreadCount }
                .removeDuplicates()
        )
        .sink { [weak self] hasMedia, agentSummary, highPriorityCount in
            guard let self else { return }
            let plan = CompactSurfacePlan.plan(
                hasMedia: hasMedia,
                hasAgentSummary: !agentSummary.isEmpty,
                highPriorityCount: highPriorityCount
            )
            self.islandState.compactWidthBonus =
                plan.showsMicroCluster ? CompactSurfaceView.microZoneWidth * 2 : 0
            self.islandState.compactShowsAgentsOnly = !plan.showsMedia && !plan.isEmpty
            self.islandState.setCompactAvailable(!plan.isEmpty)
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
        ClipboardModuleController.shared.deactivate()
    }

    func openIsland() {
        start()
        islandState.expand()
    }
}
