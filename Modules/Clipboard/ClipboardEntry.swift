import CryptoKit
import Foundation

enum ClipboardEntryKind: String, CaseIterable, Equatable {
    case text
    case url
    case code
    case file

    var localizationKey: String { "clipboard.kind.\(rawValue)" }

    var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .file: return "doc"
        }
    }
}

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    var kind: ClipboardEntryKind
    var content: String
    var preview: String
    var createdAt: Date
    var isPinned: Bool
    var contentHash: String

    init(
        id: UUID = UUID(), kind: ClipboardEntryKind, content: String,
        preview: String, createdAt: Date, isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.preview = preview
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.contentHash = ClipboardClassifier.hash(kind.rawValue + "|" + content)
    }
}

enum ClipboardClassifier {
    static let maxContentLength = 100_000
    static let previewLength = 200

    static func entry(from string: String, at moment: Date) -> ClipboardEntry? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, string.count <= maxContentLength else { return nil }
        let kind = classify(trimmed)
        return ClipboardEntry(
            kind: kind, content: string,
            preview: preview(of: trimmed), createdAt: moment
        )
    }

    static func fileEntry(path: String, at moment: Date) -> ClipboardEntry {
        ClipboardEntry(
            kind: .file, content: path,
            preview: (path as NSString).lastPathComponent, createdAt: moment
        )
    }

    static func classify(_ trimmed: String) -> ClipboardEntryKind {
        if !trimmed.contains("\n"),
           let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "ftp"].contains(scheme),
           url.host != nil {
            return .url
        }
        let lines = trimmed.components(separatedBy: "\n")
        if lines.count >= 2 {
            let markers = ["{", "};", "func ", "def ", "import ", "=> ", "</", "#include", "let ", "var ", "class ", "$ ", "();"]
            if markers.contains(where: { trimmed.contains($0) }) {
                return .code
            }
        }
        return .text
    }

    static func preview(of trimmed: String) -> String {
        let flattened = trimmed
        if flattened.count <= previewLength { return flattened }
        return String(flattened.prefix(previewLength)) + "…"
    }

    static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
