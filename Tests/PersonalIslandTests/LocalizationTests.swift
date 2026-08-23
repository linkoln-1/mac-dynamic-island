import XCTest
@testable import PersonalIsland

@MainActor
final class LocalizationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "localization-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func manager(
        mode: AppLanguageMode? = nil, preferred: [String] = ["en-US"]
    ) -> AppLanguageManager {
        if let mode { defaults.set(mode.rawValue, forKey: AppLanguageManager.defaultsKey) }
        return AppLanguageManager(defaults: defaults, preferredLanguages: { preferred })
    }

    func testLanguageResolution() {
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .english, preferred: ["ru-RU"]), "en")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .russian, preferred: ["en-US"]), "ru")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .system, preferred: ["ru-RU"]), "ru")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .system, preferred: ["en-GB"]), "en")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .system, preferred: ["de-DE"]), "en")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .system, preferred: ["de-DE", "ru-RU"]), "ru")
        XCTAssertEqual(AppLanguageManager.resolveCode(mode: .system, preferred: []), "en")
    }

    func testModePersistsAcrossManagerRestarts() {
        let first = manager()
        first.setMode(.russian)
        let second = AppLanguageManager(defaults: defaults, preferredLanguages: { ["en-US"] })
        XCTAssertEqual(second.mode, .russian)
        XCTAssertEqual(second.languageCode, "ru")

        second.setMode(.system)
        let third = AppLanguageManager(defaults: defaults, preferredLanguages: { ["en-US"] })
        XCTAssertEqual(third.mode, .system)
        XCTAssertEqual(third.languageCode, "en")
    }

    func testLiveSwitchChangesStringsWithoutRestart() {
        let lang = manager()
        XCTAssertEqual(lang.string("agent.state.finished"), "Finished")
        lang.setMode(.russian)
        XCTAssertEqual(lang.string("agent.state.finished"), "Завершено")
        lang.setMode(.english)
        XCTAssertEqual(lang.string("agent.state.finished"), "Finished")
    }

    func testBundleContainsBothLocalizations() {
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
        XCTAssertTrue(Bundle.main.localizations.contains("ru"))
    }

    private func stringsKeys(locale: String) throws -> ([String: String], [String: Any]) {
        let stringsPath = Bundle.main.path(
            forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: locale
        )
        var plain: [String: String] = [:]
        if let stringsPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: stringsPath))
            plain = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] ?? [:]
        }
        let dictPath = Bundle.main.path(
            forResource: "Localizable", ofType: "stringsdict", inDirectory: nil, forLocalization: locale
        )
        var plural: [String: Any] = [:]
        if let dictPath {
            let data = try Data(contentsOf: URL(fileURLWithPath: dictPath))
            plural = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        }
        return (plain, plural)
    }

    func testTranslationParityAndNoEmptyValues() throws {
        let (enPlain, enPlural) = try stringsKeys(locale: "en")
        let (ruPlain, ruPlural) = try stringsKeys(locale: "ru")

        XCTAssertFalse(enPlain.isEmpty)
        XCTAssertEqual(
            Set(enPlain.keys), Set(ruPlain.keys),
            "missing ru keys: \(Set(enPlain.keys).subtracting(ruPlain.keys)); missing en keys: \(Set(ruPlain.keys).subtracting(enPlain.keys))"
        )
        XCTAssertEqual(Set(enPlural.keys), Set(ruPlural.keys))
        XCTAssertFalse(enPlural.isEmpty, "plural variations must compile into stringsdict")

        for (key, value) in enPlain {
            XCTAssertFalse(value.isEmpty, "empty en value for \(key)")
        }
        for (key, value) in ruPlain {
            XCTAssertFalse(value.isEmpty, "empty ru value for \(key)")
        }
    }

    func testEnglishFallbackForMissingKey() {
        let lang = manager(mode: .russian)
        XCTAssertEqual(lang.string("nonexistent.key.for.test"), "nonexistent.key.for.test")
        XCTAssertEqual(lang.string("agent.state.failed"), "Ошибка")
    }

    func testRussianPluralForms() {
        let lang = manager(mode: .russian)
        XCTAssertEqual(lang.plural("agent.sessions.count", 1), "1 сессия")
        XCTAssertEqual(lang.plural("agent.sessions.count", 2), "2 сессии")
        XCTAssertEqual(lang.plural("agent.sessions.count", 5), "5 сессий")
        XCTAssertEqual(lang.plural("agent.sessions.count", 11), "11 сессий")
        XCTAssertEqual(lang.plural("agent.sessions.count", 21), "21 сессия")
        XCTAssertEqual(lang.plural("agent.sessions.count", 22), "22 сессии")
        XCTAssertEqual(lang.plural("agent.sessions.count", 25), "25 сессий")
    }

    func testEnglishPluralForms() {
        let lang = manager(mode: .english)
        XCTAssertEqual(lang.plural("agent.sessions.count", 1), "1 session")
        XCTAssertEqual(lang.plural("agent.sessions.count", 2), "2 sessions")
        XCTAssertEqual(lang.plural("agent.subagents.count", 1), "1 subagent")
        XCTAssertEqual(lang.plural("agent.subagents.count", 3), "3 subagents")
    }

    private func makeItem(
        kind: AttentionKind, detail: String, provider: AgentProviderKind = .claude
    ) -> AttentionItem {
        AttentionItem(
            dedupKey: "k", source: .agent(provider), kind: kind,
            priority: kind == .finished ? .normal : .high,
            title: provider.displayName, subtitle: "PersonalIsland · C-33F8",
            detail: detail, createdAt: Date(), updatedAt: Date(),
            isUnread: true, isResolved: kind != .needsPermission, isDismissed: false,
            provider: provider, projectName: "PersonalIsland", projectPath: nil,
            sessionAlias: "C-33F8", relatedAgentSessionID: "claude:s", relatedWorkCycleID: 1
        )
    }

    private final class RecordingPoster: AgentNotificationPosting {
        var posted: [(title: String, subtitle: String, body: String)] = []
        func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(true) }
        func post(title: String, subtitle: String, body: String, thread: String, identifier: String) {
            posted.append((title, subtitle, body))
        }
    }

    func testNotificationLocalizedRussianFinished() {
        let poster = RecordingPoster()
        let notifications = AgentNotificationManager(poster: poster, localization: manager(mode: .russian))
        notifications.post(item: makeItem(kind: .finished, detail: "Finished in 8:34"))

        XCTAssertEqual(poster.posted.count, 1)
        XCTAssertEqual(poster.posted[0].title, "Claude Code · PersonalIsland")
        XCTAssertEqual(poster.posted[0].subtitle, "C-33F8 · Завершено")
        XCTAssertEqual(poster.posted[0].body, "Завершено за 8:34")
    }

    func testNotificationLocalizedEnglishFinished() {
        let poster = RecordingPoster()
        let notifications = AgentNotificationManager(poster: poster, localization: manager(mode: .english))
        notifications.post(item: makeItem(kind: .finished, detail: "Finished in 8:34"))
        XCTAssertEqual(poster.posted[0].subtitle, "C-33F8 · Finished")
        XCTAssertEqual(poster.posted[0].body, "Finished in 8:34")
    }

    func testNotificationLocalizedPermissionAndFailed() {
        let poster = RecordingPoster()
        let notifications = AgentNotificationManager(poster: poster, localization: manager(mode: .russian))
        notifications.post(item: makeItem(kind: .needsPermission, detail: "Running xcodebuild test"))
        notifications.post(item: {
            var item = makeItem(kind: .failed, detail: "rate limit")
            item.dedupKey = "k2"
            return item
        }())

        XCTAssertEqual(poster.posted[0].subtitle, "C-33F8 · Требуется разрешение")
        XCTAssertEqual(poster.posted[0].body, "Выполняет xcodebuild test")
        XCTAssertEqual(poster.posted[1].subtitle, "C-33F8 · Ошибка")
        XCTAssertEqual(poster.posted[1].body, "лимит запросов")
    }

    func testPersistedEnglishDetailRendersRussian() {
        let lang = manager(mode: .russian)
        XCTAssertEqual(
            AttentionPresentation.detail(makeItem(kind: .finished, detail: "Finished in 8:34"), lang: lang),
            "Завершено за 8:34"
        )
        XCTAssertEqual(
            AttentionPresentation.detail(makeItem(kind: .finished, detail: "Finished"), lang: lang),
            "Завершено"
        )
        XCTAssertEqual(
            AttentionPresentation.detail(
                makeItem(kind: .needsPermission, detail: "Waiting for your permission"), lang: lang
            ),
            "Ожидает вашего разрешения"
        )
    }

    func testActivityLocalizationKeepsSubjects() {
        let lang = manager(mode: .russian)
        XCTAssertEqual(
            ActivityPresentation.localize("Running xcodebuild test", lang: lang),
            "Выполняет xcodebuild test"
        )
        XCTAssertEqual(
            ActivityPresentation.localize("Editing AppState.swift", lang: lang),
            "Изменяет AppState.swift"
        )
        XCTAssertEqual(
            ActivityPresentation.localize("Reading files", lang: lang),
            "Читает файлы"
        )
        XCTAssertEqual(
            ActivityPresentation.localize("Something unknown entirely", lang: lang),
            "Something unknown entirely"
        )
    }

    func testBrandsAndDataUntouchedInRussian() {
        let lang = manager(mode: .russian)
        let item = makeItem(kind: .finished, detail: "Finished in 8:34")
        XCTAssertEqual(item.title, "Claude Code")
        XCTAssertEqual(item.subtitle, "PersonalIsland · C-33F8")
        XCTAssertEqual(lang.string("action.revealInFinder"), "Показать в Finder")
    }

    func testTooltipKeysLocalizedBothLanguages() {
        let en = manager(mode: .english)
        XCTAssertEqual(en.string("attention.action.markRead"), "Mark as Read")
        XCTAssertEqual(en.string("attention.action.dismiss"), "Dismiss")
        XCTAssertEqual(en.string("agent.actions.help"), "Project actions")

        let ru = manager(mode: .russian)
        XCTAssertEqual(ru.string("attention.action.markRead"), "Отметить как прочитанное")
        XCTAssertEqual(ru.string("attention.action.dismiss"), "Скрыть")
        XCTAssertEqual(ru.string("agent.actions.help"), "Действия с проектом")
    }

    func testSidebarModuleTitlesLocalized() {
        let ru = manager(mode: .russian)
        XCTAssertEqual(ru.string("module.screenshots.title"), "Буфер скриншотов")
        XCTAssertEqual(ru.string("module.nowPlaying.title"), "Сейчас играет")
        XCTAssertEqual(ru.string("module.agents.title"), "AI-агенты")
        XCTAssertEqual(ru.string("module.attention.title"), "Внимание")
    }

    func testRelativeTimeLocalized() {
        let base = Date(timeIntervalSince1970: 500_000)
        let en = manager(mode: .english)
        let ru = manager(mode: .russian)
        XCTAssertEqual(AttentionPresentation.relativeTime(from: base, now: base.addingTimeInterval(30), lang: en), "now")
        XCTAssertEqual(AttentionPresentation.relativeTime(from: base, now: base.addingTimeInterval(300), lang: en), "5m ago")
        XCTAssertEqual(AttentionPresentation.relativeTime(from: base, now: base.addingTimeInterval(30), lang: ru), "сейчас")
        XCTAssertEqual(AttentionPresentation.relativeTime(from: base, now: base.addingTimeInterval(300), lang: ru), "5 мин назад")
        XCTAssertEqual(AttentionPresentation.relativeTime(from: base, now: base.addingTimeInterval(7200), lang: ru), "2 ч назад")
    }

    func testAgentStateLabelsLocalized() {
        let ru = manager(mode: .russian)
        XCTAssertEqual(ru.string(AgentSessionState.working.localizationKey), "Выполняется")
        XCTAssertEqual(ru.string(AgentSessionState.needsPermission.localizationKey), "Требуется разрешение")
        XCTAssertEqual(ru.string(AgentSessionState.stale.localizationKey), "Нет активности")
        let en = manager(mode: .english)
        XCTAssertEqual(en.string(AgentSessionState.working.localizationKey), "Working")
    }

    func testMenuKeysLocalized() {
        let ru = manager(mode: .russian)
        XCTAssertEqual(ru.string("menu.language"), "Язык")
        XCTAssertEqual(ru.string("menu.language.system"), "Системный")
        XCTAssertEqual(ru.string("menu.openIsland"), "Открыть остров")
        XCTAssertEqual(ru.string("menu.quit"), "Завершить PersonalIsland")
    }
}
