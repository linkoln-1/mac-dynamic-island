import Combine
import Foundation

@MainActor
final class AttentionStore: ObservableObject {
    struct Policy {
        var maxItems = 200
        var maxAge: TimeInterval = 7 * 24 * 3600
        var persistDebounce: TimeInterval = 0.5
        var notifiedKinds: Set<AttentionKind> = [.needsPermission, .finished, .failed]
    }

    static let shared = AttentionStore()

    @Published private(set) var items: [String: AttentionItem] = [:]

    let notificationRequests = PassthroughSubject<AttentionItem, Never>()

    private let policy: Policy
    var liveMaxAge: (() -> TimeInterval)?
    private let persistence: AttentionPersistence
    private let now: () -> Date
    private var persistWork: DispatchWorkItem?

    init(
        policy: Policy = Policy(),
        persistence: AttentionPersistence = AttentionPersistence(),
        now: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.persistence = persistence
        self.now = now
        let loaded = persistence.load()
        items = Dictionary(uniqueKeysWithValues: loaded.map { ($0.dedupKey, $0) })
        applyRetention()
    }

    func publish(_ event: AttentionEvent) {
        let moment = now()
        if var existing = items[event.dedupKey] {
            existing.updatedAt = moment
            items[event.dedupKey] = existing
            schedulePersist()
            return
        }
        let item = AttentionItem(
            dedupKey: event.dedupKey,
            source: event.source,
            kind: event.kind,
            priority: event.priority,
            title: event.title,
            subtitle: event.subtitle,
            detail: event.detail,
            createdAt: moment,
            updatedAt: moment,
            isUnread: true,
            isResolved: event.kind != .needsPermission,
            isDismissed: false,
            provider: event.provider,
            projectName: event.projectName,
            projectPath: event.projectPath,
            sessionAlias: event.sessionAlias,
            relatedAgentSessionID: event.relatedAgentSessionID,
            relatedWorkCycleID: event.relatedWorkCycleID
        )
        items[event.dedupKey] = item
        applyRetention()
        schedulePersist()
        if policy.notifiedKinds.contains(event.kind) {
            notificationRequests.send(item)
        }
    }

    func resolve(dedupKey: String) {
        guard var item = items[dedupKey], !item.isResolved else { return }
        item.isResolved = true
        item.priority = .normal
        item.updatedAt = now()
        items[dedupKey] = item
        schedulePersist()
    }

    func markRead(_ id: String) {
        guard var item = items[id], item.isUnread else { return }
        item.isUnread = false
        item.updatedAt = now()
        items[id] = item
        schedulePersist()
    }

    func dismiss(_ id: String) {
        guard var item = items[id], !item.isDismissed else { return }
        item.isDismissed = true
        item.isUnread = false
        item.updatedAt = now()
        items[id] = item
        schedulePersist()
    }

    func clearRead() {
        items = items.filter { _, item in
            item.isUnread && !item.isDismissed
        }
        schedulePersist()
    }

    var unreadCount: Int {
        items.values.filter { $0.isUnread && !$0.isDismissed }.count
    }

    var highPriorityUnreadCount: Int {
        items.values.filter { $0.isActionableHigh }.count
    }

    func sortedItems(unreadOnly: Bool = false) -> [AttentionItem] {
        items.values
            .filter { !$0.isDismissed && (!unreadOnly || $0.isUnread) }
            .sorted { lhs, rhs in
                let lr = sortRank(lhs)
                let rr = sortRank(rhs)
                if lr != rr { return lr < rr }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func sortRank(_ item: AttentionItem) -> Int {
        if item.isActionableHigh { return 0 }
        if item.isUnread && item.kind == .failed { return 1 }
        if item.isUnread { return 2 }
        return 3
    }

    private func applyRetention() {
        let moment = now()
        let maxAge = liveMaxAge?() ?? policy.maxAge
        var kept = items.values.filter { item in
            item.isActionableHigh || moment.timeIntervalSince(item.updatedAt) <= maxAge
        }
        if kept.count > policy.maxItems {
            let protected = kept.filter { $0.isActionableHigh }
            let rest = kept.filter { !$0.isActionableHigh }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(max(0, policy.maxItems - protected.count))
            kept = protected + Array(rest)
        }
        items = Dictionary(uniqueKeysWithValues: kept.map { ($0.dedupKey, $0) })
    }

    private func schedulePersist() {
        persistWork?.cancel()
        let snapshot = { [weak self] in
            guard let self else { return }
            self.persistWork = nil
            self.persistence.save(Array(self.items.values))
        }
        let work = DispatchWorkItem { Task { @MainActor in snapshot() } }
        persistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + policy.persistDebounce, execute: work)
    }

    func persistNow() {
        persistWork?.cancel()
        persistWork = nil
        persistence.save(Array(items.values))
    }
}
