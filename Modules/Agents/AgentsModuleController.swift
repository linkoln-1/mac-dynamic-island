import AppKit
import Combine
import Foundation

@MainActor
final class AgentsModuleController: ObservableObject {
    static let shared = AgentsModuleController()

    let store = AgentStore()
    let notifications = AgentNotificationManager()
    private let receiver = AgentEventReceiver()
    private var installer = AgentHookInstaller()
    private var sweepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var isEnabled: Bool

    @Published var providerFilter: AgentProviderKind?
    @Published private(set) var health = AgentHookInstaller.Health(
        claudeInstalled: false, codexInstalled: false, helperInstalled: false
    )
    @Published private(set) var lastEnableError: String?
    @Published private(set) var highlightedSessionID: String?
    @Published private(set) var codexLocalHealth: CodexLocalSessionProvider.Health = .inactive

    private var codexProvider: CodexLocalSessionProvider?
    private var hookSeenCodexSessions: Set<String> = []

    private var highlightWork: DispatchWorkItem?
    private static let enabledDefaultsKey = "agentMonitoringEnabled"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        store.transitions
            .receive(on: DispatchQueue.main)
            .sink { transition in
                guard let event = AgentAttentionMapper.event(for: transition) else { return }
                AttentionStore.shared.publish(event)
            }
            .store(in: &cancellables)
        store.resolutions
            .receive(on: DispatchQueue.main)
            .sink { resolution in
                AttentionStore.shared.resolve(
                    dedupKey: AgentAttentionMapper.permissionDedupKey(
                        sessionID: resolution.session.id, cycleID: resolution.cycleID
                    )
                )
            }
            .store(in: &cancellables)
        AttentionStore.shared.notificationRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.notifications.post(item: item)
            }
            .store(in: &cancellables)
    }

    func navigateToSession(_ sessionID: String) {
        guard store.sessions[sessionID] != nil else { return }
        providerFilter = nil
        highlightedSessionID = sessionID
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.highlightedSessionID = nil
            self?.highlightWork = nil
        }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        NotificationCenter.default.post(
            name: .islandNavigateToModule, object: nil, userInfo: ["moduleID": "agents"]
        )
    }

    func activateIfEnabled() {
        guard isEnabled else { return }
        startRuntime()
        health = installer.health()
    }

    func enable() {
        lastEnableError = nil
        do {
            guard let bundled = bundledHelperURL() else {
                throw NSError(domain: "Agents", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "bundled hook helper missing from the app bundle",
                ])
            }
            try installer.installHelper(from: bundled)
            try installer.installClaudeHooks()
            try installer.installCodexHooks()
            isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
            startRuntime()
            notifications.requestAuthorizationIfNeeded()
            health = installer.health()
            Log.agentHooks.info("agent monitoring enabled")
        } catch {
            lastEnableError = error.localizedDescription
            Log.agentHooks.error("enable failed: \(error.localizedDescription, privacy: .public)")
        }
        health = installer.health()
    }

    func repair() { enable() }

    private func startRuntime() {
        receiver.onEvent = { [weak self] event in
            if event.provider == .codex {
                self?.hookSeenCodexSessions.insert(event.sessionID)
            }
            self?.store.ingest(event)
        }
        receiver.start()
        if codexProvider == nil {
            let provider = CodexLocalSessionProvider { [weak self] events in
                for event in events { self?.store.ingest(event) }
            }
            provider.isHookAuthority = { [weak self] sessionID in
                self?.hookSeenCodexSessions.contains(sessionID) ?? false
            }
            provider.start()
            codexProvider = provider
            codexLocalHealth = provider.health
        }
        if sweepTimer == nil {

            let timer = Timer(timeInterval: 10, repeats: true) { _ in
                Task { @MainActor in AgentsModuleController.shared.store.sweep() }
            }
            RunLoop.main.add(timer, forMode: .common)
            sweepTimer = timer
        }
    }

    func shutdown() {
        receiver.stop()
        codexProvider?.stop()
        codexProvider = nil
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    private func bundledHelperURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/personal-island-agent-hook")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
