import AppKit

private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

@MainActor
final class NotchSpaceManager {
    static let shared = NotchSpaceManager()

    private let space: CGSSpaceID
    private let isActive: Bool

    private init() {
        let connection = _CGSDefaultConnection()
        let created = CGSSpaceCreate(connection, 0x1, nil)
        if created != 0 {
            CGSSpaceSetAbsoluteLevel(connection, created, 2147483647)
            CGSShowSpaces(connection, [created] as NSArray)
            space = created
            isActive = true
            Log.island.info("Notch space created (id \(created))")
        } else {
            space = 0
            isActive = false
            Log.island.warning("CGSSpaceCreate failed — island runs without the private space (fullscreen coverage reduced)")
        }
    }

    func add(_ window: NSWindow) {
        guard isActive, window.windowNumber > 0 else { return }
        CGSAddWindowsToSpaces(_CGSDefaultConnection(), [window.windowNumber] as NSArray, [space] as NSArray)
    }

    func remove(_ window: NSWindow) {
        guard isActive, window.windowNumber > 0 else { return }
        CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(), [window.windowNumber] as NSArray, [space] as NSArray)
    }
}
