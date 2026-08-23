import Foundation

final class AgentEventReceiver {

    var onEvent: (@MainActor (AgentWireEvent) -> Void)?

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.lincode.PersonalIsland.agentBridge", qos: .utility)
    private static let maxMessageBytes = 64 * 1024

    func start() {
        queue.async { [weak self] in
            self?.replaySpool()
            self?.openSocket()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.acceptSource?.cancel()
            self.acceptSource = nil
            if self.listenFD >= 0 { close(self.listenFD) }
            self.listenFD = -1
            unlink(AgentBridgePaths.socketURL.path)
        }
    }

    private func openSocket() {
        let directory = AgentBridgePaths.root
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = AgentBridgePaths.socketURL.path
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.agentBridge.error("agent socket creation failed")
            return
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            pathBytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, listen(fd, 16) == 0 else {
            Log.agentBridge.error("agent socket bind/listen failed errno=\(errno)")
            close(fd)
            return
        }
        chmod(path, 0o600)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        acceptSource = source
        source.resume()
        Log.agentBridge.info("agent bridge listening")
    }

    private func acceptOne() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        defer { close(clientFD) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while data.count < Self.maxMessageBytes {
            let count = read(clientFD, &chunk, chunk.count)
            if count <= 0 { break }
            data.append(contentsOf: chunk[0..<count])
        }
        deliver(data)
    }

    private func deliver(_ data: Data) {
        guard !data.isEmpty, data.count <= Self.maxMessageBytes,
              let event = try? JSONDecoder().decode(AgentWireEvent.self, from: data),
              event.v == 1
        else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onEvent?(event) }
        }
    }

    private func replaySpool() {
        let replayed = Self.consumeSpool(directory: AgentBridgePaths.spoolDirectory) { [weak self] data in
            self?.deliver(data)
        }
        if replayed > 0 {
            Log.agentBridge.info("replayed \(replayed) spooled agent events")
        }
    }

    @discardableResult
    static func consumeSpool(
        directory: URL,
        maxEvents: Int = AgentSpoolPolicy.maxEvents,
        maxAge: TimeInterval = AgentSpoolPolicy.maxAge,
        now: Date = Date(),
        deliver: (Data) -> Void
    ) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return 0 }

        let sorted = entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var replayed = 0
        for url in sorted {
            defer { try? FileManager.default.removeItem(at: url) }
            guard replayed < maxEvents else { continue }
            let age = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                .map { now.timeIntervalSince($0) } ?? 0
            guard age < maxAge else { continue }
            guard let data = try? Data(contentsOf: url), data.count <= maxMessageBytes else { continue }
            deliver(data)
            replayed += 1
        }
        return replayed
    }
}
