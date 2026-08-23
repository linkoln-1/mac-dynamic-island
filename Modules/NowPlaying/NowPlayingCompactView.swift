import SwiftUI

struct NowPlayingCompactView: View {
    @ObservedObject private var model: NowPlayingViewModel
    @ObservedObject private var lang = AppLanguageManager.shared
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
        .onAppear { model.startIfNeeded() }
    }

    private var wingLayout: some View {
        HStack(spacing: 0) {
            Group {
                if model.state.isEmpty {
                    emptyGlyph
                } else {
                    trackInfo
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: notchGapWidth)
            Group {
                if model.state.isEmpty {
                    emptyGlyph
                } else {
                    transportControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var inlineLayout: some View {
        HStack(spacing: 6) {
            if model.state.isEmpty {
                emptyGlyph
            } else {
                trackInfo
                transportControls
            }
        }
    }

    private var trackInfo: some View {
        HStack(spacing: 7) {
            MediaArtworkView(
                image: model.state.artwork,
                size: IslandMetrics.compactArtworkSize,
                cornerRadius: 6
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(model.state.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !model.state.artist.isEmpty {
                    Text(model.state.artist)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .layoutPriority(-1)
        }
    }

    private var transportControls: some View {
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

    private var emptyGlyph: some View {
        Image(systemName: "waveform")
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
    }
}
