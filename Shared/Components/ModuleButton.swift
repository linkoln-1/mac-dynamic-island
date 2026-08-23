import SwiftUI

struct ModuleButton: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
            }

            .frame(
                width: IslandMetrics.sidebarButtonHitTarget,
                height: IslandMetrics.sidebarButtonHitTarget
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        #if DEBUG
        .overlay(DebugFrameReporter(label: "button:\(title)", color: isSelected ? .green : .yellow))
        #endif
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.white.opacity(0.16)
        }
        return isHovering ? Color.white.opacity(0.08) : Color.clear
    }
}
