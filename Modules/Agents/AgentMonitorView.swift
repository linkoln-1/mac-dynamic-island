import SwiftUI

struct AgentMonitorView: View {
    @ObservedObject private var controller = AgentsModuleController.shared
    @ObservedObject private var store = AgentsModuleController.shared.store
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        Group {
            if !controller.isEnabled {
                setupState
            } else if store.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .onAppear { controller.activateIfEnabled() }
    }

    private var setupState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text(lang.string("agent.setup.description"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
            Button(lang.string("agent.setup.enable")) { controller.enable() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            if let error = controller.lastEnableError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text(lang.string("agent.empty"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
            healthRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredSessions: [AgentSession] {
        store.orderedSessions(provider: controller.providerFilter)
    }

    private var emptyFilterText: String {
        if controller.providerFilter == .codex, controller.codexLocalHealth == .unavailable {
            return lang.string("codex.health.unavailable")
        }
        return controller.providerFilter.map {
            lang.format("agent.empty.provider", $0.displayName)
        } ?? lang.string("agent.empty.any")
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lang.string("module.agents.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                providerTabs
                Spacer()
                Text(lang.plural("agent.sessions.count", filteredSessions.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                if store.hasInactiveSessions(provider: controller.providerFilter) {
                    Button(lang.string("agent.clear")) { store.clearInactive(provider: controller.providerFilter) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                        .help(lang.string("agent.clear.help"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            if filteredSessions.isEmpty {
                Text(emptyFilterText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(filteredSessions) { session in
                            AgentSessionCard(
                                session: session,
                                isHighlighted: controller.highlightedSessionID == session.id
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private var providerTabs: some View {
        HStack(spacing: 3) {
            providerTab(nil, title: lang.string("agent.tab.all"))
            ForEach(AgentProviderKind.allCases, id: \.self) { provider in
                providerTab(provider, title: provider.displayName)
            }
        }
        .padding(.leading, 6)
    }

    private func providerTab(_ provider: AgentProviderKind?, title: String) -> some View {
        let isSelected = controller.providerFilter == provider
        let count = store.sessionCount(provider: provider)
        return Button {
            controller.providerFilter = provider
        } label: {
            HStack(spacing: 3) {
                if let provider {
                    providerTabIcon(provider)
                        .opacity(isSelected ? 1.0 : 0.55)
                } else {
                    Text(title)
                        .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                }
                if provider != nil, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                }
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(isSelected ? 0.16 : 0.0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(provider?.displayName ?? lang.string("agent.tab.allProviders"))
    }

    @ViewBuilder
    private func providerTabIcon(_ provider: AgentProviderKind) -> some View {
        if let icon = AgentProviderIconResolver.shared.icon(for: provider) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 10))
                .frame(width: 14, height: 14)
        }
    }

    private var healthRow: some View {
        HStack(spacing: 10) {
            healthBadge("Claude", ok: controller.health.claudeInstalled)
            healthBadge("Codex", ok: controller.health.codexInstalled)
            if !controller.health.claudeInstalled || !controller.health.codexInstalled {
                Button(lang.string("agent.repair")) { controller.repair() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
        }
    }

    private func healthBadge(_ name: String, ok: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(ok ? Color.green.opacity(0.8) : Color.yellow.opacity(0.9))
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

struct AgentSessionCard: View {
    let session: AgentSession
    var isHighlighted: Bool = false
    @State private var isHovering = false
    @ObservedObject private var lang = AppLanguageManager.shared

    private static let projectActions = AgentProjectActions()

    var body: some View {
        HStack(spacing: 8) {
            providerIcon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.provider.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(session.project) · \(session.alias)")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    stateBadge
                    if !session.activity.isEmpty, session.state == .working || session.state == .needsPermission {
                        Text(ActivityPresentation.localize(session.activity, lang: lang))
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    if session.subagentCount > 0 {
                        Text(lang.plural("agent.subagents.count", session.subagentCount))
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer(minLength: 4)
            durationLabel
            if isHovering, Self.projectActions.isAvailable(path: session.projectPath) {
                AgentActionMenuButton(projectPath: session.projectPath)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.20 : backgroundOpacity))
        )
        .onHover { isHovering = $0 }
        .help("\(session.provider.displayName) · \(session.project)")
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let icon = AgentProviderIconResolver.shared.icon(for: session.provider) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 22, height: 22)
        }
    }

    private var stateBadge: some View {
        HStack(spacing: 3) {
            stateGlyph
            Text(lang.string(session.state.localizationKey))
                .font(.system(size: 9, weight: session.state == .needsPermission ? .bold : .medium))
        }
        .foregroundStyle(stateColor)
    }

    @ViewBuilder
    private var stateGlyph: some View {
        switch session.state {
        case .working:
            WorkingPulseDot(color: stateColor)
        case .needsPermission:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 8))
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.system(size: 8))
        case .idle, .stale:
            Circle().fill(stateColor).frame(width: 5, height: 5)
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .working: return .green
        case .needsPermission: return .yellow
        case .finished: return Color.green.opacity(0.75)
        case .failed: return .red
        case .idle: return .white.opacity(0.5)
        case .stale: return .white.opacity(0.35)
        }
    }

    private var backgroundOpacity: Double {
        if session.state == .needsPermission { return isHovering ? 0.16 : 0.12 }
        return isHovering ? 0.10 : 0.06
    }

    @ViewBuilder
    private var durationLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let duration = session.cycleDuration(at: context.date) {
                Text(AgentActivityFormatter.duration(duration))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

struct WorkingPulseDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}
