import AppKit

@MainActor
final class AgentProviderIconResolver {
    static let shared = AgentProviderIconResolver()

    private var cache: [AgentProviderKind: NSImage?] = [:]

    private static let bundleIDs: [AgentProviderKind: [String]] = [
        .claude: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
        .codex: ["com.openai.codex", "com.openai.chat"],
    ]

    func icon(for provider: AgentProviderKind) -> NSImage? {
        if let cached = cache[provider] { return cached }
        let resolved = Self.resolveIcon(for: provider)
        cache[provider] = resolved
        return resolved
    }

    private static func resolveIcon(for provider: AgentProviderKind) -> NSImage? {
        for bundleID in bundleIDs[provider] ?? [] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                Log.agentIcons.info("provider icon for \(provider.rawValue, privacy: .public) from \(bundleID, privacy: .public)")
                return icon
            }
        }
        Log.agentIcons.warning("no official app found for \(provider.rawValue, privacy: .public) — neutral placeholder")
        return nil
    }
}
