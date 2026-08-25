import SwiftUI

struct NowPlayingCompactView: View {
    @ObservedObject private var model: NowPlayingViewModel
    @Environment(\.notchGapWidth) private var notchGapWidth

    @MainActor
    init(model: NowPlayingViewModel? = nil) {
        _model = ObservedObject(wrappedValue: model ?? .shared)
    }

    var body: some View {
        Group {
            if notchGapWidth > 0 {
                wingLayout
            } else {
                inlineLayout
            }
        }
    }

    private var wingLayout: some View {
        HStack(spacing: 0) {
            NowPlayingCompactInfo(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchGapWidth)
            NowPlayingCompactControls(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inlineLayout: some View {
        HStack(spacing: 6) {
            NowPlayingCompactInfo(model: model)
            NowPlayingCompactControls(model: model)
        }
    }
}

struct NowPlayingCompactInfo: View {
    @ObservedObject private var model: NowPlayingViewModel

    @MainActor
    init(model: NowPlayingViewModel? = nil) {
        _model = ObservedObject(wrappedValue: model ?? .shared)
    }

    var body: some View {
        Group {
            if model.state.isEmpty {
                MediaEmptyGlyph()
            } else {
                MediaArtworkView(
                    image: model.state.artwork,
                    size: IslandMetrics.compactArtworkSize,
                    cornerRadius: 6
                )
                .help(model.state.title)
            }
        }
        .onAppear { model.startIfNeeded() }
    }
}

struct NowPlayingCompactControls: View {
    @ObservedObject private var model: NowPlayingViewModel
    @ObservedObject private var lang = AppLanguageManager.shared

    @MainActor
    init(model: NowPlayingViewModel? = nil) {
        _model = ObservedObject(wrappedValue: model ?? .shared)
    }

    var body: some View {
        if model.state.isEmpty {
            MediaEmptyGlyph()
        } else {
            HStack(spacing: 2) {
                MediaControlButton(
                    systemImage: "backward.fill",
                    size: 10,
                    label: lang.string("media.previous"),
                    hitTarget: IslandMetrics.compactControlHitTarget
                ) {
                    model.previousTrack()
                }
                .disabled(!model.canSkip)
                .opacity(model.canSkip ? 1 : 0.35)
                MediaControlButton(
                    systemImage: model.state.isPlaying ? "pause.fill" : "play.fill",
                    size: 12,
                    label: lang.string(model.state.isPlaying ? "media.pause" : "media.play"),
                    hitTarget: IslandMetrics.compactControlHitTarget
                ) {
                    model.togglePlayPause()
                }
                MediaControlButton(
                    systemImage: "forward.fill",
                    size: 10,
                    label: lang.string("media.next"),
                    hitTarget: IslandMetrics.compactControlHitTarget
                ) {
                    model.nextTrack()
                }
                .disabled(!model.canSkip)
                .opacity(model.canSkip ? 1 : 0.35)
            }
        }
    }
}

struct MediaEmptyGlyph: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
    }
}
