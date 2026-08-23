import Combine
import XCTest
@testable import PersonalIsland

private enum SampleLines {
    static let full = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","playing":true,\
    "title":"Test Track","artist":"Test Artist","album":"Test Album","duration":180.5,\
    "elapsedTime":42.25,"timestamp":"2026-08-22T10:00:00Z","playbackRate":1}}
    """
    static let browserHelper = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome.helper",\
    "parentApplicationBundleIdentifier":"com.google.Chrome","playing":true,"title":"Video"}}
    """
    static let diffPause = """
    {"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0,"elapsedTime":50}}
    """
    static let diffRemoveAlbum = """
    {"type":"data","diff":true,"payload":{"album":null}}
    """
    static let diffRemoveArtwork = """
    {"type":"data","diff":true,"payload":{"artworkData":null}}
    """
    static let empty = #"{"type":"data","diff":false,"payload":{}}"#
    static let malformed = "this is not json {{{"

    static let artworkBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    static let fullWithArtwork = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,\
    "title":"Art Track","artist":"Art Artist","duration":100,"elapsedTime":1,\
    "timestamp":"2026-08-22T10:00:00Z","playbackRate":1,"artworkData":"\(artworkBase64)",\
    "artworkMimeType":"image/png"}}
    """
}

final class NowPlayingMappingTests: XCTestCase {
    private func assertState(
        _ result: AdapterLineResult, file: StaticString = #filePath, line: UInt = #line
    ) -> NowPlayingState? {
        guard case .state(let state) = result else {
            XCTFail("expected .state, got .ignored", file: file, line: line)
            return nil
        }
        return state
    }

    func testFullPayloadMapsAllFields() {
        let processor = AdapterEventProcessor()

        let state = assertState(processor.process(line: SampleLines.full))

        XCTAssertEqual(state?.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(state?.title, "Test Track")
        XCTAssertEqual(state?.artist, "Test Artist")
        XCTAssertEqual(state?.album, "Test Album")
        XCTAssertEqual(state?.isPlaying, true)
        XCTAssertEqual(state?.duration ?? 0, 180.5, accuracy: 0.001)
        XCTAssertEqual(state?.elapsedTime ?? 0, 42.25, accuracy: 0.001)
        XCTAssertEqual(state?.playbackRate ?? 0, 1, accuracy: 0.001)
        let expectedDate = ISO8601DateFormatter().date(from: "2026-08-22T10:00:00Z")
        XCTAssertEqual(state?.elapsedTimestamp, expectedDate)
    }

    func testParentBundleIdentifierPreferredOverHelper() {
        let processor = AdapterEventProcessor()

        let state = assertState(processor.process(line: SampleLines.browserHelper))

        XCTAssertEqual(state?.bundleIdentifier, "com.google.Chrome")
    }

    func testDiffUpdateMergesOverPreviousState() {
        let processor = AdapterEventProcessor()
        _ = processor.process(line: SampleLines.full)

        let state = assertState(processor.process(line: SampleLines.diffPause))

        XCTAssertEqual(state?.title, "Test Track")
        XCTAssertEqual(state?.isPlaying, false)
        XCTAssertEqual(state?.playbackRate ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(state?.elapsedTime ?? 0, 50, accuracy: 0.001)
    }

    func testDiffNullRemovesKey() {
        let processor = AdapterEventProcessor()
        _ = processor.process(line: SampleLines.full)

        let state = assertState(processor.process(line: SampleLines.diffRemoveAlbum))

        XCTAssertEqual(state?.album, "")
        XCTAssertEqual(state?.title, "Test Track")
    }

    func testEmptyPayloadMeansNothingPlaying() {
        let processor = AdapterEventProcessor()
        _ = processor.process(line: SampleLines.full)

        guard case .state(let state) = processor.process(line: SampleLines.empty) else {
            return XCTFail("expected .state(nil)")
        }
        XCTAssertNil(state)
    }

    func testMalformedLineIgnoredAndStatePreserved() {
        let processor = AdapterEventProcessor()
        _ = processor.process(line: SampleLines.full)

        guard case .ignored = processor.process(line: SampleLines.malformed) else {
            return XCTFail("malformed line must be ignored")
        }

        let state = assertState(processor.process(line: SampleLines.diffPause))
        XCTAssertEqual(state?.title, "Test Track")
    }

    func testArtworkDecodedFromBase64AndCached() {
        let processor = AdapterEventProcessor()

        let first = assertState(processor.process(line: SampleLines.fullWithArtwork))
        let second = assertState(processor.process(line: SampleLines.fullWithArtwork))

        XCTAssertNotNil(first?.artwork)

        XCTAssertTrue(first?.artwork === second?.artwork)
    }

    func testArtworkKeptWhenItVanishesForSameTrack() {
        let processor = AdapterEventProcessor()
        let withArt = assertState(processor.process(line: SampleLines.fullWithArtwork))

        let afterVanish = assertState(processor.process(line: SampleLines.diffRemoveArtwork))

        XCTAssertNotNil(afterVanish?.artwork)
        XCTAssertTrue(afterVanish?.artwork === withArt?.artwork)
    }
}

final class NDJSONLineBufferTests: XCTestCase {
    func testPartialLineIsBufferedUntilNewline() {
        var buffer = NDJSONLineBuffer()

        XCTAssertTrue(buffer.append(Data("{\"a\":1".utf8)).isEmpty)
        let lines = buffer.append(Data("}\n".utf8))

        XCTAssertEqual(lines, ["{\"a\":1}"])
    }

    func testMultipleLinesInOneChunk() {
        var buffer = NDJSONLineBuffer()

        let lines = buffer.append(Data("first\nsecond\npartial".utf8))

        XCTAssertEqual(lines, ["first", "second"])
        XCTAssertEqual(buffer.append(Data("\n".utf8)), ["partial"])
    }
}

final class NowPlayingPositionTests: XCTestCase {
    private func makeState(
        elapsed: TimeInterval, rate: Double, playing: Bool, duration: TimeInterval, at date: Date
    ) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "T"
        state.elapsedTime = elapsed
        state.playbackRate = rate
        state.isPlaying = playing
        state.duration = duration
        state.elapsedTimestamp = date
        return state
    }

    func testPositionAdvancesWhilePlaying() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let state = makeState(elapsed: 10, rate: 1, playing: true, duration: 100, at: anchor)

        XCTAssertEqual(state.position(at: anchor.addingTimeInterval(5)), 15, accuracy: 0.001)
    }

    func testPositionUsesPlaybackRate() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let state = makeState(elapsed: 10, rate: 2, playing: true, duration: 100, at: anchor)

        XCTAssertEqual(state.position(at: anchor.addingTimeInterval(5)), 20, accuracy: 0.001)
    }

    func testPositionStaticWhenPaused() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let state = makeState(elapsed: 10, rate: 0, playing: false, duration: 100, at: anchor)

        XCTAssertEqual(state.position(at: anchor.addingTimeInterval(60)), 10, accuracy: 0.001)
    }

    func testPositionClampedToDuration() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let state = makeState(elapsed: 95, rate: 1, playing: true, duration: 100, at: anchor)

        XCTAssertEqual(state.position(at: anchor.addingTimeInterval(30)), 100, accuracy: 0.001)
    }

    func testPositionNeverNegative() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let state = makeState(elapsed: 5, rate: 1, playing: true, duration: 100, at: anchor)

        XCTAssertEqual(state.position(at: anchor.addingTimeInterval(-20)), 0, accuracy: 0.001)
    }
}

private final class FakeNowPlayingProvider: NowPlayingProviding {
    let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }
    let canSeek = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var seekValues: [TimeInterval] = []

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func play() {}
    func pause() {}
    func togglePlayPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func seek(to seconds: TimeInterval) { seekValues.append(seconds) }
}

@MainActor
final class NowPlayingProviderSelectionTests: XCTestCase {
    private func makeViewModel(
        testResult: Bool, adapter: FakeNowPlayingProvider, fallback: FakeNowPlayingProvider
    ) -> NowPlayingViewModel {
        NowPlayingViewModel(factory: .init(
            runAdapterTest: { testResult },
            makeAdapter: { _ in adapter },
            makeFallback: { fallback }
        ))
    }

    func testAdapterSelectedWhenTestPasses() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: true, adapter: adapter, fallback: fallback)

        await viewModel.activateProvider()

        XCTAssertEqual(adapter.startCount, 1)
        XCTAssertEqual(fallback.startCount, 0)
        XCTAssertFalse(viewModel.isUsingFallback)
        XCTAssertTrue(viewModel.canSeek)
    }

    func testFallbackSelectedWhenTestFails() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: false, adapter: adapter, fallback: fallback)

        await viewModel.activateProvider()

        XCTAssertEqual(adapter.startCount, 0)
        XCTAssertEqual(fallback.startCount, 1)
        XCTAssertTrue(viewModel.isUsingFallback)
    }

    func testPermanentAdapterFailureSwitchesToFallback() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: true, adapter: adapter, fallback: fallback)
        await viewModel.activateProvider()

        viewModel.switchToFallback()

        XCTAssertEqual(adapter.stopCount, 1)
        XCTAssertEqual(fallback.startCount, 1)
        XCTAssertTrue(viewModel.isUsingFallback)
    }

    func testStartIfNeededIsIdempotent() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: true, adapter: adapter, fallback: fallback)

        let firstTask = viewModel.startIfNeeded()
        XCTAssertNotNil(firstTask)
        XCTAssertNil(viewModel.startIfNeeded())
        await firstTask?.value

        XCTAssertEqual(adapter.startCount, 1)
    }

    func testProviderStateFlowsToViewModelAndNilMeansEmpty() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: true, adapter: adapter, fallback: fallback)
        await viewModel.activateProvider()

        var playing = NowPlayingState()
        playing.title = "Flowing"
        playing.artist = "Artist"
        let received = expectation(description: "state received")
        let cancellable = viewModel.$state.dropFirst().sink { state in
            if state.title == "Flowing" { received.fulfill() }
        }
        adapter.subject.send(playing)
        await fulfillment(of: [received], timeout: 2)

        let cleared = expectation(description: "state cleared")
        let clearCancellable = viewModel.$state.dropFirst().sink { state in
            if state.isEmpty { cleared.fulfill() }
        }
        adapter.subject.send(nil)
        await fulfillment(of: [cleared], timeout: 2)

        XCTAssertTrue(viewModel.state.isEmpty)
        cancellable.cancel()
        clearCancellable.cancel()
    }

    func testSeekForwardsToProviderWithOptimisticUpdate() async {
        let adapter = FakeNowPlayingProvider()
        let fallback = FakeNowPlayingProvider()
        let viewModel = makeViewModel(testResult: true, adapter: adapter, fallback: fallback)
        await viewModel.activateProvider()

        var playing = NowPlayingState()
        playing.title = "Seekable"
        playing.duration = 200
        let received = expectation(description: "state received")
        let cancellable = viewModel.$state.dropFirst().sink { state in
            if state.title == "Seekable" { received.fulfill() }
        }
        adapter.subject.send(playing)
        await fulfillment(of: [received], timeout: 2)
        cancellable.cancel()

        viewModel.seek(to: 90)

        XCTAssertEqual(adapter.seekValues, [90])
        XCTAssertEqual(viewModel.state.elapsedTime, 90, accuracy: 0.001)
    }
}
