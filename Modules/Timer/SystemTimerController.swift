import Combine
import CoreServices
import Foundation

@MainActor
final class SystemTimerController: ObservableObject {
    static let shared = SystemTimerController()

    @Published private(set) var snapshot: SystemTimerSnapshot?
    @Published private(set) var tick = Date()

    private static let preferencesDomain = "com.apple.mobiletimerd"
    private static let timersKey = "MTTimers"
    private static let safetyReadInterval: TimeInterval = 5

    static var preferencesPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(preferencesDomain).plist").path
    }

    private let read: () -> [[String: Any]]
    private let isEnabled: @MainActor () -> Bool
    private let now: () -> Date
    private var watcher: SystemTimerPreferencesWatcher?
    private var ticker: Timer?
    private var ticksSinceRead = 0
    private var isStarted = false

    init(
        read: @escaping () -> [[String: Any]] = SystemTimerController.readTimerEntries,
        isEnabled: (@MainActor () -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.read = read
        self.isEnabled = isEnabled ?? { AppSettings.shared.showSystemTimer }
        self.now = now
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
        watcher = SystemTimerPreferencesWatcher(path: Self.preferencesPath) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        ticker?.invalidate()
        ticker = nil
        isStarted = false
    }

    func refresh() {
        ticksSinceRead = 0
        let parsed = isEnabled() ? SystemTimerParser.snapshot(from: read()) : nil
        if parsed != snapshot { snapshot = parsed }
        tick = now()
    }

    private func heartbeat() {
        ticksSinceRead += 1
        if ticksSinceRead >= Int(Self.safetyReadInterval) {
            refresh()
            return
        }
        guard let snapshot, !snapshot.isPaused else { return }
        tick = now()
    }

    static func readTimerEntries() -> [[String: Any]] {
        CFPreferencesAppSynchronize(preferencesDomain as CFString)
        let value = CFPreferencesCopyValue(
            timersKey as CFString, preferencesDomain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        )
        guard let container = value as? [String: Any],
              let entries = container[timersKey] as? [[String: Any]]
        else { return [] }
        return entries
    }
}

private final class SystemTimerPreferencesWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(path: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: nil, retain: nil, release: nil, copyDescription: nil
        )
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<SystemTimerPreferencesWatcher>.fromOpaque(info)
                .takeUnretainedValue().onChange()
        }
        guard let created = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
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
