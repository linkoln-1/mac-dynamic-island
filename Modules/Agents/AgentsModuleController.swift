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

    private static let enabledDefaultsKey = "agentMonitoringEnabled"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        store.transitions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.notifications.handle(transition)
            }
            .store(in: &cancellables)
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
            self?.store.ingest(event)
        }
        receiver.start()
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
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    private func bundledHelperURL() -> URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/personal-island-agent-hook")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
