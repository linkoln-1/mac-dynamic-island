import CoreServices
import Foundation

struct CodexRolloutTracker {
    var sessionID: String?
    var cwd: String?
    var offset: UInt64 = 0
    var lineIndex: Int = 0
    var startedTurns = 0
    var completedTurns = 0
    var lastToolName: String?
    var partialLine = ""
    var isLive = false
}

enum CodexRolloutParser {
    static let sourceTag = "codexlocal"

    static func parse(line: String, tracker: inout CodexRolloutTracker) -> [AgentWireEvent] {
        tracker.lineIndex += 1
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        let type = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]

        switch type {
        case "session_meta":
            tracker.sessionID = payload["id"] as? String
            tracker.cwd = payload["cwd"] as? String
            return events(tracker, name: "SessionStart")
        case "event_msg":
            switch payload["type"] as? String {
            case "task_started":
                tracker.startedTurns += 1
                return events(tracker, name: "UserPromptSubmit")
            case "task_complete":
                tracker.completedTurns += 1
                return events(tracker, name: "Stop")
            case "turn_aborted":
                tracker.completedTurns += 1
                return events(tracker, name: "Stop")
            default:
                return []
            }
        case "response_item":
            if payload["type"] as? String == "custom_tool_call" {
                let name = payload["name"] as? String ?? "tool"
                tracker.lastToolName = toolName(for: name)
                return events(tracker, name: "PreToolUse", tool: tracker.lastToolName)
            }
            return []
        default:
            return []
        }
    }

    static func toolName(for rolloutName: String) -> String {
        rolloutName == "exec" ? "Shell" : rolloutName
    }

    static func events(
        _ tracker: CodexRolloutTracker, name: String, tool: String? = nil
    ) -> [AgentWireEvent] {
        guard let sessionID = tracker.sessionID else { return [] }
        return [AgentWireEvent(
            provider: .codex,
            event: name,
            sessionID: sessionID,
            timestamp: Date().timeIntervalSince1970,
            cwd: tracker.cwd,
            toolName: tool,
            activityDetail: nil,
            notificationType: nil,
            dedupKey: "\(sourceTag):\(sessionID):\(tracker.lineIndex):\(name)"
        )]
    }
}

@MainActor
final class CodexLocalSessionProvider {
    enum Health: Equatable {
        case inactive
        case active
        case unavailable
    }

    private(set) var health: Health = .inactive
    var isHookAuthority: (String) -> Bool = { _ in false }

    private let root: URL
    private let emit: ([AgentWireEvent]) -> Void
    private let reconcileWindow: TimeInterval
    private var trackers: [String: CodexRolloutTracker] = [:]
    private var watcher: CodexSessionsWatcher?

    init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        reconcileWindow: TimeInterval = 6 * 3600,
        emit: @escaping ([AgentWireEvent]) -> Void
    ) {
        self.root = root
        self.reconcileWindow = reconcileWindow
        self.emit = emit
    }

    func start() {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            health = .unavailable
            Log.agentBridge.info("codex local sessions dir unavailable")
            return
        }
        reconcileRecentFiles()
        watcher = CodexSessionsWatcher(root: root.path) { [weak self] paths in
            Task { @MainActor in self?.processChanged(paths: paths) }
        }
        health = .active
        Log.agentBridge.info("codex local session provider active (fallback source)")
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        health = .inactive
    }

    func reconcileRecentFiles() {
        let cutoff = Date().addingTimeInterval(-reconcileWindow)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"),
                  url.pathExtension == "jsonl",
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                      .contentModificationDate,
                  modified > cutoff
            else { continue }
            catchUp(fileURL: url)
        }
    }

    func catchUp(fileURL: URL) {
        guard trackers[fileURL.path] == nil else { return }
        var tracker = CodexRolloutTracker()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.components(separatedBy: "\n")
        if let last = lines.last, !last.isEmpty {
            tracker.partialLine = last
            lines.removeLast()
        } else if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        for line in lines where !line.isEmpty {
            _ = CodexRolloutParser.parse(line: line, tracker: &tracker)
        }
        tracker.offset = UInt64(data.count - tracker.partialLine.utf8.count)
        tracker.partialLine = ""
        tracker.isLive = true

        if let sessionID = tracker.sessionID,
           tracker.startedTurns > tracker.completedTurns,
           !isHookAuthority(sessionID) {
            var announce = CodexRolloutParser.events(tracker, name: "SessionStart")
            for _ in 0..<tracker.startedTurns {
                announce += CodexRolloutParser.events(tracker, name: "UserPromptSubmit")
            }
            if let tool = tracker.lastToolName {
                announce += CodexRolloutParser.events(tracker, name: "PreToolUse", tool: tool)
            }
            let unique = announce.enumerated().map { index, event -> AgentWireEvent in
                var copy = event
                copy.dedupKey = "\(event.dedupKey):announce\(index)"
                return copy
            }
            emit(unique)
            Log.agentBridge.info("codex reconcile: active session imported")
        }
        trackers[fileURL.path] = tracker
    }

    func processChanged(paths: [String]) {
        for path in paths {
            let name = (path as NSString).lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            tail(fileURL: URL(fileURLWithPath: path))
        }
    }

    func tail(fileURL: URL) {
        var tracker = trackers[fileURL.path] ?? {
            var fresh = CodexRolloutTracker()
            fresh.isLive = true
            return fresh
        }()
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: tracker.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else {
            trackers[fileURL.path] = tracker
            return
        }
        tracker.offset += UInt64(data.count)
        let text = tracker.partialLine + String(decoding: data, as: UTF8.self)
        tracker.partialLine = ""
        var lines = text.components(separatedBy: "\n")
        if let last = lines.last, !last.isEmpty {
            tracker.partialLine = last
        }
        lines.removeLast()

        var produced: [AgentWireEvent] = []
        for line in lines where !line.isEmpty {
            produced += CodexRolloutParser.parse(line: line, tracker: &tracker)
        }
        trackers[fileURL.path] = tracker

        let allowed = produced.filter { !isHookAuthority($0.sessionID) }
        if !allowed.isEmpty { emit(allowed) }
    }
}

private final class CodexSessionsWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init?(root: String, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: nil, retain: nil, release: nil, copyDescription: nil
        )
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CodexSessionsWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            watcher.onChange(paths)
        }
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            )
        ) else { return nil }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
