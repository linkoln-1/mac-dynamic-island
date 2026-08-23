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
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var lang = AppLanguageManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section(lang.string("settings.section.island")) {
                Toggle(lang.string("settings.island.hoverOpen"), isOn: $settings.hoverOpenEnabled)
                sliderRow(
                    lang.string("settings.island.expandDelay"),
                    value: $settings.hoverExpandDelay, range: 0.1...0.8, step: 0.05
                )
                sliderRow(
                    lang.string("settings.island.collapseGrace"),
                    value: $settings.hoverCollapseGrace, range: 0.3...2.0, step: 0.05
                )
                .disabled(!settings.hoverOpenEnabled)
            }
            Section(lang.string("settings.section.notifications")) {
                Toggle(lang.string("agent.state.finished"), isOn: $settings.notifyFinished)
                Toggle(lang.string("agent.state.needsPermission"), isOn: $settings.notifyPermission)
                Toggle(lang.string("agent.state.failed"), isOn: $settings.notifyFailed)
                Toggle("Claude Code", isOn: $settings.notifyClaude)
                Toggle("Codex", isOn: $settings.notifyCodex)
                LabeledContent(lang.string("settings.agents.autoClear")) {
                    HStack(spacing: 6) {
                        Slider(value: $settings.agentAutoClearSeconds, in: 15...300, step: 15)
                            .frame(width: 140)
                        Text("\(Int(settings.agentAutoClearSeconds)) \(lang.string("settings.seconds.suffix"))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            Section(lang.string("settings.section.general")) {
                Toggle(lang.string("settings.launchAtLogin"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchAtLogin = newValue
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                ))
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Picker(lang.string("menu.language"), selection: Binding(
                    get: { lang.mode },
                    set: { lang.setMode($0) }
                )) {
                    Text(lang.string("menu.language.system")).tag(AppLanguageMode.system)
                    Text("English").tag(AppLanguageMode.english)
                    Text("Русский").tag(AppLanguageMode.russian)
                }
            }
            Section(lang.string("module.screenshots.title")) {
                LabeledContent(lang.string("settings.screenshots.limit")) {
                    HStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { Double(settings.screenshotBufferLimit) },
                                set: { settings.screenshotBufferLimit = Int($0) }
                            ),
                            in: 10...100, step: 5
                        )
                        .frame(width: 140)
                        Text(lang.plural("settings.items.count", settings.screenshotBufferLimit))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                    }
                }
            }
            Section(lang.string("module.attention.title")) {
                LabeledContent(lang.string("settings.attention.retention")) {
                    HStack(spacing: 6) {
                        Slider(value: $settings.attentionRetentionDays, in: 1...30, step: 1)
                            .frame(width: 140)
                        Text(lang.plural("settings.days.count", Int(settings.attentionRetentionDays)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.locale, lang.locale)
    }

    private func sliderRow(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Slider(value: value, in: range, step: step)
                    .frame(width: 140)
                Text(String(format: "%.2f %@", value.wrappedValue, lang.string("settings.seconds.suffix")))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}
