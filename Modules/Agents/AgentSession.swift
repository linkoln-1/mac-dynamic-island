import Foundation

enum AgentSessionState: String, Equatable {
    case idle
    case working
    case needsPermission
    case finished
    case failed
    case stale

    var sortRank: Int {
        switch self {
        case .needsPermission: return 0
        case .working: return 1
        case .failed: return 2
        case .finished: return 3
        case .idle: return 4
        case .stale: return 5
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .needsPermission: return "Needs permission"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .stale: return "No recent activity"
        }
    }
}

struct AgentSession: Identifiable, Equatable {
    var provider: AgentProviderKind
    var sessionID: String
    var project: String
    var branch: String?
    var projectPath: String?
    var hostAppPath: String?

    var state: AgentSessionState = .idle
    var activity: String = ""
    var startedAt: Date
    var lastActivityAt: Date
    var cycleStartedAt: Date?
    var cycleID: Int = 0
    var finishedAt: Date?
    var lastCycleDuration: TimeInterval?
    var subagentCount: Int = 0
    var failureReason: String?

    var hasEnded: Bool = false

    var id: String { "\(provider.rawValue):\(sessionID)" }

    var alias: String {
        let cleaned = sessionID.replacingOccurrences(of: "-", with: "").uppercased()
        let tail = String(cleaned.suffix(4))
        return "\(provider.aliasPrefix)-\(tail.isEmpty ? "0000" : tail)"
    }

    func cycleDuration(at now: Date) -> TimeInterval? {
        if state == .working || state == .needsPermission,
           let cycleStartedAt {
            return now.timeIntervalSince(cycleStartedAt)
        }
        return lastCycleDuration
    }
}

final class AgentProjectResolver {
    private var cache: [String: (project: String, branch: String?, rootPath: String)] = [:]

    func resolve(cwd: String?) -> (project: String, branch: String?, rootPath: String?) {
        guard let cwd, !cwd.isEmpty else { return ("Unknown", nil, nil) }
        if let cached = cache[cwd] { return cached }

        var result: (String, String?, String) = ((cwd as NSString).lastPathComponent, nil, cwd)
        var directory = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let gitURL = directory.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                result = (directory.lastPathComponent, Self.branch(gitURL: gitURL), directory.path)
                break
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
        }
        cache[cwd] = result
        return result
    }

    private static func branch(gitURL: URL) -> String? {
        var headURL = gitURL.appendingPathComponent("HEAD")

        if let contents = try? String(contentsOf: gitURL, encoding: .utf8),
           contents.hasPrefix("gitdir:") {
            let path = contents.dropFirst("gitdir:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headURL = URL(fileURLWithPath: path).appendingPathComponent("HEAD")
        }
        guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        guard let range = head.range(of: "refs/heads/") else { return nil }
        return String(head[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
