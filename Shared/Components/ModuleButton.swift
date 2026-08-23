import SwiftUI

struct ModuleButton: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    var badgeLabel: String?
    var badgeIsUrgent: Bool = false
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
                if let badgeLabel {
                    Text(badgeLabel)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12)
                        .frame(height: 12)
                        .background(
                            badgeIsUrgent ? Color.red.opacity(0.9) : Color.white.opacity(0.25),
                            in: Capsule()
                        )
                        .offset(x: 12, y: -11)
                }
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
