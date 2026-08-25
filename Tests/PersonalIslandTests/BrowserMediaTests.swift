import XCTest
@testable import PersonalIsland

final class BrowserMediaNormalizationTests: XCTestCase {
    private func normalize(_ json: String, tabID: String = "tab-1") -> BrowserMediaSnapshot? {
        BrowserMediaNormalizer.normalize(
            tabID: tabID, probeJSON: Data(json.utf8), sampledAt: Date(timeIntervalSince1970: 1000)
        )
    }

    func testPlayingVideoProducesValidPlayingState() {
        let snapshot = normalize("""
        {"media":[{"paused":false,"ended":false,"ct":354.2,"dur":3818,"rs":4,"muted":false,"rate":1}],
         "meta":{"title":"Song","artist":"Artist","album":""},"dt":"Song - YouTube"}
        """)
        XCTAssertEqual(snapshot?.isPlaying, true)
        XCTAssertEqual(snapshot?.title, "Song")
        XCTAssertEqual(snapshot?.artist, "Artist")
        XCTAssertEqual(snapshot!.elapsed, 354.2, accuracy: 0.01)
        XCTAssertEqual(snapshot!.duration, 3818, accuracy: 0.01)
    }

    func testPausedVideoProducesPausedState() {
        let snapshot = normalize("""
        {"media":[{"paused":true,"ended":false,"ct":10,"dur":100,"rs":4,"muted":false,"rate":1}],
         "meta":{"title":"Song","artist":"A"},"dt":""}
        """)
        XCTAssertEqual(snapshot?.isPlaying, false)
        XCTAssertEqual(snapshot?.hasMedia, true)
    }

    func testEndedVideoIsNotPlaying() {
        let snapshot = normalize("""
        {"media":[{"paused":false,"ended":true,"ct":100,"dur":100,"rs":4,"muted":false,"rate":1}],
         "meta":{"title":"Song","artist":"A"},"dt":""}
        """)
        XCTAssertEqual(snapshot?.isPlaying, false)
    }

    func testInvalidDurationHandledSafely() {
        let snapshot = normalize("""
        {"media":[{"paused":false,"ended":false,"ct":5,"dur":null,"rs":4,"muted":false,"rate":1}],
         "meta":{"title":"Live","artist":""},"dt":""}
        """)
        XCTAssertEqual(snapshot?.duration, 0)
        XCTAssertEqual(snapshot?.isPlaying, true)
    }

    func testMissingMediaSessionFallsBackToDocumentTitle() {
        let snapshot = normalize("""
        {"media":[{"paused":false,"ended":false,"ct":5,"dur":60,"rs":4,"muted":false,"rate":1}],
         "meta":null,"dt":"Great Video - YouTube"}
        """)
        XCTAssertEqual(snapshot?.title, "Great Video")
        XCTAssertEqual(snapshot?.artist, "")
    }

    func testMissingArtistAllowed() {
        let snapshot = normalize("""
        {"media":[{"paused":false,"ended":false,"ct":5,"dur":60,"rs":4,"muted":false,"rate":1}],
         "meta":{"title":"Solo"},"dt":""}
        """)
        XCTAssertEqual(snapshot?.title, "Solo")
        XCTAssertEqual(snapshot?.artist, "")
    }

    func testNoMediaElementsReturnsNil() {
        XCTAssertNil(normalize(#"{"media":[],"meta":null,"dt":"Page"}"#))
        XCTAssertNil(normalize("not json"))
    }

    func testProbeOutputParsing() {
        let stdout = "TAB-A\t{\"media\":[{\"paused\":false,\"ended\":false,\"ct\":1,\"dur\":10,\"rs\":4,\"muted\":false,\"rate\":1}],\"meta\":{\"title\":\"X\",\"artist\":\"Y\"},\"dt\":\"\"}\nbroken line\n"
        let snapshots = ArcBrowserNowPlayingProvider.parseProbeOutput(stdout)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.tabID, "TAB-A")
        XCTAssertEqual(snapshots.first?.title, "X")
    }

    func testProbeOutputParsesArcDoubleEncodedPayload() {
        let payload = #""{\"media\":[{\"paused\":false,\"ended\":false,\"ct\":135,\"dur\":213,\"rs\":4,\"muted\":false,\"rate\":1}],\"meta\":{\"title\":\"Track\",\"artist\":\"Band\"},\"dt\":\"Track - YouTube\"}""#
        let snapshots = ArcBrowserNowPlayingProvider.parseProbeOutput("TAB-B\t" + payload + "\n")
        XCTAssertEqual(snapshots.count, 1, "Arc hands back the JS result as a JSON-encoded string")
        XCTAssertEqual(snapshots.first?.title, "Track")
        XCTAssertEqual(snapshots.first?.artist, "Band")
        XCTAssertEqual(snapshots.first?.isPlaying, true)
        XCTAssertEqual(snapshots.first?.elapsed, 135)
    }

    func testProbeScriptSeparatorSurvivesArcTerminology() {
        let script = ArcBrowserNowPlayingProvider.probeScript(mediaHosts: ["youtube.com"])
        XCTAssertFalse(
            script.contains("& tab &"),
            "inside a tell block `tab` resolves to Arc's tab class, not a tab character"
        )
        XCTAssertTrue(script.contains("\t"))
    }
}

final class BrowserCandidateRankingTests: XCTestCase {
    private func snapshot(_ id: String, playing: Bool, muted: Bool = false) -> BrowserMediaSnapshot {
        var snapshot = BrowserMediaSnapshot()
        snapshot.tabID = id
        snapshot.title = id
        snapshot.hasMedia = true
        snapshot.isPlaying = playing
        snapshot.isMuted = muted
        return snapshot
    }

    func testPlayingBeatsPaused() {
        let best = BrowserCandidateRanking.best(
            of: [snapshot("paused", playing: false), snapshot("playing", playing: true)],
            currentTabID: nil
        )
        XCTAssertEqual(best?.tabID, "playing")
    }

    func testCurrentCandidateStableAcrossTies() {
        let tabs = [snapshot("a", playing: true), snapshot("b", playing: true)]
        XCTAssertEqual(BrowserCandidateRanking.best(of: tabs, currentTabID: "b")?.tabID, "b")

        XCTAssertEqual(BrowserCandidateRanking.best(of: tabs, currentTabID: nil)?.tabID, "a")
    }

    func testUnmutedBeatsMuted() {
        let best = BrowserCandidateRanking.best(
            of: [snapshot("muted", playing: true, muted: true), snapshot("audible", playing: true)],
            currentTabID: nil
        )
        XCTAssertEqual(best?.tabID, "audible")
    }
}

final class MediaItemIdentityTests: XCTestCase {
    private func state(_ title: String, _ artist: String, _ duration: TimeInterval) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = title
        state.artist = artist
        state.duration = duration
        return state
    }

    func testSameItemMatchesAcrossSubSecondDurationDrift() {
        XCTAssertTrue(MediaItemIdentity.matches(
            state("Song", "Artist", 3818.0), state("Song", "Artist", 3817.9)
        ))
    }

    func testTitleOnlyMatchWhenOtherSourceLacksMetadata() {
        XCTAssertTrue(MediaItemIdentity.matches(
            state("Song", "Artist", 3818), state("Song", "", 0)
        ))
    }

    func testDifferentItemsDoNotMatch() {
        XCTAssertFalse(MediaItemIdentity.matches(
            state("Song A", "Artist", 100), state("Song B", "Artist", 100)
        ))
        XCTAssertFalse(MediaItemIdentity.matches(state("", "", 0), state("", "", 0)))
    }
}

final class ArcPermissionClassifierTests: XCTestCase {
    func testStatuses() {
        XCTAssertEqual(ArcPermissionClassifier.classify(exitCode: 0, stderr: ""), .authorized)
        XCTAssertEqual(
            ArcPermissionClassifier.classify(exitCode: 1, stderr: "execution error: Not authorized to send Apple events to Arc. (-1743)"),
            .denied
        )
        XCTAssertEqual(
            ArcPermissionClassifier.classify(exitCode: 1, stderr: "Arc got an error: Application isn't running. (-600)"),
            .appNotRunning
        )
        XCTAssertEqual(ArcPermissionClassifier.classify(exitCode: 1, stderr: "syntax error"), .failure)
    }
}
