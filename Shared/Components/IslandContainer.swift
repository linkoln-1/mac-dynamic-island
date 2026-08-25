import SwiftUI

struct IslandContainer: View {
    @ObservedObject var state: IslandState

    var body: some View {
        HStack(spacing: 0) {
            IslandSidebar(state: state)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)

            ZStack {
                moduleContent
                    .id(state.selectedModuleID)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.18), value: state.selectedModuleID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, state.closedSize.height)

        .padding(.horizontal, IslandMetrics.expandedContentHorizontalInset)
        .padding(.bottom, IslandMetrics.expandedContentBottomInset)
        .overlay(alignment: .topLeading) {
            TimerExpandedChip()
                .padding(.leading, IslandMetrics.expandedContentHorizontalInset + 4)
                .padding(.top, max(0, (state.closedSize.height - 24) / 2))
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        if let module = state.selectedModule {
            module.makeContent()
        } else {
            Text("No module selected")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
