import AppKit
import XCTest
@testable import PersonalIsland

final class NowPlayingArbiterTests: XCTestCase {
    private var virtualNow = Date(timeIntervalSince1970: 10_000)
    private var arbiter: NowPlayingArbiter!

    override func setUp() {
        virtualNow = Date(timeIntervalSince1970: 10_000)
        arbiter = NowPlayingArbiter(
            config: .init(switchDebounce: 1.5, emptyGrace: 3.0, arcSnapshotLifetime: 6.0, pausedRetention: 600),
            now: { self.virtualNow }
        )
    }

    private func advance(_ seconds: TimeInterval) {
        virtualNow = virtualNow.addingTimeInterval(seconds)
    }

    private func mrState(_ title: String = "MR Song") -> NowPlayingState {
        var state = NowPlayingState()
        state.title = title
        state.artist = "Artist"
        state.duration = 300
        state.isPlaying = true
        return state
    }

    private func paused(_ state: NowPlayingState, at elapsed: TimeInterval) -> NowPlayingState {
        var copy = state
        copy.isPlaying = false
        copy.playbackRate = 0
        copy.elapsedTime = elapsed
        copy.elapsedTimestamp = virtualNow
        return copy
    }

    private func arcState(_ title: String = "Arc Song") -> NowPlayingState {
        var snapshot = BrowserMediaSnapshot()
        snapshot.tabID = "tab"
        snapshot.title = title
        snapshot.artist = "Artist"
        snapshot.duration = 300
        snapshot.isPlaying = true
        snapshot.hasMedia = true
        return snapshot.nowPlayingState()
    }

    func testMediaRemoteWinsWhenBothValid() {
        arbiter.ingestArc(arcState())
        let output = arbiter.ingestMediaRemote(mrState())
        XCTAssertEqual(output.source, .mediaRemote)
        XCTAssertEqual(output.state?.title, "MR Song")
    }

    func testArcWinsWhenMediaRemoteEmpty() {
        arbiter.ingestMediaRemote(nil)
        let output = arbiter.ingestArc(arcState())
        XCTAssertEqual(output.source, .arcBrowser)
        XCTAssertEqual(output.state?.title, "Arc Song")
    }

    func testMediaRemoteRegainsAuthorityOnSameItemWithoutDebounce() {
        arbiter.ingestMediaRemote(nil)
        arbiter.ingestArc(arcState("Same Song"))
        advance(0.3)
        let output = arbiter.ingestMediaRemote(mrState("Same Song"))
        XCTAssertEqual(output.source, .mediaRemote)
        XCTAssertEqual(output.state?.title, "Same Song")
    }

    func testTemporaryMediaRemoteDropoutKeepsLastGoodState() {
        arbiter.ingestMediaRemote(mrState())
        advance(1)
        let output = arbiter.ingestMediaRemote(nil)
        XCTAssertNotNil(output.state, "grace must hold the last good state")
        XCTAssertEqual(output.state?.title, "MR Song")

        advance(1)
        XCTAssertEqual(arbiter.ingestMediaRemote(mrState()).source, .mediaRemote)
    }

    func testBothEmptyBeyondGraceBecomesNothingPlaying() {
        arbiter.ingestMediaRemote(mrState())
        advance(1)
        arbiter.ingestMediaRemote(nil)
        advance(3.5)
        let output = arbiter.tick()
        XCTAssertNil(output.state)
        XCTAssertNil(output.source)
    }

    func testAntiFlapUnderRapidSourceChanges() {
        arbiter.ingestMediaRemote(mrState())
        advance(0.2)
        arbiter.ingestMediaRemote(nil)
        advance(0.2)
        arbiter.ingestMediaRemote(mrState())
        advance(0.2)
        arbiter.ingestMediaRemote(nil)
        advance(0.1)
        let flap = arbiter.ingestArc(arcState())

        XCTAssertEqual(flap.source, .mediaRemote, "debounce must suppress an instant flip")
        XCTAssertEqual(flap.state?.title, "MR Song")

        advance(2.0)
        let settled = arbiter.ingestArc(arcState())
        XCTAssertEqual(settled.source, .arcBrowser)
    }

    func testStaleArcSnapshotExpiresToNothingPlaying() {
        arbiter.ingestMediaRemote(nil)
        arbiter.ingestArc(arcState())
        advance(7)
        let heldOrEmpty = arbiter.tick()
        XCTAssertEqual(heldOrEmpty.state?.title, "Arc Song", "grace should hold briefly")
        advance(3.5)
        let output = arbiter.tick()
        XCTAssertNil(output.state)
    }

    func testRealStopReachesNothingPlayingAfterBoundedGrace() {
        arbiter.ingestMediaRemote(nil)
        arbiter.ingestArc(arcState())
        advance(1)
        arbiter.ingestArc(nil)
        advance(3.5)
        XCTAssertNil(arbiter.tick().state)
    }

    func testPausedMediaRemoteStaysVisibleWithinRetention() {
        arbiter.ingestMediaRemote(paused(mrState(), at: 42))
        advance(599)
        XCTAssertEqual(arbiter.tick().state?.title, "MR Song")
    }

    func testPausedMediaRemoteHidesAfterRetention() {
        arbiter.ingestMediaRemote(paused(mrState(), at: 42))
        advance(601 + 3.5)
        let output = arbiter.tick()
        XCTAssertNil(output.state, "a track paused for longer than the retention is not 'now playing'")
        XCTAssertNil(output.source)
    }

    func testPausedArcSnapshotRefreshedByProbesStillExpires() {
        arbiter.ingestMediaRemote(nil)
        var elapsedTotal: TimeInterval = 0
        while elapsedTotal <= 620 {
            arbiter.ingestArc(paused(arcState("Preview"), at: 3.37))
            advance(5)
            elapsedTotal += 5
        }
        XCTAssertNil(arbiter.tick().state, "re-probing the same paused tab must not keep it alive forever")
    }

    func testPlayingMediaNeverExpires() {
        arbiter.ingestMediaRemote(mrState())
        advance(3 * 3600)
        XCTAssertEqual(arbiter.tick().state?.title, "MR Song")
    }

    func testResumingAfterHiddenPauseShowsImmediately() {
        arbiter.ingestMediaRemote(paused(mrState(), at: 42))
        advance(700)
        XCTAssertNil(arbiter.tick().state)

        let output = arbiter.ingestMediaRemote(mrState())
        XCTAssertEqual(output.source, .mediaRemote)
        XCTAssertEqual(output.state?.title, "MR Song")
    }

    func testSeekingWhilePausedRestartsRetention() {
        arbiter.ingestMediaRemote(paused(mrState(), at: 10))
        advance(500)
        arbiter.ingestMediaRemote(paused(mrState(), at: 90))
        advance(500)
        XCTAssertEqual(arbiter.tick().state?.title, "MR Song", "the user touched the item — it is fresh again")
        advance(200)
        XCTAssertNil(arbiter.tick().state)
    }

    func testExpiredPausedMediaRemoteFallsThroughToPlayingArc() {
        arbiter.ingestMediaRemote(paused(mrState(), at: 42))
        advance(700)
        let output = arbiter.ingestArc(arcState())
        XCTAssertEqual(output.source, .arcBrowser)
        XCTAssertEqual(output.state?.title, "Arc Song")
    }

    private func image() -> NSImage { NSImage(size: NSSize(width: 1, height: 1)) }

    func testArcFallbackInheritsArtworkSeenViaMediaRemote() {
        let art = image()
        var withArt = mrState("Same Song")
        withArt.artwork = art
        arbiter.ingestMediaRemote(withArt)
        advance(1)
        arbiter.ingestMediaRemote(nil)
        advance(2)

        let output = arbiter.ingestArc(arcState("Same Song"))

        XCTAssertEqual(output.source, .arcBrowser)
        XCTAssertTrue(output.state?.artwork === art, "artwork must survive the fall back to Arc")
    }

    func testMediaRemoteReturningWithoutArtworkKeepsRememberedArtwork() {
        let art = image()
        var withArt = mrState("Same Song")
        withArt.artwork = art
        arbiter.ingestMediaRemote(withArt)
        advance(1)
        arbiter.ingestMediaRemote(nil)
        advance(4)
        XCTAssertNil(arbiter.tick().state)

        let output = arbiter.ingestMediaRemote(mrState("Same Song"))

        XCTAssertEqual(output.source, .mediaRemote)
        XCTAssertTrue(output.state?.artwork === art, "artwork must return with the same item")
    }

    func testDifferentItemDoesNotInheritArtwork() {
        var withArt = mrState("First Song")
        withArt.artwork = image()
        arbiter.ingestMediaRemote(withArt)
        advance(1)
        arbiter.ingestMediaRemote(nil)
        advance(2)

        let output = arbiter.ingestArc(arcState("Second Song"))

        XCTAssertNil(output.state?.artwork)
    }
}
