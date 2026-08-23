import AppKit
import SwiftUI

enum IslandHitTest {

    static func interactiveRect(
        mode: IslandMode,
        closedSize: CGSize,
        bounds: CGRect,
        margin: CGFloat = IslandMetrics.hitTestMargin,
        compactWidthBonus: CGFloat = 0
    ) -> CGRect {
        let islandSize: CGSize
        switch mode {
        case .collapsed:
            islandSize = closedSize
        case .compact:
            islandSize = CGSize(
                width: closedSize.width + IslandMetrics.compactExtraWidth + compactWidthBonus,
                height: closedSize.height
            )
        case .expanded:
            islandSize = IslandMetrics.expandedSize
        }
        let width = min(islandSize.width + margin * 2, bounds.width)
        let height = min(islandSize.height + margin, bounds.height)
        return CGRect(
            x: bounds.midX - width / 2,

            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }
}

final class IslandHitTestContainerView: NSView {
    private let state: IslandState

    @MainActor
    init(state: IslandState) {
        self.state = state
        super.init(frame: NSRect(origin: .zero, size: IslandMetrics.windowSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)

        let rect = MainActor.assumeIsolated {
            IslandHitTest.interactiveRect(
                mode: state.mode,
                closedSize: state.closedSize,
                bounds: bounds,
                compactWidthBonus: state.compactWidthBonus
            )
        }
        guard rect.contains(local) else { return nil }
        return super.hitTest(point)
    }
}
