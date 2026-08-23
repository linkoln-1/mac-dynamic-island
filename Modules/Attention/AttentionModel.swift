import Foundation

enum AttentionSource: Codable, Equatable, Hashable {
    case agent(AgentProviderKind)
}

enum AttentionKind: String, Codable, Equatable {
    case needsPermission
    case finished
    case failed

    var label: String {
        switch self {
        case .needsPermission: return "Needs permission"
        case .finished: return "Finished"
        case .failed: return "Failed"
        }
    }
}

enum AttentionPriority: Int, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2

    static func < (lhs: AttentionPriority, rhs: AttentionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AttentionItem: Codable, Identifiable, Equatable {
    var dedupKey: String
    var source: AttentionSource
    var kind: AttentionKind
    var priority: AttentionPriority

    var title: String
    var subtitle: String
    var detail: String

    var createdAt: Date
    var updatedAt: Date

    var isUnread: Bool
    var isResolved: Bool
    var isDismissed: Bool

    var provider: AgentProviderKind
    var projectName: String
    var projectPath: String?
    var sessionAlias: String
    var relatedAgentSessionID: String
    var relatedWorkCycleID: Int

    var id: String { dedupKey }

    var isActionableHigh: Bool {
        priority == .high && !isResolved && !isDismissed
    }
}

struct AttentionEvent {
    var dedupKey: String
    var source: AttentionSource
    var kind: AttentionKind
    var priority: AttentionPriority
    var title: String
    var subtitle: String
    var detail: String
    var provider: AgentProviderKind
    var projectName: String
    var projectPath: String?
    var sessionAlias: String
    var relatedAgentSessionID: String
    var relatedWorkCycleID: Int
}

enum AttentionBadgeFormatter {
    static func label(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 9 ? "9+" : "\(count)"
    }
}

struct CompactSurfacePlan: Equatable {
    var showsMedia: Bool
    var showsMicroCluster: Bool
    var showsAgentSummary: Bool
    var showsAttentionBadge: Bool

    var isEmpty: Bool { !showsMedia && !showsAgentSummary && !showsAttentionBadge }

    static func plan(
        hasMedia: Bool, hasAgentSummary: Bool, highPriorityCount: Int
    ) -> CompactSurfacePlan {
        let hasAttention = highPriorityCount > 0
        return CompactSurfacePlan(
            showsMedia: hasMedia,
            showsMicroCluster: hasMedia && (hasAgentSummary || hasAttention),
            showsAgentSummary: !hasMedia && hasAgentSummary,
            showsAttentionBadge: hasAttention
        )
    }
}

enum AgentAttentionMapper {
    static func event(for transition: AgentTransition) -> AttentionEvent? {
        let session = transition.session
        let kind: AttentionKind
        let priority: AttentionPriority
        let detail: String
        switch transition.kind {
        case .needsPermission:
            kind = .needsPermission
            priority = .high
            detail = session.activity.isEmpty
                ? "Waiting for your permission" : session.activity
        case .finished:
            kind = .finished
            priority = .normal
            if let duration = session.lastCycleDuration {
                detail = "Finished in \(AgentActivityFormatter.duration(duration))"
            } else {
                detail = "Finished"
            }
        case .failed:
            kind = .failed
            priority = .high
            detail = session.failureReason ?? "Failed"
        }
        return AttentionEvent(
            dedupKey: transition.dedupKey,
            source: .agent(session.provider),
            kind: kind,
            priority: priority,
            title: session.provider.displayName,
            subtitle: "\(session.project) · \(session.alias)",
            detail: detail,
            provider: session.provider,
            projectName: session.project,
            projectPath: session.projectPath,
            sessionAlias: session.alias,
            relatedAgentSessionID: session.id,
            relatedWorkCycleID: session.cycleID
        )
    }

    static func permissionDedupKey(sessionID: String, cycleID: Int) -> String {
        "\(sessionID)|\(cycleID)|\(AgentNotificationKind.needsPermission.rawValue)"
    }
}
