import SwiftUI

@main
struct PersonalIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PersonalIsland", systemImage: "sparkles") {
            MenuBarContentView()
        }

        Settings {
            SettingsPlaceholderView()
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        Button(lang.string("menu.openIsland")) {
            AppState.shared.openIsland()
        }
        Menu(lang.string("menu.language")) {
            Picker("", selection: Binding(
                get: { lang.mode },
                set: { lang.setMode($0) }
            )) {
                Text(lang.string("menu.language.system")).tag(AppLanguageMode.system)
                Text("English").tag(AppLanguageMode.english)
                Text("Русский").tag(AppLanguageMode.russian)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        SettingsLink {
            Text(lang.string("menu.settings"))
        }
        Divider()
        Button(lang.string("menu.quit")) {
            NSApp.terminate(nil)
        }
    }
}

struct SettingsPlaceholderView: View {
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gearshape")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(lang.string("settings.title"))
                .font(.headline)
            Text(lang.string("settings.empty"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 180)
    }
}
