import SwiftUI

struct IslandRootView: View {
    @ObservedObject var state: IslandState

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(
            maxWidth: IslandMetrics.windowSize.width,
            maxHeight: IslandMetrics.windowSize.height,
            alignment: .top
        )
        .preferredColorScheme(.dark)
    }

    private var island: some View {
        interior
            .frame(width: islandSize.width, height: islandSize.height)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius))

            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
                    .padding(.horizontal, topRadius)
            }
            .compositingGroup()
            .scaleEffect(hoverScale, anchor: .top)
            .shadow(color: shadowColor, radius: IslandMetrics.shadowRadius)
            .animation(state.mode == .expanded ? IslandAnimation.open : IslandAnimation.close, value: state.mode)
            .animation(IslandAnimation.interactive, value: state.isHovering)
            .contentShape(Rectangle())
            .onHover { hovering in

                state.hoverChanged(hovering)
            }

            .gesture(
                TapGesture().onEnded { state.handleIslandTap() },
                isEnabled: state.mode != .expanded
            )
    }

    private var interior: some View {
        ZStack {
            switch state.mode {
            case .collapsed:
                Color.black
                    .transition(.opacity)
            case .compact:
                compactContent
                    .transition(.opacity)
            case .expanded:
                IslandContainer(state: state)
                    .transition(.opacity)
            }
        }
    }

    private var compactContent: some View {
        CompactSurfaceView()
            .environment(\.notchGapWidth, state.closedSize.width)
            .padding(.horizontal, 4)
    }

    private var islandSize: CGSize {
        switch state.mode {
        case .collapsed:
            return state.closedSize
        case .compact:
            return CGSize(
                width: state.closedSize.width + IslandMetrics.compactExtraWidth + state.compactWidthBonus,
                height: state.closedSize.height
            )
        case .expanded:
            return IslandMetrics.expandedSize
        }
    }

    private var topRadius: CGFloat {
        switch state.mode {
        case .collapsed: return IslandMetrics.collapsedTopRadius
        case .compact: return IslandMetrics.compactTopRadius
        case .expanded: return IslandMetrics.expandedTopRadius
        }
    }

    private var bottomRadius: CGFloat {
        switch state.mode {
        case .collapsed: return IslandMetrics.collapsedBottomRadius
        case .compact: return IslandMetrics.compactBottomRadius
        case .expanded: return IslandMetrics.expandedBottomRadius
        }
    }

    private var hoverScale: CGFloat {
        state.isHovering && state.mode != .expanded ? IslandMetrics.hoverScale : 1.0
    }

    private var shadowColor: Color {
        if state.mode == .expanded {
            return .black.opacity(0.7)
        }
        return state.isHovering ? .black.opacity(0.5) : .clear
    }
}
