import AppKit
import QuickLookThumbnailing

enum ScreenshotThumbnailService {
    private static var thumbnailSize: CGSize {
        CGSize(
            width: ScreenshotBufferSettings.thumbnailMaxDimension,
            height: ScreenshotBufferSettings.thumbnailMaxDimension * 0.7
        )
    }

    static func fileThumbnail(url: URL, completion: @MainActor @escaping (NSImage?) -> Void) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            if let error {
                Log.screenshots.debug("QL thumbnail failed: \(error.localizedDescription)")
            }
            let image = representation?.nsImage
            Task { @MainActor in completion(image) }
        }
    }

    static func downscale(
        data: Data,
        maxPixel: Int = Int(ScreenshotBufferSettings.thumbnailMaxDimension * 2)
    ) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func previewImage(url: URL, maxPixel: Int = 1600) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return downscale(data: data, maxPixel: maxPixel)
    }
}
