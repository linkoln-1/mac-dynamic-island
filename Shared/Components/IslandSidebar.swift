import SwiftUI

struct IslandSidebar: View {
    @ObservedObject var state: IslandState
    @ObservedObject private var attention = AttentionStore.shared
    @ObservedObject private var lang = AppLanguageManager.shared
    @ObservedObject private var settings = AppSettings.shared

    private var orderedModules: [any IslandModule] {
        let order = settings.orderedModuleIDs(all: state.registry.modules.map(\.id))
        return order.compactMap { id in state.registry.module(withID: id) }
    }

    var body: some View {

        VStack(spacing: 0) {
            let modules = orderedModules
            ForEach(modules.indices, id: \.self) { index in
                let module = modules[index]
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
