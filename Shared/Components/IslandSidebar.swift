import SwiftUI

struct IslandSidebar: View {
    @ObservedObject var state: IslandState
    @ObservedObject private var attention = AttentionStore.shared
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {

        VStack(spacing: 0) {
            ForEach(state.registry.modules.indices, id: \.self) { index in
                let module = state.registry.modules[index]
                ModuleButton(
                    systemImage: module.systemImage,
                    title: lang.string("module.\(module.id).title"),
                    isSelected: module.id == state.selectedModuleID,
                    badgeLabel: module.id == "attention"
                        ? AttentionBadgeFormatter.label(attention.unreadCount) : nil,
                    badgeIsUrgent: attention.highPriorityUnreadCount > 0
                ) {
                    state.select(moduleID: module.id)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: IslandMetrics.sidebarWidth)
        #if DEBUG
        .overlay(DebugFrameReporter(label: "sidebar", color: .blue))
        #endif
    }
}
