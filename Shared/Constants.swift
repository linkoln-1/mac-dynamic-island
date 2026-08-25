import SwiftUI

enum IslandMetrics {

    static let expandedSize = CGSize(width: 640, height: 256)

    static let shadowPadding: CGFloat = 20

    static var windowSize: CGSize {
        CGSize(width: expandedSize.width, height: expandedSize.height + shadowPadding)
    }

    static let compactExtraWidth: CGFloat = 260

    static let compactArtworkSize: CGFloat = 26
    static let compactControlHitTarget: CGFloat = 28

    static let expandedControlHitTarget: CGFloat = 32

    static let fallbackClosedSize = CGSize(width: 224, height: 38)

    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 14
    static let compactTopRadius: CGFloat = 6
    static let compactBottomRadius: CGFloat = 14
    static let expandedTopRadius: CGFloat = 19
    static let expandedBottomRadius: CGFloat = 24

    static let sidebarWidth: CGFloat = 44

    static let sidebarButtonHitTarget: CGFloat = 40

    static let expandedContentHorizontalInset: CGFloat = expandedTopRadius + 2

    static let expandedContentBottomInset: CGFloat = 6

    static let hoverScale: CGFloat = 1.03
    static let shadowRadius: CGFloat = 6

    static let hitTestMargin: CGFloat = 10
}

enum IslandAnimation {

    static let open = Animation.spring(response: 0.32, dampingFraction: 0.8, blendDuration: 0)
    static let close = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    static let interactive = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
}

enum ScreenshotBufferSettings {
    static let maxItems = 30
    static let thumbnailMaxDimension: CGFloat = 320
}

private struct NotchGapWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var notchGapWidth: CGFloat {
        get { self[NotchGapWidthKey.self] }
        set { self[NotchGapWidthKey.self] = newValue }
    }
}
