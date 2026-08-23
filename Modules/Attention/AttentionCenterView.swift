import SwiftUI

struct AttentionCenterView: View {
    @ObservedObject private var store = AttentionStore.shared
    @ObservedObject private var agents = AgentsModuleController.shared
    @ObservedObject private var lang = AppLanguageManager.shared
    @State private var unreadOnly = false

    var body: some View {
        let rows = store.sortedItems(unreadOnly: unreadOnly)
        VStack(spacing: 0) {
            header
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rows) { item in
                            AttentionRowView(item: item)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
        }
        .environment(\.locale, lang.locale)
    }

    private var header: some View {
        HStack {
            Text(lang.string("module.attention.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            filterTab(lang.string("attention.filter.unread"), active: unreadOnly) { unreadOnly = true }
            filterTab(lang.string("attention.filter.all"), active: !unreadOnly) { unreadOnly = false }
            Spacer()
            if store.unreadCount > 0 {
                Text(lang.plural("attention.unread.count", store.unreadCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            if store.sortedItems().contains(where: { !$0.isUnread }) {
                Button(lang.string("attention.clearRead")) { store.clearRead() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func filterTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: active ? .semibold : .regular))
                .foregroundStyle(.white.opacity(active ? 0.95 : 0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(active ? 0.16 : 0.0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text(lang.string(agents.isEnabled ? "attention.empty.allClear" : "attention.empty.noSources"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AttentionRowView: View {
    let item: AttentionItem
    @State private var isHovering = false
    @ObservedObject private var agents = AgentsModuleController.shared
    @ObservedObject private var lang = AppLanguageManager.shared

    private let actions = AgentProjectActions()

    var body: some View {
        HStack(spacing: 8) {
            AgentProviderIconView(provider: item.provider, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(item.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    if item.isUnread {
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 4, height: 4)
                    }
                }
                HStack(spacing: 5) {
                    kindBadge
                    Text(AttentionPresentation.detail(item, lang: lang))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isHovering {
                rowButtons
            } else {
                Text(AttentionPresentation.relativeTime(from: item.updatedAt, now: Date(), lang: lang))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(backgroundOpacity))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            AttentionStore.shared.markRead(item.id)
            agents.navigateToSession(item.relatedAgentSessionID)
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.title), \(item.subtitle), \(AttentionPresentation.kindLabel(item.kind, lang: lang)), \(AttentionPresentation.detail(item, lang: lang))"
        )
    }

    private var rowButtons: some View {
        HStack(spacing: 4) {
            if item.isUnread {
                rowButton("circle.badge.checkmark", help: lang.string("attention.action.markRead")) {
                    AttentionStore.shared.markRead(item.id)
                }
            }
            if actions.isAvailable(path: item.projectPath) {
                AgentActionMenuButton(projectPath: item.projectPath)
                    .help(lang.string("agent.actions.help"))
            }
            rowButton("xmark", help: lang.string("attention.action.dismiss")) {
                AttentionStore.shared.dismiss(item.id)
            }
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var kindBadge: some View {
        HStack(spacing: 3) {
            kindGlyph
            Text(AttentionPresentation.kindLabel(item.kind, lang: lang))
                .font(.system(size: 9, weight: item.isActionableHigh ? .bold : .medium))
        }
        .foregroundStyle(kindColor)
    }

    @ViewBuilder
    private var kindGlyph: some View {
        switch item.kind {
        case .needsPermission:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
        case .finished:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 8))
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.system(size: 8))
        }
    }

    private var kindColor: Color {
        switch item.kind {
        case .needsPermission:
            return item.isResolved ? .white.opacity(0.5) : .yellow
        case .finished:
            return Color.green.opacity(0.75)
        case .failed:
            return .red
        }
    }

    private var backgroundOpacity: Double {
        if item.isActionableHigh { return isHovering ? 0.16 : 0.12 }
        return isHovering ? 0.10 : 0.06
    }
}
