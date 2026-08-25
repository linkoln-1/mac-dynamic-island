import Foundation

struct SystemTimerSnapshot: Equatable {
    enum Mode: Equatable {
        case running(fireDate: Date)
        case paused(remaining: TimeInterval)
    }

    var mode: Mode
    var duration: TimeInterval

    var isPaused: Bool {
        if case .paused = mode { return true }
        return false
    }

    func remaining(at now: Date) -> TimeInterval {
        switch mode {
        case .running(let fireDate):
            return max(0, fireDate.timeIntervalSince(now))
        case .paused(let remaining):
            return max(0, remaining)
        }
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / duration))
    }

    func isEnding(at now: Date, threshold: TimeInterval = 10) -> Bool {
        !isPaused && remaining(at: now) <= threshold
    }
}

enum SystemTimerParser {
    static let runningState = 3
    static let pausedState = 2

    static func snapshot(from entries: [[String: Any]]) -> SystemTimerSnapshot? {
        let candidates = entries.compactMap(snapshot(fromEntry:))
        let running = candidates.filter { !$0.isPaused }
        if !running.isEmpty {
            return running.min { fireDate($0) < fireDate($1) }
        }
        return candidates.min { $0.remaining(at: .distantPast) < $1.remaining(at: .distantPast) }
    }

    static func snapshot(fromEntry entry: [String: Any]) -> SystemTimerSnapshot? {
        guard let timer = entry["$MTTimer"] as? [String: Any],
              let state = timer["MTTimerState"] as? Int
        else { return nil }
        let duration = (timer["MTTimerDuration"] as? Double) ?? 0
        let fireTime = timer["MTTimerFireTime"] as? [String: Any]

        switch state {
        case runningState:
            guard let date = (fireTime?["$MTTimerDate"] as? [String: Any])?["MTTimerTimeDate"] as? Date
            else { return nil }
            return SystemTimerSnapshot(mode: .running(fireDate: date), duration: duration)
        case pausedState:
            guard let interval = (fireTime?["$MTTimerTimeInterval"] as? [String: Any])?[
                "MTTimerTimeInterval"
            ] as? Double else { return nil }
            return SystemTimerSnapshot(
                mode: .paused(remaining: interval),
                duration: max(duration, interval)
            )
        default:
            return nil
        }
    }

    private static func fireDate(_ snapshot: SystemTimerSnapshot) -> Date {
        if case .running(let date) = snapshot.mode { return date }
        return .distantFuture
    }
}
