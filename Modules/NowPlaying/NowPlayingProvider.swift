import Combine
import Foundation

protocol NowPlayingProviding: AnyObject {

    var statePublisher: AnyPublisher<NowPlayingState?, Never> { get }

    var canSeek: Bool { get }

    func start()
    func stop()

    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()

    func seek(to seconds: TimeInterval)
}
