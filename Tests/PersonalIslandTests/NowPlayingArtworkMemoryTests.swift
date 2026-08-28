import AppKit
import XCTest
@testable import PersonalIsland

final class NowPlayingArtworkMemoryTests: XCTestCase {
    private func image() -> NSImage { NSImage(size: NSSize(width: 1, height: 1)) }

    private func state(
        _ title: String, artist: String = "Artist", duration: TimeInterval = 300, artwork: NSImage? = nil
    ) -> NowPlayingState {
        var state = NowPlayingState()
        state.title = title
        state.artist = artist
        state.duration = duration
        state.artwork = artwork
        return state
    }

    func testRestoresRememberedArtworkForSameItem() {
        var memory = NowPlayingArtworkMemory()
        let art = image()
        memory.remember(state("Song", artwork: art))

        let restored = memory.restoring(state("Song"))

        XCTAssertTrue(restored.artwork === art)
    }

    func testDoesNotRestoreArtworkForDifferentItem() {
        var memory = NowPlayingArtworkMemory()
        memory.remember(state("Song", artwork: image()))

        XCTAssertNil(memory.restoring(state("Other")).artwork)
    }

    func testKeepsPresentArtworkUntouched() {
        var memory = NowPlayingArtworkMemory()
        memory.remember(state("Song", artwork: image()))
        let fresh = image()

        let restored = memory.restoring(state("Song", artwork: fresh))

        XCTAssertTrue(restored.artwork === fresh)
    }

    func testNewerArtworkForSameItemReplacesOlder() {
        var memory = NowPlayingArtworkMemory()
        memory.remember(state("Song", artwork: image()))
        let newer = image()
        memory.remember(state("Song", artwork: newer))

        XCTAssertTrue(memory.restoring(state("Song")).artwork === newer)
    }

    func testFallsBackToTitleMatchWhenDurationDiffers() {
        var memory = NowPlayingArtworkMemory()
        let art = image()
        memory.remember(state("Song", duration: 6683, artwork: art))

        let restored = memory.restoring(state("Song", duration: 0))

        XCTAssertTrue(restored.artwork === art)
    }

    func testIgnoresEmptyStatesAndMissingArtwork() {
        var memory = NowPlayingArtworkMemory()
        memory.remember(state("", artist: "", artwork: image()))
        memory.remember(state("Song"))

        XCTAssertNil(memory.restoring(state("")).artwork)
        XCTAssertNil(memory.restoring(state("Song")).artwork)
    }

    func testEvictsOldestBeyondCapacity() {
        var memory = NowPlayingArtworkMemory(capacity: 2)
        let first = image()
        memory.remember(state("One", artwork: first))
        memory.remember(state("Two", artwork: image()))
        memory.remember(state("Three", artwork: image()))

        XCTAssertNil(memory.restoring(state("One")).artwork)
        XCTAssertNotNil(memory.restoring(state("Two")).artwork)
        XCTAssertNotNil(memory.restoring(state("Three")).artwork)
    }
}
