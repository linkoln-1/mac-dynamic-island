import Foundation

enum AgentProviderKind: String, Codable, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var aliasPrefix: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        }
    }
}

struct AgentWireEvent: Codable, Equatable {
    var v: Int = 1
    var provider: AgentProviderKind

    var event: String
    var sessionID: String

    var timestamp: Double
    var cwd: String?
    var toolName: String?

    var activityDetail: String?

    var notificationType: String?

    var dedupKey: String
    var hostAppPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case v, provider, event
        case sessionID = "sid"
        case timestamp = "ts"
        case cwd
        case toolName = "tool"
        case activityDetail = "act"
        case notificationType = "nt"
        case dedupKey = "uid"
        case hostAppPath = "app"
    }
}

enum AgentBridgePaths {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalIsland/AgentBridge", isDirectory: true)
    }
    static var socketURL: URL { root.appendingPathComponent("agent.sock") }
    static var spoolDirectory: URL { root.appendingPathComponent("spool", isDirectory: true) }
    static var helperDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }
    static var helperURL: URL { helperDirectory.appendingPathComponent("personal-island-agent-hook") }
    static var backupsDirectory: URL { root.appendingPathComponent("backups", isDirectory: true) }
}

enum AgentSpoolPolicy {
    static let maxAge: TimeInterval = 24 * 3600
    static let maxEvents = 500
}

enum AgentHookPayloadMapper {
    static let maxDetailLength = 100

    static func wireEvent(
        provider: AgentProviderKind,
        payload: [String: Any],
        now: Date = Date()
    ) -> AgentWireEvent? {
        guard let event = payload["hook_event_name"] as? String,
              let sessionID = payload["session_id"] as? String,
              !sessionID.isEmpty
        else { return nil }

        let toolName = payload["tool_name"] as? String
        let toolInput = payload["tool_input"] as? [String: Any]
        let detail = activityDetail(toolName: toolName, toolInput: toolInput)
        let notificationType = payload["notification_type"] as? String

        let fingerprint = [
            provider.rawValue, event, sessionID,
            toolName ?? "", detail ?? "", notificationType ?? "",
            (payload["turn_id"] as? String) ?? "",
            String(describing: payload["stop_hook_active"] ?? ""),
        ].joined(separator: "|")

        return AgentWireEvent(
            provider: provider,
            event: event,
            sessionID: sessionID,
            timestamp: now.timeIntervalSince1970,
            cwd: payload["cwd"] as? String,
            toolName: toolName,
            activityDetail: detail,
            notificationType: notificationType,
            dedupKey: stableHash(fingerprint)
        )
    }

    static func activityDetail(toolName: String?, toolInput: [String: Any]?) -> String? {
        guard let toolInput else { return nil }
        let candidate = (toolInput["file_path"] as? String)
            ?? (toolInput["path"] as? String)
            ?? (toolInput["command"] as? String)
            ?? (toolInput["pattern"] as? String)
            ?? (toolInput["url"] as? String)
        guard var detail = candidate else { return nil }
        detail = detail.replacingOccurrences(of: "\n", with: " ")
        detail = redactSecrets(in: detail)
        if detail.count > maxDetailLength {
            detail = String(detail.prefix(maxDetailLength)) + "…"
        }
        return detail
    }

    static func redactSecrets(in text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "(?i)([A-Z_]*(TOKEN|PASSWORD|SECRET|API_KEY|APIKEY|ACCESS_KEY)[A-Z_]*)(=|:\\s*)[^\\s\"']+",
            with: "$1$3•••", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)Authorization:\\s*\\S+(\\s+\\S+)?",
            with: "Authorization: •••", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)Bearer\\s+[A-Za-z0-9._\\-]+",
            with: "Bearer •••", options: .regularExpression
        )
        return result
    }

    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
