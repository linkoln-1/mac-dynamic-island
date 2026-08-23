import Foundation

struct AgentHookInstaller {
    var claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    var codexHooksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/hooks.json")
    var helperURL = AgentBridgePaths.helperURL
    var backupsDirectory = AgentBridgePaths.backupsDirectory

    static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "Notification", "SubagentStart", "SubagentStop", "Stop", "StopFailure",
        "SessionEnd",
    ]

    static let codexEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "SubagentStart", "SubagentStop", "Stop", "SessionEnd",
    ]

    struct Health: Equatable {
        var claudeInstalled: Bool
        var codexInstalled: Bool
        var helperInstalled: Bool
    }

    func installHelper(from bundledHelper: URL) throws {
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: helperURL.path) {
            try FileManager.default.removeItem(at: helperURL)
        }
        try FileManager.default.copyItem(at: bundledHelper, to: helperURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    }

    func hookCommand(provider: AgentProviderKind) -> String {
        "\"\(helperURL.path)\" --provider \(provider.rawValue)"
    }

    private func hookEntry(provider: AgentProviderKind, event: String) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand(provider: provider),
        ]

        hook["async"] = true
        hook["timeout"] = 10
        return ["matcher": "*", "hooks": [hook]]
    }

    private func isOurs(_ matcherGroup: [String: Any]) -> Bool {
        guard let hooks = matcherGroup["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains("personal-island-agent-hook") == true }
    }

    func installClaudeHooks() throws {
        try mergeHooks(
            configURL: claudeSettingsURL, events: Self.claudeEvents,
            provider: .claude, topLevel: true
        )
    }

    func installCodexHooks() throws {
        try mergeHooks(
            configURL: codexHooksURL, events: Self.codexEvents,
            provider: .codex, topLevel: false
        )
    }

    private func mergeHooks(
        configURL: URL, events: [String], provider: AgentProviderKind, topLevel: Bool
    ) throws {
        var document: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw NSError(domain: "AgentHookInstaller", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "existing config at \(configURL.path) is not valid JSON — refusing to touch it",
                ])
            }
            document = parsed
            try backup(configURL: configURL, data: data)
        }

        var hooksSection = (document["hooks"] as? [String: Any]) ?? [:]
        var changed = false
        for event in events {
            var groups = (hooksSection[event] as? [[String: Any]]) ?? []
            if !groups.contains(where: isOurs) {
                groups.append(hookEntry(provider: provider, event: event))
                changed = true
            }
            hooksSection[event] = groups
        }
        guard changed || document["hooks"] == nil else {
            document["hooks"] = hooksSection
            return
        }
        document["hooks"] = hooksSection
        _ = topLevel

        let output = try JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try output.write(to: configURL, options: .atomic)
    }

    func uninstall(configURL: URL) throws {
        guard let data = try? Data(contentsOf: configURL),
              var document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var hooksSection = document["hooks"] as? [String: Any]
        else { return }
        try backup(configURL: configURL, data: data)

        for (event, value) in hooksSection {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooksSection[event] = kept.isEmpty ? nil : kept
        }
        document["hooks"] = hooksSection.isEmpty ? nil : hooksSection
        let output = try JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .sortedKeys]
        )
        try output.write(to: configURL, options: .atomic)
    }

    private func backup(configURL: URL, data: Data) throws {
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(configURL.lastPathComponent).\(formatter.string(from: Date())).bak"
        let url = backupsDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
        }
    }

    func health() -> Health {
        Health(
            claudeInstalled: configHasOurHooks(claudeSettingsURL),
            codexInstalled: configHasOurHooks(codexHooksURL),
            helperInstalled: FileManager.default.isExecutableFile(atPath: helperURL.path)
        )
    }

    private func configHasOurHooks(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooksSection = document["hooks"] as? [String: Any]
        else { return false }
        return hooksSection.values.contains { value in
            (value as? [[String: Any]])?.contains(where: isOurs) == true
        }
    }
}
