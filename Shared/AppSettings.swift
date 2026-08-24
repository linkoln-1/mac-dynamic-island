import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared: AppSettings = {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            let suite = "com.lincode.PersonalIsland.tests"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            return AppSettings(defaults: defaults)
        }
        return AppSettings()
    }()

    @Published var hoverOpenEnabled: Bool { didSet { save() } }
    @Published var hoverExpandDelay: Double { didSet { save() } }
    @Published var hoverCollapseGrace: Double { didSet { save() } }
    @Published var notifyFinished: Bool { didSet { save() } }
    @Published var notifyPermission: Bool { didSet { save() } }
    @Published var notifyFailed: Bool { didSet { save() } }
    @Published var notifyClaude: Bool { didSet { save() } }
    @Published var notifyCodex: Bool { didSet { save() } }
    @Published var agentAutoClearSeconds: Double { didSet { save() } }
    @Published var screenshotBufferLimit: Int { didSet { save() } }
    @Published var attentionRetentionDays: Double { didSet { save() } }
    @Published var moduleOrder: [String] { didSet { save() } }

    private let defaults: UserDefaults
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hoverOpenEnabled = defaults.object(forKey: "settings.hoverOpenEnabled") as? Bool ?? true
        hoverExpandDelay = defaults.object(forKey: "settings.hoverExpandDelay") as? Double ?? 0.2
        hoverCollapseGrace = defaults.object(forKey: "settings.hoverCollapseGrace") as? Double ?? 0.75
        notifyFinished = defaults.object(forKey: "settings.notifyFinished") as? Bool ?? true
        notifyPermission = defaults.object(forKey: "settings.notifyPermission") as? Bool ?? true
        notifyFailed = defaults.object(forKey: "settings.notifyFailed") as? Bool ?? true
        notifyClaude = defaults.object(forKey: "settings.notifyClaude") as? Bool ?? true
        notifyCodex = defaults.object(forKey: "settings.notifyCodex") as? Bool ?? true
        agentAutoClearSeconds = defaults.object(forKey: "settings.agentAutoClearSeconds") as? Double ?? 60
        screenshotBufferLimit = defaults.object(forKey: "settings.screenshotBufferLimit") as? Int ?? 30
        attentionRetentionDays = defaults.object(forKey: "settings.attentionRetentionDays") as? Double ?? 7
        moduleOrder = defaults.object(forKey: "settings.moduleOrder") as? [String] ?? []
        isLoading = false
    }

    func orderedModuleIDs(all: [String]) -> [String] {
        let known = moduleOrder.filter { all.contains($0) }
        let missing = all.filter { !known.contains($0) }
        return known + missing
    }

    func moveModule(_ id: String, offset: Int, all: [String]) {
        var order = orderedModuleIDs(all: all)
        guard let index = order.firstIndex(of: id) else { return }
        let target = index + offset
        guard target >= 0, target < order.count else { return }
        order.swapAt(index, target)
        moduleOrder = order
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(hoverOpenEnabled, forKey: "settings.hoverOpenEnabled")
        defaults.set(hoverExpandDelay, forKey: "settings.hoverExpandDelay")
        defaults.set(hoverCollapseGrace, forKey: "settings.hoverCollapseGrace")
        defaults.set(notifyFinished, forKey: "settings.notifyFinished")
        defaults.set(notifyPermission, forKey: "settings.notifyPermission")
        defaults.set(notifyFailed, forKey: "settings.notifyFailed")
        defaults.set(notifyClaude, forKey: "settings.notifyClaude")
        defaults.set(notifyCodex, forKey: "settings.notifyCodex")
        defaults.set(agentAutoClearSeconds, forKey: "settings.agentAutoClearSeconds")
        defaults.set(screenshotBufferLimit, forKey: "settings.screenshotBufferLimit")
        defaults.set(attentionRetentionDays, forKey: "settings.attentionRetentionDays")
        defaults.set(moduleOrder, forKey: "settings.moduleOrder")
    }

    var hoverPolicy: IslandHoverPolicy {
        IslandHoverPolicy(expandDelay: hoverExpandDelay, collapseGrace: hoverCollapseGrace)
    }

    func allowsNotification(kind: AttentionKind, provider: AgentProviderKind) -> Bool {
        let kindAllowed: Bool
        switch kind {
        case .finished: kindAllowed = notifyFinished
        case .needsPermission: kindAllowed = notifyPermission
        case .failed: kindAllowed = notifyFailed
        }
        let providerAllowed = provider == .claude ? notifyClaude : notifyCodex
        return kindAllowed && providerAllowed
    }
}

@MainActor
enum LaunchAtLogin {
    static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.lincode.personalisland.plist")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
            || FileManager.default.fileExists(atPath: legacyAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            removeLegacyAgent()
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            removeLegacyAgent()
        }
    }

    private static func removeLegacyAgent() {
        guard FileManager.default.fileExists(atPath: legacyAgentURL.path) else { return }
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(getuid())/com.lincode.personalisland.launcher"]
        try? bootout.run()
        bootout.waitUntilExit()
        try? FileManager.default.removeItem(at: legacyAgentURL)
    }
}
