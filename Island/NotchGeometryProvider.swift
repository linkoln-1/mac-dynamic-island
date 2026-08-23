import AppKit

enum NotchGeometryProvider {

    static let fakeIslandWidth: CGFloat = 190

    static let fallbackBarHeight: CGFloat = 32

    static let notchEdgeOverlap: CGFloat = 4

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func closedSize(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        auxiliaryLeftWidth: CGFloat?,
        auxiliaryRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> CGSize {
        if safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
            return CGSize(
                width: screenWidth - left - right + notchEdgeOverlap,
                height: safeAreaTop
            )
        }
        return CGSize(
            width: fakeIslandWidth,
            height: menuBarHeight > 0 ? menuBarHeight : fallbackBarHeight
        )
    }

    static func closedSize(for screen: NSScreen) -> CGSize {
        closedSize(
            screenWidth: screen.frame.width,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }

    static func notchRect(screenFrame: CGRect, closedSize: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - closedSize.width / 2,
            y: screenFrame.maxY - closedSize.height,
            width: closedSize.width,
            height: closedSize.height
        )
    }

    static func notchRect(for screen: NSScreen) -> CGRect {
        notchRect(screenFrame: screen.frame, closedSize: closedSize(for: screen))
    }
}
