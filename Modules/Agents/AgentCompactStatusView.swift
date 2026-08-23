import SwiftUI

struct AgentCompactStatusView: View {
    @ObservedObject private var store = AgentsModuleController.shared.store
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
                if summary.attention > 0 {
                    attentionBadge(summary.attention)
                }
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

    private func attentionBadge(_ count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.yellow)
    }
}

struct AgentMicroClusterView: View {
    @ObservedObject private var store = AgentsModuleController.shared.store

    var body: some View {
        let summary = store.compactSummary
        HStack(spacing: 4) {
            if summary.attention > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                Text("\(summary.attention)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
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
    @Environment(\.notchGapWidth) private var notchGapWidth

    static let microZoneWidth: CGFloat = 56

    var body: some View {
        if !media.state.isEmpty {
            HStack(spacing: 0) {
                if showMicroCluster {
                    Color.clear.frame(width: Self.microZoneWidth)
                }
                NowPlayingCompactView()
                if showMicroCluster {
                    AgentMicroClusterView()
                        .frame(width: Self.microZoneWidth, alignment: .trailing)
                        .padding(.trailing, 2)
                }
            }
        } else {
            AgentCompactStatusView()
        }
    }

    private var showMicroCluster: Bool {
        !agents.compactSummary.isEmpty
    }
}
