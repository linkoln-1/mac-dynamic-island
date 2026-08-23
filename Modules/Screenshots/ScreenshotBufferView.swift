import QuickLook
import SwiftUI

struct ScreenshotBufferView: View {
    @ObservedObject private var buffer: ScreenshotBuffer
    @ObservedObject private var viewModel: ScreenshotBufferViewModel

    private static let gridSpacing: CGFloat = 8

    @MainActor
    init(controller: ScreenshotsModuleController? = nil) {
        let controller = controller ?? .shared
        buffer = controller.buffer
        viewModel = controller.viewModel
    }

    var body: some View {
        ZStack {
            if buffer.items.isEmpty {
                emptyState
            } else {
                content
            }
            if let previewItem = viewModel.previewItem {
                ScreenshotPreviewOverlay(item: previewItem) { viewModel.closePreview() }
            }
        }
        .background(keyboardShortcuts)
        .quickLookPreview($viewModel.quickLookURL)
        .onAppear { ScreenshotsModuleController.shared.activate() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 110), spacing: Self.gridSpacing)],
                    spacing: Self.gridSpacing
                ) {
                    ForEach(buffer.items) { item in
                        ScreenshotCard(item: item, viewModel: viewModel)
                    }
                }
                .padding(10)
            }
            if !viewModel.selectedIDs.isEmpty {
                selectionFooter
            }
        }
    }

    private var selectionFooter: some View {
        HStack(spacing: 10) {
            Text("Selected: \(viewModel.selectedIDs.count)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            footerButton("Copy") { viewModel.copySelected() }
            footerButton("Remove from Buffer") { viewModel.removeSelected() }
            footerButton("Clear Selection") { viewModel.clearSelection() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.1), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.35))
            Text("Take a screenshot (⌘⇧3 / ⌘⇧4)\nor copy an image — it appears here.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("") { viewModel.copySelected() }
                .keyboardShortcut("c", modifiers: .command)
            Button("") { viewModel.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

private struct ScreenshotPreviewOverlay: View {
    let item: ScreenshotItem
    let onClose: () -> Void
    @State private var fullImage: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            Group {
                if let image = fullImage ?? item.thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .padding(14)
            closeButton
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .task(id: item.id) {
            guard let url = item.fileURL else { return }

            let image = await Task.detached(priority: .userInitiated) {
                ScreenshotThumbnailService.previewImage(url: url)
            }.value
            fullImage = image
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            Spacer()
        }
    }
}
