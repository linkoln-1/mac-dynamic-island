import Combine
import Foundation

enum AgentNotificationKind: String {
    case finished
    case needsPermission
    case failed
}

struct AgentTransition: Equatable {
    var session: AgentSession
    var kind: AgentNotificationKind

    var dedupKey: String
}

struct AgentPermissionResolution: Equatable {
    var session: AgentSession
    var cycleID: Int
}

@MainActor
final class AgentStore: ObservableObject {
    struct Policy {

        var finishedRetention: TimeInterval = 60

        var idleRetention: TimeInterval = 25 * 60

        var staleThreshold: TimeInterval = 30 * 60

        var minimumNotifiedCycle: TimeInterval = 3
    }

    @Published private(set) var sessions: [String: AgentSession] = [:]

    let transitions = PassthroughSubject<AgentTransition, Never>()
    let resolutions = PassthroughSubject<AgentPermissionResolution, Never>()

    private let policy: Policy
    private let now: () -> Date
    private let projectResolver = AgentProjectResolver()
    private var seenDedupKeys: [String] = []
    private var seenDedupSet: Set<String> = []

    private var notifiedPermissionCycles: Set<String> = []

    init(policy: Policy = Policy(), now: @escaping () -> Date = Date.init) {
        self.policy = policy
        self.now = now
    }

    var orderedSessions: [AgentSession] {
        sessions.values.sorted { lhs, rhs in
            if lhs.state.sortRank != rhs.state.sortRank {
                return lhs.state.sortRank < rhs.state.sortRank
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    func ingest(_ event: AgentWireEvent) {

        guard !seenDedupSet.contains(event.dedupKey) else { return }
        seenDedupSet.insert(event.dedupKey)
        seenDedupKeys.append(event.dedupKey)
        if seenDedupKeys.count > 2000 {
            let removed = seenDedupKeys.removeFirst()
            seenDedupSet.remove(removed)
        }

        let key = "\(event.provider.rawValue):\(event.sessionID)"
        let moment = now()
        var session = sessions[key] ?? newSession(for: event, at: moment)
        session.lastActivityAt = moment
        let previousState = session.state
        let previousCycleID = session.cycleID

        switch event.event {
        case "SessionStart":
            break

        case "UserPromptSubmit":
            session.cycleID += 1
            session.cycleStartedAt = moment
            session.state = .working
            session.activity = "Thinking…"
            session.failureReason = nil

        case "PreToolUse":
            if session.state != .working {

                if session.cycleStartedAt == nil {
                    session.cycleID += 1
                    session.cycleStartedAt = moment
                }
                session.state = .working
            }
            session.activity = AgentActivityFormatter.activity(
                toolName: event.toolName, detail: event.activityDetail
            )

        case "PermissionRequest":
            session.state = .needsPermission
            if let toolName = event.toolName {
                session.activity = AgentActivityFormatter.activity(
                    toolName: toolName, detail: event.activityDetail
                )
            }
            emitPermission(session)

        case "Notification":
            if event.notificationType == "permission_prompt" {
                session.state = .needsPermission
                emitPermission(session)
            }

        case "SubagentStart":
            session.subagentCount += 1

        case "SubagentStop":
            session.subagentCount = max(0, session.subagentCount - 1)

        case "Stop":
            let duration = session.cycleStartedAt.map { moment.timeIntervalSince($0) }
            session.state = .finished
            session.finishedAt = moment
            session.lastCycleDuration = duration
            session.activity = ""
            session.subagentCount = 0
            if (duration ?? 0) >= policy.minimumNotifiedCycle {
                emit(session, kind: .finished)
            }
            session.cycleStartedAt = nil

        case "StopFailure":
            session.state = .failed
            session.finishedAt = moment
            session.lastCycleDuration = session.cycleStartedAt.map { moment.timeIntervalSince($0) }
            session.failureReason = AgentActivityFormatter.failureCategory(event.activityDetail)
            emit(session, kind: .failed)
            session.cycleStartedAt = nil

        case "SessionEnd":
            session.hasEnded = true
            if session.state == .working || session.state == .needsPermission {
                session.state = .idle
            }

        default:
            break
        }

        sessions[key] = session

        if previousState == .needsPermission, session.state != .needsPermission {
            resolutions.send(AgentPermissionResolution(session: session, cycleID: previousCycleID))
        }
    }

    private func newSession(for event: AgentWireEvent, at moment: Date) -> AgentSession {
        let resolved = projectResolver.resolve(cwd: event.cwd)
        return AgentSession(
            provider: event.provider,
            sessionID: event.sessionID,
            project: resolved.project,
            branch: resolved.branch,
            projectPath: resolved.rootPath,
            startedAt: moment,
            lastActivityAt: moment
        )
    }

    private func emit(_ session: AgentSession, kind: AgentNotificationKind) {
        transitions.send(AgentTransition(
            session: session,
            kind: kind,
            dedupKey: "\(session.id)|\(session.cycleID)|\(kind.rawValue)"
        ))
    }

    private func emitPermission(_ session: AgentSession) {
        let cycleKey = "\(session.id)|\(session.cycleID)"
        guard !notifiedPermissionCycles.contains(cycleKey) else { return }
        notifiedPermissionCycles.insert(cycleKey)
        emit(session, kind: .needsPermission)
    }

    func sweep() {
        let moment = now()
        for (key, var session) in sessions {
            switch session.state {
            case .finished, .failed:
                let anchor = session.finishedAt ?? session.lastActivityAt
                if moment.timeIntervalSince(anchor) > policy.finishedRetention {
                    sessions.removeValue(forKey: key)
                }
            case .idle:

                let retention = session.hasEnded
                    ? policy.finishedRetention : policy.idleRetention
                if moment.timeIntervalSince(session.lastActivityAt) > retention {
                    sessions.removeValue(forKey: key)
                }
            case .stale:
                if moment.timeIntervalSince(session.lastActivityAt) > policy.idleRetention {
                    sessions.removeValue(forKey: key)
                }
            case .working, .needsPermission:
                if moment.timeIntervalSince(session.lastActivityAt) > policy.staleThreshold {
                    session.state = .stale
                    sessions[key] = session
                }
            }
        }
    }

    func orderedSessions(provider: AgentProviderKind?) -> [AgentSession] {
        guard let provider else { return orderedSessions }
        return orderedSessions.filter { $0.provider == provider }
    }

    func sessionCount(provider: AgentProviderKind?) -> Int {
        guard let provider else { return sessions.count }
        return sessions.values.filter { $0.provider == provider }.count
    }

    func hasInactiveSessions(provider: AgentProviderKind? = nil) -> Bool {
        sessions.values.contains {
            $0.state != .working && $0.state != .needsPermission
                && (provider == nil || $0.provider == provider)
        }
    }

    func clearInactive(provider: AgentProviderKind? = nil) {
        sessions = sessions.filter { _, session in
            session.state == .working || session.state == .needsPermission
                || (provider != nil && session.provider != provider)
        }
    }

    struct CompactSummary: Equatable {
        var claudeActive = 0
        var codexActive = 0
        var working = 0
        var attention = 0
        var isEmpty: Bool { claudeActive == 0 && codexActive == 0 }
    }

    var compactSummary: CompactSummary {
        var summary = CompactSummary()
        for session in sessions.values {
            let isActive = session.state == .working || session.state == .needsPermission
                || session.state == .idle
            if isActive {
                switch session.provider {
                case .claude: summary.claudeActive += 1
                case .codex: summary.codexActive += 1
                }
            }
            if session.state == .working { summary.working += 1 }
            if session.state == .needsPermission { summary.attention += 1 }
        }
        return summary
    }
}
