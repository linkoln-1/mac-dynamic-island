import SwiftUI

@main
struct PersonalIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PersonalIsland", systemImage: "sparkles") {
            Button("Open Island") {
                AppState.shared.openIsland()
            }
            SettingsLink {
                Text("Settings…")
            }
            Divider()
            Button("Quit PersonalIsland") {
                NSApp.terminate(nil)
            }
        }

        Settings {
            SettingsPlaceholderView()
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gearshape")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("PersonalIsland Settings")
                .font(.headline)
            Text("Nothing to configure yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 180)
    }
}
