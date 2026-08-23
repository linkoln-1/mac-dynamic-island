import SwiftUI

struct IslandSidebar: View {
    @ObservedObject var state: IslandState

    var body: some View {

        VStack(spacing: 0) {
            ForEach(state.registry.modules.indices, id: \.self) { index in
                let module = state.registry.modules[index]
                ModuleButton(
                    systemImage: module.systemImage,
                    title: module.title,
                    isSelected: module.id == state.selectedModuleID
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
