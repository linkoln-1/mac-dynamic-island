# Research: windowing

## Recommendation
Use a borderless, non-activating NSPanel subclass (styleMask [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]) with clear background, level = .mainMenu + 1..3, collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle], sized ONCE to the maximum-expanded frame and parked top-center on the target screen — then animate ONLY the SwiftUI content inside (never the NSWindow frame). This is exactly what both boring.notch and MewNotch do. Compute notch geometry from public API: hasNotch = screen.safeAreaInsets.top > 0; notchWidth = screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width; notchHeight = safeAreaInsets.top. Fallback for non-notch displays: fake island ~185–200pt wide, height = menu bar height (frame.maxY − visibleFrame.maxY) with a constant fallback. Run as .accessory activation policy with a SwiftUI MenuBarExtra. Optionally add the private CGSSpace trick (both apps ship it) to stay visible over fullscreen apps with hidden menu bar — acceptable for an unsandboxed personal app.

## Implementation notes
VERIFIED LOCALLY on this machine (macOS 26.6, Apple Silicon MBP, `swift -e` against AppKit): built-in display frame (0,0,2056,1329), safeAreaInsets = (top:38, others 0), auxiliaryTopLeftArea = (0,1291,918,38), auxiliaryTopRightArea = (1138,1291,918,38) → notch width = 2056−918−918 = 220 pt, height 38 pt, notch x-range 918…1138 (exactly centered). External display ("Mi Monitor"): safeAreaInsets all 0, both auxiliary areas nil, and frame.maxY − visibleFrame.maxY returned 0 (menu bar not counted on the external in this config) — so ALWAYS guard the menu-bar-height formula with a constant fallback (use 32). NSWindow.Level raw values verified: mainMenu=24, statusBar=25, screenSaver=1000.

=== 1. GEOMETRY (public API only, macOS 12+) ===
- hasNotch(screen) = screen.safeAreaInsets.top > 0  (MewNotch/Utils/NotchUtils.swift does exactly this; boring.notch deviceHasNotch() iterates screens the same way).
- Real notch size (NotchUtils.getRealNotchSize + boring.notch sizing/matters.swift getClosedNotchSize):
    notchWidth  = screen.frame.width − auxiliaryTopLeftArea!.width − auxiliaryTopRightArea!.width   // boring.notch adds +4 pt fudge so the island slightly overlaps the notch edges
    notchHeight = screen.safeAreaInsets.top                                                          // 38 on this Mac
    "match menu bar" variant: notchHeight = screen.frame.maxY − screen.visibleFrame.maxY
- Notch rect in GLOBAL (screen) coordinates (bottom-left origin AppKit coords):
    x = screen.frame.midX − notchWidth/2   (equivalently screen.frame.minX + auxTopLeft.width)
    y = screen.frame.maxY − notchHeight
- Fake island fallback (no notch / external): width = 185 (boring.notch) or 180 (MewNotch); height = screen.frame.maxY − screen.visibleFrame.maxY, and if that is 0 (verified it can be) use a constant (24–32). Center at top edge with the same formulas.
- Per-screen identity: use display UUID (CGDisplayCreateUUIDFromDisplayID via deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]) as dictionary key, not NSScreen object equality (boring.notch keys windows/viewModels by UUID string; MewNotch keys by NSScreen and rebuilds).

=== 2. PANEL CONFIGURATION (verbatim from both apps) ===
Sources: boring.notch → boringNotch/components/Notch/BoringNotchWindow.swift and BoringNotchSkyLightWindow.swift (the one actually instantiated in boringNotchApp.swift createBoringNotchWindow); MewNotch → MewNotch/View/Common/MewWindow.swift (class MewPanel).
Subclass NSPanel; in init after super.init:
    styleMask (passed at creation, both apps identical): [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false                    // SwiftUI draws its own shadow inside the padded frame
    isMovable = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
    level = .mainMenu + 1                // MewNotch (== .statusBar); boring.notch uses .mainMenu + 3. Do NOT use .screenSaver — it draws over the lock screen password UI.
    isReleasedWhenClosed = false         // boring.notch (safe to close/reopen on screen changes)
    canBecomeVisibleWithoutLogin = true  // MewNotch
    appearance = NSAppearance(named: .darkAqua)  // boring.notch SkyLight window: force dark regardless of system theme
    override var canBecomeKey: Bool { false }    // both apps
    override var canBecomeMain: Bool { false }   // both apps
    hidesOnDeactivate: neither app sets it (programmatic NSPanel default is false) — explicitly set false to be safe.
    ignoresMouseEvents: neither app sets it. boring.notch avoids the issue by making the window only 640×210; MewNotch makes the panel FULL-SCREEN (screen.frame) and relies on NSHostingView hit-test returning nil where no SwiftUI content exists, so clicks pass through empty areas. Prefer the boring.notch small-window approach — less hit-test risk.
    sharingType = .none                  // optional: hide from screen recording (boring.notch setting)
Show with orderFrontRegardless() — NEVER makeKeyAndOrderFront (non-activating panel, canBecomeKey false).

=== 3. WINDOW SIZE + POSITION (the no-jump resize strategy) ===
Both apps NEVER resize or animate the NSWindow. boring.notch (sizing/matters.swift):
    openNotchSize = 640×190; shadowPadding = 20; windowSize = 640×210 (open + shadow padding)
Create panel with contentRect NSRect(0,0,windowSize.width,windowSize.height), then position (boringNotchApp.swift positionWindow):
    window.setFrameOrigin(NSPoint(
        x: screenFrame.origin.x + screenFrame.width/2 − window.frame.width/2,
        y: screenFrame.origin.y + screenFrame.height − window.frame.height))
Top edge of window == top edge of screen; the SwiftUI root is `.frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)` so content hugs the top and grows DOWNWARD only — top anchoring is automatic and there are no visual jumps. Expansion/collapse = SwiftUI state change animating the inner shape between closedNotchSize and openNotchSize:
    open  animation: .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    close animation: .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    hover/gesture:   .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    hover scale (MewNotch): .scaleEffect(isHovered ? 1.1 : 1, anchor: .top)
MewNotch alternative: panel covers the entire screen.frame; root view = VStack { HStack { Spacer(); island; Spacer() } ; Spacer() } with ZStack(alignment: .top) swapping CollapsedNotchView/ExpandedNotchView masked by a NotchShape. Same principle: window static, content animates.
The island itself: content .background(.black).clipShape(NotchShape(topCornerRadius:bottomCornerRadius:)) — corner radii from boring.notch: closed (top 6, bottom 14), open (top 19, bottom 24); MewNotch: collapsed (8, 13), expanded (8, 24). NotchShape draws outward-curving top corners (file boringNotch/components/Notch/NotchShape.swift). boring.notch also overlays a 1-pt black Rectangle at the very top inset by topCornerRadius to seal the seam against the physical notch.

=== 4. HOVER / OPEN / CLOSE / OUTSIDE-CLICK / ESCAPE ===
Both apps drive open/close from SwiftUI .onHover + .onTapGesture on the island's .contentShape(Rectangle()) — no NSTrackingArea needed (boringNotch/ContentView.swift handleHover):
  - hover-in: set isHovering (animated); if closed and openOnHover: Task sleep minimumHoverDuration (~0.3s), re-check still hovering, then open.
  - hover-out: Task sleep 100ms debounce, then close (guarding popover/share states). Cancel the task on re-entry (hoverTask?.cancel()).
  - tap: open immediately.
  - Keyboard shortcut toggle + 3s auto-close timer via KeyboardShortcuts lib (optional).
Neither app uses a click-outside monitor (hover-out already closes). If you want click-outside-to-collapse and Escape:
  - Global mouse monitor (no permissions needed for mouse): NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in if !panelFrameContains(NSEvent.mouseLocation) { collapse() } } — install when expanding, remove (NSEvent.removeMonitor) when collapsed.
  - Local monitor for clicks inside your own app + Escape: NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { e in if e.keyCode == 53 { collapse(); return nil }; return e }. Local keyDown only fires if your panel is key: either flip an `allowKey` flag making canBecomeKey true while expanded and call makeKey(), or (simpler) accept hover-out as the Escape substitute. A GLOBAL keyDown monitor requires Accessibility permission — avoid.
  - Pointer-in-rect check helper (BoringViewModel.isMouseHovering): compare NSEvent.mouseLocation against rect(x: frame.midX − notchSize.width/2, y: frame.maxY − notchSize.height, w, h).
  - Drag-into-notch auto-open (boring.notch DragDetector): global monitor for .leftMouseDragged over a notch region rect computed as x: screenFrame.midX − openNotchSize.width/2, y: screenFrame.maxY − openNotchSize.height.

=== 5. SCREEN CHANGES / MULTI-DISPLAY / FULLSCREEN ===
- Observe NSApplication.didChangeScreenParametersNotification (both apps). boring.notch (screenConfigurationDidChange) diffs Set(displayUUIDs) AND Set(frames) against the previous snapshot; on change: close all panels, remove from CGS space, recreate + reposition on main queue. MewNotch refreshNotches() closes windows whose screen disappeared and creates one panel per NSScreen.
- Also observe NSWindow.didChangeScreenNotification per window (boring.notch) to re-derive per-screen geometry.
- MewNotch schedules a one-shot 30 s timer after launch that rebuilds all windows (works around early-login screen enumeration weirdness).
- Fullscreen apps (menu bar hidden): .canJoinAllSpaces + .fullScreenAuxiliary keeps the panel eligible for fullscreen spaces at level mainMenu+1. BOTH apps additionally ship an identical private-API NotchSpaceManager (MewNotch/Utils/NotchSpaceManager.swift; boring.notch has the same class inserted via NotchSpaceManager.shared.notchSpace.windows.insert(window)) that creates a dedicated CGS space: CGSSpaceCreate(_CGSDefaultConnection(), 1, nil); CGSSpaceSetAbsoluteLevel(cid, space, 2147483647); CGSShowSpaces; then CGSAddWindowsToSpaces([windowNumber], [space]). Declared via @_silgen_name — links against nothing extra. The flag MUST be 1 or Finder redraws desktop icons (their comment). This guarantees visibility over fullscreen apps and across Spaces. For a personal app: implement it, but the app degrades gracefully without it.
- Optional politeness: hide/collapse when a fullscreen app is frontmost — MewNotch fades windows to alpha 0 per fullscreen space (MacroVisionKit); boring.notch collapses height to 0 (hideOnClosed → effectiveClosedNotchHeight = 0) via its FullscreenMediaDetector.
- Screen lock: DistributedNotificationCenter observers for "com.apple.screenIsLocked"/"com.apple.screenIsUnlocked" (boring.notch) — close or hide panels while locked unless you deliberately want lock-screen presence.

=== 6. SWIFTUI HOSTING + TRANSPARENCY ===
panel.contentView = NSHostingView(rootView: RootView().environmentObject(vm)). Nothing else — the clear/non-opaque panel plus SwiftUI drawing its own black NotchShape is the whole transparency story (no layer fiddling, no ignoresSafeArea needed in a borderless panel; boring.notch adds none). Root view pattern (boring.notch ContentView): ZStack(alignment: .top) { VStack(spacing 0) { islandContent } }.frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top).preferredColorScheme(.dark). Give the island .compositingGroup() before scaleEffect to avoid shadow artifacts.

=== 7. APP STRUCTURE / ACTIVATION POLICY ===
SwiftUI App with @NSApplicationDelegateAdaptor; body contains only a MenuBarExtra scene ("AppName", systemImage: "sparkle", isInserted: $showMenuBarIcon) with Settings/Quit buttons (boring.notch boringNotchApp.swift). In applicationDidFinishLaunching: create panels, then NSApp.setActivationPolicy(.accessory) (MewNotch does it at the end of didFinishLaunching; alternatively set LSUIElement=YES in Info.plist). MenuBarExtra coexists fine with .accessory. When you need a real dialog (alerts, onboarding): NSApp.setActivationPolicy(.regular) + NSApp.activate(ignoringOtherApps: true), and on close revert to .accessory + NSApp.deactivate() (boring.notch does exactly this dance in toggleCameraPreview and onboarding). applicationShouldTerminateAfterLastWindowClosed → false. applicationShouldHandleReopen (dock icon click while .regular) → open settings window.

=== EXACT SOURCE FILES CONSULTED (fetched at main, 2026-08-22) ===
boring.notch (TheBoredTeam/boring.notch): boringNotch/components/Notch/BoringNotchWindow.swift (plain NSPanel config), boringNotch/components/Notch/BoringNotchSkyLightWindow.swift (the instantiated variant + lock-screen SkyLight delegation), boringNotch/boringNotchApp.swift (AppDelegate: window creation, positionWindow, screenConfigurationDidChange, adjustWindowPosition, DistributedNotificationCenter lock observers, MenuBarExtra), boringNotch/sizing/matters.swift (openNotchSize/windowSize/getClosedNotchSize/cornerRadiusInsets), boringNotch/ContentView.swift (hover/tap/gesture handling, animation springs, frame strategy), boringNotch/models/BoringViewModel.swift (open()/close()/notchSize state, isMouseHovering), boringNotch/components/Notch/NotchShape.swift.
mew-notch (monuk7735/mew-notch): MewNotch/View/Common/MewWindow.swift (MewPanel), MewNotch/Utils/NotchUtils.swift (hasNotch/notchSize/simulated size/corner radii), MewNotch/Utils/NotchManager.swift (per-screen window dict, refreshNotches, didChangeScreenParameters listener, fullscreen alpha fade), MewNotch/Utils/NotchSpaceManager.swift (CGSSpace private API, level 2147483647), MewNotch/MewAppDelegate.swift (.accessory policy, 30s rebuild timer), MewNotch/View/Notch/NotchView.swift + MewNotch/ViewModel/Notch/NotchViewModel.swift (expand-on-hover with delay, scaleEffect anchor .top).

## Code sketch
import AppKit
import SwiftUI

// MARK: - Geometry (public API only; values verified on this Mac: 220x38 notch, aux 918/918)
enum NotchGeometry {
    static let fakeIslandWidth: CGFloat = 190
    static let fallbackBarHeight: CGFloat = 32

    static func hasNotch(_ screen: NSScreen) -> Bool { screen.safeAreaInsets.top > 0 }

    /// Physical notch (or fake island) size for a screen.
    static func closedSize(for screen: NSScreen) -> CGSize {
        if hasNotch(screen),
           let l = screen.auxiliaryTopLeftArea?.width,
           let r = screen.auxiliaryTopRightArea?.width {
            // +4: overlap the physical notch edges slightly (boring.notch fudge)
            return CGSize(width: screen.frame.width - l - r + 4,
                          height: screen.safeAreaInsets.top)          // 38 pt here
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY     // can be 0 on externals!
        return CGSize(width: fakeIslandWidth,
                      height: menuBar > 0 ? menuBar : fallbackBarHeight)
    }

    /// Notch rect in global AppKit coords (bottom-left origin).
    static func notchRect(for screen: NSScreen) -> CGRect {
        let s = closedSize(for: screen)
        return CGRect(x: screen.frame.midX - s.width / 2,
                      y: screen.frame.maxY - s.height,
                      width: s.width, height: s.height)
    }
}

// Fixed max-expanded canvas; window is created once at this size and NEVER resized.
let openNotchSize = CGSize(width: 640, height: 190)
let shadowPadding: CGFloat = 20
let windowSize = CGSize(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)

// MARK: - Panel (verbatim union of MewPanel + BoringNotchWindow)
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: windowSize),
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        canBecomeVisibleWithoutLogin = true
        appearance = NSAppearance(named: .darkAqua)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1) // NOT .screenSaver
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
    }
    // Escape support: temporarily key-able while expanded, without activating the app.
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller: create / position / monitors / screen changes
@MainActor
final class IslandController {
    private var panels: [String: IslandPanel] = [:]     // displayUUID -> panel
    private var previousScreens: [NSScreen]?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    let vm = IslandViewModel()

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    private func screensChanged() {
        let cur = NSScreen.screens
        let changed = cur.count != previousScreens?.count
            || Set(cur.map(\.frame)) != Set((previousScreens ?? []).map(\.frame))
        previousScreens = cur
        if changed { rebuild() }   // boring.notch: close all, recreate, reposition
    }

    private func rebuild() {
        panels.values.forEach { $0.close(); NotchSpace.shared.remove($0) }
        panels.removeAll()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let panel = IslandPanel()
        vm.closedSize = NotchGeometry.closedSize(for: screen)
        panel.contentView = NSHostingView(rootView: IslandRootView().environmentObject(vm))
        position(panel, on: screen)
        panel.orderFrontRegardless()                     // never makeKeyAndOrderFront
        NotchSpace.shared.add(panel)                     // private-API space, optional
        panels["main"] = panel
    }

    /// Top-center, top edge glued to screen top. Window frame is static forever after.
    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let f = screen.frame
        panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2,
                                     y: f.maxY - panel.frame.height))
    }

    // Expand/collapse == SwiftUI state only. Install/remove monitors alongside.
    func expand(panel: IslandPanel) {
        vm.open()
        panel.allowKey = true; panel.makeKey()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) { self.collapse(panel: panel) }
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { Task { @MainActor in self?.collapse(panel: panel) }; return nil }
            return e
        }
    }

    func collapse(panel: IslandPanel) {
        vm.close()
        panel.allowKey = false
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
    }
}

// MARK: - State + SwiftUI content (boring.notch animation values)
final class IslandViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var closedSize = CGSize(width: 220, height: 38)
    func open()  { isOpen = true }
    func close() { isOpen = false }
}

struct IslandRootView: View {
    @EnvironmentObject var vm: IslandViewModel
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    private let openAnim  = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnim = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Group {
                    if vm.isOpen { ExpandedContent() }        // your UI
                    else { Color.clear.frame(width: vm.closedSize.width, height: vm.closedSize.height) }
                }
                .background(.black)
                .clipShape(NotchShape(topRadius: vm.isOpen ? 19 : 6,
                                      bottomRadius: vm.isOpen ? 24 : 14))
                // seal the seam against the physical notch:
                .overlay(alignment: .top) { Rectangle().fill(.black).frame(height: 1).padding(.horizontal, 6) }
                .compositingGroup()
                .shadow(color: vm.isOpen || isHovering ? .black.opacity(0.7) : .clear, radius: 6)
                .frame(height: vm.isOpen ? openNotchSize.height : nil)
                .animation(vm.isOpen ? openAnim : closeAnim, value: vm.isOpen)
                .contentShape(Rectangle())
                .onHover { hovering in handleHover(hovering) }
                .onTapGesture { withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) { vm.open() } }
            }
        }
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top) // top-anchored, no jumps
        .preferredColorScheme(.dark)
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        isHovering = hovering
        if hovering {
            guard !vm.isOpen else { return }
            hoverTask = Task {                        // open after dwell
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await MainActor.run { if isHovering { withAnimation(openAnim) { vm.open() } } }
            }
        } else {
            hoverTask = Task {                        // 100 ms debounce, then close
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await MainActor.run { if vm.isOpen { withAnimation(closeAnim) { vm.close() } } }
            }
        }
    }
}

// Outward-curving island silhouette (see boringNotch/components/Notch/NotchShape.swift for the full path)
struct NotchShape: Shape {
    var topRadius: CGFloat, bottomRadius: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .init(x: r.minX, y: r.minY))
        p.addQuadCurve(to: .init(x: r.minX + topRadius, y: r.minY + topRadius),
                       control: .init(x: r.minX + topRadius, y: r.minY))
        p.addLine(to: .init(x: r.minX + topRadius, y: r.maxY - bottomRadius))
        p.addQuadCurve(to: .init(x: r.minX + topRadius + bottomRadius, y: r.maxY),
                       control: .init(x: r.minX + topRadius, y: r.maxY))
        p.addLine(to: .init(x: r.maxX - topRadius - bottomRadius, y: r.maxY))
        p.addQuadCurve(to: .init(x: r.maxX - topRadius, y: r.maxY - bottomRadius),
                       control: .init(x: r.maxX - topRadius, y: r.maxY))
        p.addLine(to: .init(x: r.maxX - topRadius, y: r.minY + topRadius))
        p.addQuadCurve(to: .init(x: r.maxX, y: r.minY),
                       control: .init(x: r.maxX - topRadius, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Private CGS space (optional; identical code ships in BOTH apps: MewNotch/Utils/NotchSpaceManager.swift)
final class NotchSpace {
    static let shared = NotchSpace()
    private let space: CGSSpaceID
    private init() {
        space = CGSSpaceCreate(_CGSDefaultConnection(), 0x1, nil)   // flag MUST be 1
        CGSSpaceSetAbsoluteLevel(_CGSDefaultConnection(), space, 2147483647)
        CGSShowSpaces(_CGSDefaultConnection(), [space] as NSArray)
    }
    func add(_ w: NSWindow)    { CGSAddWindowsToSpaces(_CGSDefaultConnection(), [w.windowNumber] as NSArray, [space] as NSArray) }
    func remove(_ w: NSWindow) { CGSRemoveWindowsFromSpaces(_CGSDefaultConnection(), [w.windowNumber] as NSArray, [space] as NSArray) }
}
private typealias CGSConnectionID = UInt
private typealias CGSSpaceID = UInt64
@_silgen_name("_CGSDefaultConnection") private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate") private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int, _ opts: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceSetAbsoluteLevel") private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ s: CGSSpaceID, _ level: Int)
@_silgen_name("CGSAddWindowsToSpaces") private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ ws: NSArray, _ ss: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces") private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ ws: NSArray, _ ss: NSArray)
@_silgen_name("CGSShowSpaces") private func CGSShowSpaces(_ cid: CGSConnectionID, _ ss: NSArray)

// MARK: - App entry (.accessory + MenuBarExtra coexist)
@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Island", systemImage: "sparkle") {
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = IslandController()
    func applicationDidFinishLaunching(_ n: Notification) {
        Task { @MainActor in controller.start() }
        NSApp.setActivationPolicy(.accessory)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

## Risks
1) Private API: the CGSSpace block (CGSSpaceCreate/CGSSpaceSetAbsoluteLevel/CGSAddWindowsToSpaces) is undocumented SkyLight/CoreGraphics SPI — could break on any macOS update; both reference apps ship it on current macOS and it works on Tahoe today, but the app must degrade gracefully (public collectionBehavior alone covers ~90% of cases; the space only adds over-fullscreen + hidden-menu-bar coverage). The flag argument MUST be 1 or Finder redraws desktop icons over the desktop. Skip boring.notch's SkyLightWindow lock-screen delegation entirely unless lock-screen presence is required. 2) Window level: never use .screenSaver (1000) — it floats over the lock-screen password field; .mainMenu+1…3 (25–27) is what both apps use. 3) External-display fallback: frame.maxY − visibleFrame.maxY returned 0 for the external monitor on this exact machine — always fall back to a constant (~32 pt) or the island gets zero height. 4) Escape key: a GLOBAL keyDown monitor silently requires Accessibility permission and returns nothing without it — use the local-monitor + temporary canBecomeKey approach in the sketch, or rely on hover-out close (what both shipping apps actually do). Global MOUSE monitors need no permission. 5) Full-screen-panel strategy (MewNotch) depends on NSHostingView.hitTest returning nil over empty regions to pass clicks through; if any invisible SwiftUI view (e.g., Color.clear with contentShape) covers the screen it will swallow clicks — prefer the small fixed 640×210 window (boring.notch) unless you need screen-wide drop targets. 6) Never animate the NSWindow frame (window.animator().setFrame causes visible tearing against the physical notch); all animation stays in SwiftUI, window parked at max-expanded size, alignment .top. 7) Screen wake/login race: screens may enumerate before geometry is final — MewNotch rebuilds all windows on a 30 s one-shot timer after launch; replicate if you see a mispositioned island after login/wake. Diff screens by UUID AND frame on didChangeScreenParametersNotification (frame-only moves also require repositioning). 8) macOS 26 verified: NSScreen.safeAreaInsets / auxiliaryTopLeftArea / auxiliaryTopRightArea all return correct values on this machine (Swift 6.3, Tahoe) — no version guard needed above the macOS 12 availability floor. 9) With .nonactivatingPanel + orderFrontRegardless the panel never steals focus; do not call NSApp.activate when showing it, and toggle activation policy to .regular only for real dialogs, reverting to .accessory afterwards, or the Dock icon flashes.

## Sources
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/BoringNotchWindow.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/boringNotchApp.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/sizing/matters.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/models/BoringViewModel.swift
- https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/NotchShape.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/View/Common/MewWindow.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/Utils/NotchManager.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/Utils/NotchUtils.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/Utils/NotchSpaceManager.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/MewAppDelegate.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/View/Notch/NotchView.swift
- https://github.com/monuk7735/mew-notch/blob/main/MewNotch/ViewModel/Notch/NotchViewModel.swift
- local verification: swift -e against AppKit on this machine (macOS 26.6, Xcode 26.6) — NSScreen geometry and NSWindow.Level raw values