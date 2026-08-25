import SwiftUI

struct AgentCompactStatusView: View {
    @ObservedObject private var store = AgentsModuleController.shared.store
    @ObservedObject private var attention = AttentionStore.shared
    @Environment(\.notchGapWidth) private var notchGapWidth

    var body: some View {
        let summary = store.compactSummary
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                providerCount(.claude, count: summary.claudeActive)
                providerCount(.codex, count: summary.codexActive)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: notchGapWidth)
            HStack(spacing: 8) {
                if summary.working > 0 {
                    HStack(spacing: 3) {
                        WorkingPulseDot(color: .green)
                        Text("\(summary.working)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                TimerCompactChip()
                CompactAttentionBadge(count: attention.highPriorityUnreadCount, iconSize: 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func providerCount(_ provider: AgentProviderKind, count: Int) -> some View {
        if count > 0 {
            HStack(spacing: 3) {
                AgentProviderIconView(provider: provider, size: 16)
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

}

struct CompactAttentionBadge: View {
    let count: Int
    let iconSize: CGFloat
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        if let label = AttentionBadgeFormatter.label(count) {
            Button {
                NotificationCenter.default.post(
                    name: .islandNavigateToModule, object: nil,
                    userInfo: ["moduleID": "attention"]
                )
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: iconSize))
                    Text(label)
                        .font(.system(size: iconSize + 1, weight: .bold))
                }
                .foregroundStyle(.yellow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.string("attention.badge.help"))
            .accessibilityLabel(lang.string("attention.badge.help"))
        }
    }
}

struct AgentMicroClusterView: View {
    @ObservedObject private var store = AgentsModuleController.shared.store
    @ObservedObject private var attention = AttentionStore.shared

    var body: some View {
        let summary = store.compactSummary
        HStack(spacing: 4) {
            if attention.highPriorityUnreadCount > 0 {
                CompactAttentionBadge(count: attention.highPriorityUnreadCount, iconSize: 8)
            } else {
                if summary.claudeActive > 0 {
                    AgentProviderIconView(provider: .claude, size: 12)
                    Text("\(summary.claudeActive)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if summary.codexActive > 0 {
                    AgentProviderIconView(provider: .codex, size: 12)
                    Text("\(summary.codexActive)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

struct AgentProviderIconView: View {
    let provider: AgentProviderKind
    let size: CGFloat

    var body: some View {
        if let icon = AgentProviderIconResolver.shared.icon(for: provider) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .help(provider.displayName)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.7))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: size, height: size)
        }
    }
}

struct CompactSurfaceView: View {
    @ObservedObject private var media = NowPlayingViewModel.shared
    @ObservedObject private var agents = AgentsModuleController.shared.store
    @ObservedObject private var attention = AttentionStore.shared
    @ObservedObject private var systemTimer = SystemTimerController.shared
    @Environment(\.notchGapWidth) private var notchGapWidth

    static let microZoneWidth: CGFloat = 56
    static let timerZoneWidth: CGFloat = 46

    var body: some View {
        let plan = CompactSurfacePlan.plan(
            hasMedia: !media.state.isEmpty,
            hasAgentSummary: !agents.compactSummary.isEmpty,
            highPriorityCount: attention.highPriorityUnreadCount,
            hasTimer: systemTimer.snapshot != nil
        )
        if plan.showsMedia {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    NowPlayingCompactInfo()
                    NowPlayingCompactControls()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notchGapWidth)
                HStack(spacing: 8) {
                    TimerCompactChip()
                    AgentMicroClusterView()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            }
        } else {
            AgentCompactStatusView()
        }
    }
}
