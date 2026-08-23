import Foundation

struct AttentionPersistence {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PersonalIsland", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent("attention.json") }

    func load() -> [AttentionItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([AttentionItem].self, from: data)
        } catch {
            Log.attention.error("attention store corrupted: \(error.localizedDescription, privacy: .public)")
            let backup = directory.appendingPathComponent(
                "attention.corrupted-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
    }

    func save(_ items: [AttentionItem]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.attention.error("attention save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
