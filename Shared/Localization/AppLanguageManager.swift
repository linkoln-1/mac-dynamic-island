import Combine
import Foundation

enum AppLanguageMode: String, CaseIterable {
    case system
    case english
    case russian
}

@MainActor
final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()
    static let defaultsKey = "appLanguageMode"
    private static let missingMarker = "\u{FFFF}PI_MISSING\u{FFFF}"

    @Published private(set) var mode: AppLanguageMode
    @Published private(set) var languageCode: String

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]
    private var localizedBundle: Bundle
    private let englishBundle: Bundle
    private var reportedMissingKeys: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        let storedMode = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguageMode.init(rawValue:)) ?? .system
        let code = Self.resolveCode(mode: storedMode, preferred: preferredLanguages())
        mode = storedMode
        languageCode = code
        englishBundle = Self.bundle(for: "en")
        localizedBundle = Self.bundle(for: code)
    }

    static func resolveCode(mode: AppLanguageMode, preferred: [String]) -> String {
        switch mode {
        case .english:
            return "en"
        case .russian:
            return "ru"
        case .system:
            for language in preferred {
                if language.hasPrefix("ru") { return "ru" }
                if language.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }

    private static func bundle(for code: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return Bundle.main }
        return bundle
    }

    var locale: Locale { Locale(identifier: languageCode) }

    func setMode(_ newMode: AppLanguageMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.defaultsKey)
        refreshResolvedLanguage()
    }

    func refreshResolvedLanguage() {
        let code = Self.resolveCode(mode: mode, preferred: preferredLanguages())
        guard code != languageCode else { return }
        languageCode = code
        localizedBundle = Self.bundle(for: code)
    }

    func string(_ key: String) -> String {
        let value = localizedBundle.localizedString(
            forKey: key, value: Self.missingMarker, table: nil
        )
        if value != Self.missingMarker { return value }
        #if DEBUG
        if !reportedMissingKeys.contains(key) {
            reportedMissingKeys.insert(key)
            Log.attention.warning("Localization missing: \(key, privacy: .public) locale=\(self.languageCode, privacy: .public)")
        }
        #endif
        let english = englishBundle.localizedString(forKey: key, value: key, table: nil)
        return english
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    func plural(_ key: String, _ count: Int) -> String {
        String(format: string(key), locale: locale, count)
    }
}

@MainActor
enum ActivityPresentation {
    static func localize(_ canonical: String, lang: AppLanguageManager) -> String {
        let exact: [String: String] = [
            "Working": "agent.activity.working",
            "Thinking…": "agent.activity.thinking",
            "Reading files": "agent.activity.readingFiles",
            "Editing files": "agent.activity.editingFiles",
            "Writing files": "agent.activity.writingFiles",
            "Running a command": "agent.activity.runningCommand",
            "Searching": "agent.activity.searching",
            "Fetching a page": "agent.activity.fetching",
            "Working with subagent": "agent.activity.subagent",
            "Using MCP tool": "agent.activity.mcp",
            "Waiting for your permission": "agent.activity.waitingPermission",
        ]
        if let key = exact[canonical] { return lang.string(key) }

        let prefixed: [(String, String)] = [
            ("Reading ", "agent.activity.reading"),
            ("Editing ", "agent.activity.editing"),
            ("Writing ", "agent.activity.writing"),
            ("Running ", "agent.activity.running"),
            ("Using ", "agent.activity.using"),
        ]
        for (prefix, key) in prefixed where canonical.hasPrefix(prefix) {
            let subject = String(canonical.dropFirst(prefix.count))
            return String(format: lang.string(key), locale: lang.locale, subject)
        }
        return canonical
    }

    static func localizeFailure(_ canonical: String?, lang: AppLanguageManager) -> String {
        let map: [String: String] = [
            "rate limit": "agent.failure.rateLimit",
            "authentication": "agent.failure.authentication",
            "network error": "agent.failure.network",
            "server error": "agent.failure.server",
            "error": "agent.failure.generic",
        ]
        guard let canonical else { return lang.string("agent.failure.generic") }
        if let key = map[canonical] { return lang.string(key) }
        return canonical
    }
}

@MainActor
enum AttentionPresentation {
    static func kindLabel(_ kind: AttentionKind, lang: AppLanguageManager) -> String {
        switch kind {
        case .needsPermission: return lang.string("agent.state.needsPermission")
        case .finished: return lang.string("agent.state.finished")
        case .failed: return lang.string("agent.state.failed")
        }
    }

    static func detail(_ item: AttentionItem, lang: AppLanguageManager) -> String {
        switch item.kind {
        case .finished:
            if item.detail.hasPrefix("Finished in ") {
                let duration = String(item.detail.dropFirst("Finished in ".count))
                return String(
                    format: lang.string("attention.detail.finishedIn"),
                    locale: lang.locale, duration
                )
            }
            return lang.string("attention.detail.finished")
        case .needsPermission:
            return ActivityPresentation.localize(item.detail, lang: lang)
        case .failed:
            return ActivityPresentation.localizeFailure(item.detail, lang: lang)
        }
    }

    static func relativeTime(from date: Date, now: Date, lang: AppLanguageManager) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return lang.string("time.now") }
        if interval < 3600 { return lang.format("time.minutesAgo", Int(interval / 60)) }
        if interval < 86400 { return lang.format("time.hoursAgo", Int(interval / 3600)) }
        return lang.format("time.daysAgo", Int(interval / 86400))
    }
}

extension AgentSessionState {
    var localizationKey: String {
        switch self {
        case .idle: return "agent.state.idle"
        case .working: return "agent.state.working"
        case .needsPermission: return "agent.state.needsPermission"
        case .finished: return "agent.state.finished"
        case .failed: return "agent.state.failed"
        case .stale: return "agent.state.stale"
        }
    }
}
