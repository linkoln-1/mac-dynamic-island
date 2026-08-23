import Foundation
import UserNotifications

protocol AgentNotificationPosting: AnyObject {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func post(title: String, subtitle: String, body: String, thread: String, identifier: String)
}

final class SystemNotificationPoster: AgentNotificationPosting {
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func post(title: String, subtitle: String, body: String, thread: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.threadIdentifier = thread
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class AgentNotificationManager {
    private let poster: AgentNotificationPosting
    private let localization: AppLanguageManager
    private var sentKeys: Set<String> = []
    private(set) var isAuthorized = false
    private var didRequestAuthorization = false

    init(
        poster: AgentNotificationPosting = SystemNotificationPoster(),
        localization: AppLanguageManager = .shared
    ) {
        self.poster = poster
        self.localization = localization
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        poster.requestAuthorization { [weak self] granted in
            self?.isAuthorized = granted
            Log.agentNotifications.info("notification authorization granted=\(granted)")
        }
    }

    func post(item: AttentionItem) {
        guard !sentKeys.contains(item.dedupKey) else { return }
        sentKeys.insert(item.dedupKey)
        if sentKeys.count > 4000 { sentKeys.removeAll() }

        poster.post(
            title: "\(item.provider.displayName) · \(item.projectName)",
            subtitle: "\(item.sessionAlias) · \(AttentionPresentation.kindLabel(item.kind, lang: localization))",
            body: AttentionPresentation.detail(item, lang: localization),
            thread: item.relatedAgentSessionID,
            identifier: item.dedupKey
        )
    }

    func handle(_ transition: AgentTransition) {
        guard !sentKeys.contains(transition.dedupKey) else { return }
        sentKeys.insert(transition.dedupKey)
        if sentKeys.count > 4000 { sentKeys.removeAll() }

        let session = transition.session
        let title = "\(session.provider.displayName) · \(session.project)"
        let subtitle = "\(session.alias) · \(subtitleLabel(for: transition.kind))"
        let body = body(for: transition)

        poster.post(
            title: title,
            subtitle: subtitle,
            body: body,
            thread: session.id,
            identifier: transition.dedupKey
        )
    }

    private func subtitleLabel(for kind: AgentNotificationKind) -> String {
        switch kind {
        case .finished: return "Finished"
        case .needsPermission: return "Needs permission"
        case .failed: return "Failed"
        }
    }

    private func body(for transition: AgentTransition) -> String {
        let session = transition.session
        switch transition.kind {
        case .finished:
            if let duration = session.lastCycleDuration {
                return "Finished in \(AgentActivityFormatter.duration(duration))"
            }
            return "Finished"
        case .needsPermission:
            return session.activity.isEmpty
                ? "Waiting for your permission"
                : "Needs permission for \(session.activity)"
        case .failed:
            return "Failed · \(session.failureReason ?? "error")"
        }
    }
}
