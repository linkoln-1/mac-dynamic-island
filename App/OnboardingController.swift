import AppKit
import SwiftUI

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    static let defaultsKey = "onboardingShown"

    private var window: NSWindow?

    @discardableResult
    func showIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: Self.defaultsKey) else { return false }
        defaults.set(true, forKey: Self.defaultsKey)
        show()
        return true
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.window?.close()
        })
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text(lang.string("onboarding.title"))
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                row("cursorarrow.motionlines", "onboarding.hover")
                row("square.grid.2x2", "onboarding.modules")
                row("cpu", "onboarding.agents")
                row("sparkles", "onboarding.menubar")
            }
            .frame(maxWidth: 380)
            Button {
                onDone()
            } label: {
                Text(lang.string("onboarding.start"))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 470)
    }

    private func row(_ symbol: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)
            Text(lang.string(key))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
