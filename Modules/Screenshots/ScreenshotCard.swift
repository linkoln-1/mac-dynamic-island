import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotCard: View {
    let item: ScreenshotItem
    @ObservedObject var viewModel: ScreenshotBufferViewModel
    @State private var isHovering = false

    private static let cardWidth: CGFloat = 96
    private static let thumbnailHeight: CGFloat = 60
    private static let cornerRadius: CGFloat = 8

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var isSelected: Bool { viewModel.isSelected(item) }

    var body: some View {
        VStack(spacing: 3) {
            thumbnail
            Text(Self.timeFormatter.string(from: item.creationDate))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(width: Self.cardWidth)
        .contentShape(Rectangle())

        .overlay {
            ScreenshotCardInteraction(
                tooltip: item.fileURL?.lastPathComponent ?? "Screenshot",
                onClick: { commandKey in viewModel.handleClick(item, commandKey: commandKey) },
                onDoubleClick: { viewModel.handleDoubleClick(item) },
                onHover: { isHovering = $0 },
                dragPayloadProvider: {
                    viewModel.dragPayload(for: item).compactMap { payloadItem in
                        guard let url = payloadItem.fileURL else { return nil }
                        return (url: url, preview: payloadItem.thumbnail)
                    }
                },
                menuEntries: { menuEntries }
            )
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHovering && !isSelected ? 0.14 : 0.08))
            if let image = item.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.cardWidth, height: Self.thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: Self.cardWidth, height: Self.thumbnailHeight)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(isHovering ? 0.3 : 0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(3)
            }
        }
    }

    private var menuEntries: [CardMenuEntry?] {
        [
            CardMenuEntry(title: AppLanguageManager.shared.string("screenshots.copy")) { viewModel.copy(item) },
            item.fileExists
                ? CardMenuEntry(title: AppLanguageManager.shared.string("action.revealInFinder")) { viewModel.revealInFinder(item) }
                : nil,
            CardMenuEntry(title: AppLanguageManager.shared.string("screenshots.open")) { viewModel.open(item) },
            CardMenuEntry(title: AppLanguageManager.shared.string("screenshots.quickLook")) { viewModel.showQuickLook(item) },
            CardMenuEntry(title: "-") {},
            CardMenuEntry(title: AppLanguageManager.shared.string("screenshots.remove")) { viewModel.remove(item) },
        ]
    }
}
