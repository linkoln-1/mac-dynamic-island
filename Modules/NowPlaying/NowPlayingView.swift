import SwiftUI

struct NowPlayingView: View {
    @ObservedObject private var model: NowPlayingViewModel

    @State private var scrubFraction: Double?

    @MainActor
    init(model: NowPlayingViewModel? = nil) {
        _model = ObservedObject(wrappedValue: model ?? .shared)
    }

    var body: some View {
        Group {
            if model.state.isEmpty {
                emptyState
            } else {
                player
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.startIfNeeded() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing Playing")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Nothing playing")
    }

    private var player: some View {
        HStack(alignment: .center, spacing: 16) {
            MediaArtworkView(image: model.state.artwork, size: 132, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.state.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if !model.state.album.isEmpty {
                    Text(model.state.album)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                progressSection
                Spacer(minLength: 6)
                controls
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if model.state.isPlaying && scrubFraction == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                progressContent(at: context.date)
            }
        } else {
            progressContent(at: Date())
        }
    }

    private func progressContent(at now: Date) -> some View {
        let duration = model.state.duration
        let position = scrubFraction.map { $0 * duration } ?? model.state.position(at: now)
        let fraction = duration > 0 ? position / duration : 0
        return VStack(spacing: 4) {
            MediaSeekBar(
                fraction: fraction,
                isSeekable: model.canSeek && duration > 0,
                onScrub: { scrubFraction = $0 },
                onCommit: { committed in
                    scrubFraction = nil
                    model.seek(to: committed * duration)
                }
            )
            HStack {
                Text(MediaTimeFormatter.format(position))
                Spacer()
                Text(MediaTimeFormatter.format(duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            MediaControlButton(
                systemImage: "backward.fill",
                size: 14,
                label: "Previous track",
                hitTarget: IslandMetrics.expandedControlHitTarget
            ) {
                model.previousTrack()
            }
            .disabled(!model.canSkip)
            .opacity(model.canSkip ? 1 : 0.35)
            MediaControlButton(
                systemImage: model.state.isPlaying ? "pause.fill" : "play.fill",
                size: 20,
                label: model.state.isPlaying ? "Pause" : "Play",
                hitTarget: IslandMetrics.expandedControlHitTarget
            ) {
                model.togglePlayPause()
            }
            MediaControlButton(
                systemImage: "forward.fill",
                size: 14,
                label: "Next track",
                hitTarget: IslandMetrics.expandedControlHitTarget
            ) {
                model.nextTrack()
            }
            .disabled(!model.canSkip)
            .opacity(model.canSkip ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MediaArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .animation(.easeInOut(duration: 0.2), value: image.map(ObjectIdentifier.init))
        .accessibilityHidden(true)
    }
}

struct MediaControlButton: View {
    let systemImage: String
    let size: CGFloat
    let label: String
    var hitTarget: CGFloat = 28
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isHovering ? 0.12 : 0))
                Image(systemName: systemImage)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 1 : 0.85))
            }
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
    }
}

struct MediaSeekBar: View {
    let fraction: Double
    let isSeekable: Bool

    let onScrub: (Double) -> Void

    let onCommit: (Double) -> Void

    private static let barHeight: CGFloat = 4
    private static let hitHeight: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: Self.barHeight)
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: max(Self.barHeight, width * clamped(fraction)), height: Self.barHeight)
            }
            .frame(height: Self.hitHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isSeekable, width > 0 else { return }
                        onScrub(clamped(value.location.x / width))
                    }
                    .onEnded { value in
                        guard isSeekable, width > 0 else { return }
                        onCommit(clamped(value.location.x / width))
                    }
            )
        }
        .frame(height: Self.hitHeight)
        .accessibilityLabel("Playback progress")
        .accessibilityValue("\(Int(clamped(fraction) * 100)) percent")
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
