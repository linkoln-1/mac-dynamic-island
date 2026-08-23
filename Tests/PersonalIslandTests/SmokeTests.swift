import XCTest
@testable import PersonalIsland

final class SmokeTests: XCTestCase {
    @MainActor
    func testModuleRegistryHasExactlyFourModulesInOrder() {
        let registry = ModuleRegistry()

        XCTAssertEqual(registry.modules.count, 4)
        XCTAssertEqual(
            registry.modules.map { $0.id },
            ["screenshots", "nowPlaying", "agents", "attention"]
        )
        XCTAssertTrue(registry.modules[0] is ScreenshotBufferModule)
        XCTAssertTrue(registry.modules[1] is NowPlayingModule)
        XCTAssertTrue(registry.modules[2] is AgentsModule)
        XCTAssertTrue(registry.modules[3] is AttentionModule)
    }

    @MainActor
    func testModuleLookupByID() {
        let registry = ModuleRegistry()

        XCTAssertNotNil(registry.module(withID: "screenshots"))
        XCTAssertNotNil(registry.module(withID: "nowPlaying"))
        XCTAssertNil(registry.module(withID: "does-not-exist"))
        XCTAssertEqual(registry.defaultModuleID, "screenshots")
    }

    @MainActor
    func testIslandStateMachineTransitions() {
        let state = IslandState()

        XCTAssertEqual(state.mode, .collapsed)
        state.expand()
        XCTAssertEqual(state.mode, .expanded)
        state.collapse()
        XCTAssertEqual(state.mode, .collapsed)
        state.showCompact()
        XCTAssertEqual(state.mode, .compact)
        state.expand()
        XCTAssertEqual(state.mode, .expanded)
    }

    @MainActor
    func testIslandTapExpandsFromCollapsedAndCompactOnly() {
        let state = IslandState()

        state.handleIslandTap()
        XCTAssertEqual(state.mode, .expanded)
        state.handleIslandTap()
        XCTAssertEqual(state.mode, .expanded)

        state.showCompact()
        state.handleIslandTap()
        XCTAssertEqual(state.mode, .expanded)
    }

    @MainActor
    func testDefaultSelectionIsFirstModule() {
        let state = IslandState()

        XCTAssertEqual(state.selectedModuleID, "screenshots")
        XCTAssertNotNil(state.selectedModule)
        state.select(moduleID: "nowPlaying")
        XCTAssertEqual(state.selectedModule?.id, "nowPlaying")
    }

    @MainActor
    func testCompactAvailabilityDrivesBaselineWhileNotExpanded() {
        let state = IslandState()

        XCTAssertEqual(state.mode, .collapsed)
        state.setCompactAvailable(true)
        XCTAssertEqual(state.mode, .compact)
        state.setCompactAvailable(false)
        XCTAssertEqual(state.mode, .collapsed)
    }

    @MainActor
    func testDismissExpandedReturnsToCurrentBaseline() {
        let state = IslandState()

        state.expand()
        state.dismissExpanded()
        XCTAssertEqual(state.mode, .collapsed)

        state.setCompactAvailable(true)
        state.expand()
        state.setCompactAvailable(false)
        XCTAssertEqual(state.mode, .expanded)
        state.setCompactAvailable(true)
        XCTAssertEqual(state.mode, .expanded)
        state.dismissExpanded()
        XCTAssertEqual(state.mode, .compact)
    }

    @MainActor
    func testCompactModuleIsNowPlaying() {
        let registry = ModuleRegistry()

        XCTAssertEqual(registry.compactModule?.id, "nowPlaying")
        XCTAssertFalse(ScreenshotBufferModule().providesCompactSummary)
    }

    func testVendoredAdapterScriptIsInAppResources() {
        let url = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
        XCTAssertNotNil(url, "mediaremote-adapter.pl missing from Contents/Resources")
    }

    func testVendoredAdapterTestClientIsInAppResources() {
        let url = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)
        XCTAssertNotNil(url, "MediaRemoteAdapterTestClient missing from Contents/Resources")
    }

    func testMediaRemoteAdapterFrameworkIsEmbedded() {
        let frameworkURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/MediaRemoteAdapter.framework")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: frameworkURL.path),
            "MediaRemoteAdapter.framework missing from Contents/Frameworks"
        )
    }
}
