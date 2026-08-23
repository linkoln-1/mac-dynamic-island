import Foundation

private let maxStdinBytes = 1_000_000
private let socketTimeoutMs: Int32 = 400

func run() {

    var provider: AgentProviderKind?
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        if argument == "--provider", let value = arguments.next() {
            provider = AgentProviderKind(rawValue: value)
        }
    }
    guard let provider else { exit(0) }

    let input = FileHandle.standardInput.readData(ofLength: maxStdinBytes)
    guard !input.isEmpty,
          let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let event = AgentHookPayloadMapper.wireEvent(provider: provider, payload: payload),
          let encoded = try? JSONEncoder().encode(event)
    else { exit(0) }

    if !sendOverSocket(encoded) {
        spool(encoded, dedupKey: event.dedupKey)
    }
    exit(0)
}

private func sendOverSocket(_ data: Data) -> Bool {
    let path = AgentBridgePaths.socketURL.path
    guard FileManager.default.fileExists(atPath: path) else { return false }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var timeout = timeval(tv_sec: 0, tv_usec: socketTimeoutMs * 1000)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        pathBytes.withUnsafeBytes { buffer.copyMemory(from: $0) }
    }

    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connectResult == 0 else { return false }

    return data.withUnsafeBytes { buffer in
        var sent = 0
        while sent < buffer.count {
            let written = write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
            guard written > 0 else { return false }
            sent += written
        }
        return true
    }
}

private func spool(_ data: Data, dedupKey: String) {
    let directory = AgentBridgePaths.spoolDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
    let url = directory.appendingPathComponent("\(stamp)-\(dedupKey).json")
    try? data.write(to: url, options: .atomic)
}

run()
