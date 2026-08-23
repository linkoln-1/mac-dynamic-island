import Foundation

enum AgentActivityFormatter {
    static let maxLength = 90

    static func activity(toolName: String?, detail: String?) -> String {
        guard let toolName, !toolName.isEmpty else { return "Working" }
        let fileName = detail.map { ($0 as NSString).lastPathComponent }

        let line: String
        switch toolName {
        case "Read":
            line = fileName.map { "Reading \($0)" } ?? "Reading files"
        case "Edit", "MultiEdit", "NotebookEdit":
            line = fileName.map { "Editing \($0)" } ?? "Editing files"
        case "Write":
            line = fileName.map { "Writing \($0)" } ?? "Writing files"
        case "Bash", "BashOutput", "Shell", "LocalShell":
            line = detail.map { "Running \($0)" } ?? "Running a command"
        case "Grep", "Glob", "Search", "WebSearch":
            line = "Searching"
        case "WebFetch":
            line = "Fetching a page"
        case "Task", "Agent":
            line = "Working with subagent"
        case let name where name.hasPrefix("mcp__"):
            line = "Using MCP tool"
        default:
            line = detail.map { "\(toolName) · \($0)" } ?? "Using \(toolName)"
        }
        guard line.count > maxLength else { return line }
        return String(line.prefix(maxLength)) + "…"
    }

    static func failureCategory(_ detail: String?) -> String {
        guard let detail = detail?.lowercased() else { return "error" }
        if detail.contains("rate") { return "rate limit" }
        if detail.contains("auth") || detail.contains("credential") { return "authentication" }
        if detail.contains("network") || detail.contains("connect") { return "network error" }
        if detail.contains("server") || detail.contains("5xx") { return "server error" }
        return "error"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        MediaTimeFormatter.format(seconds)
    }
}
