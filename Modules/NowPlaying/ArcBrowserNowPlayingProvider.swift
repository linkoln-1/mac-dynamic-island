import AppKit
import Foundation

enum ArcProbeOutcome: Equatable {
    case snapshot(BrowserMediaSnapshot)
    case noMedia
    case arcNotRunning
    case permissionDenied
    case failed
}

enum ArcPermissionClassifier {
    enum Status: Equatable {
        case authorized
        case denied
        case appNotRunning
        case failure
    }

    static func classify(exitCode: Int32, stderr: String) -> Status {
        guard exitCode != 0 else { return .authorized }
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") {
            return .denied
        }
        if stderr.contains("-600") || stderr.localizedCaseInsensitiveContains("isn't running") {
            return .appNotRunning
        }
        return .failure
    }
}

actor ArcBrowserNowPlayingProvider {

    private static let mediaHosts = ["youtube.com"]
    private static let probeTimeout: TimeInterval = 4
    private static let killTimeout: TimeInterval = 6

    private static let deniedRetryInterval: TimeInterval = 300

    private(set) var currentTabID: String?
    private var permissionDeniedAt: Date?

    func probe() async -> ArcProbeOutcome {
        guard Self.isArcRunning() else {
            currentTabID = nil
            return .arcNotRunning
        }
        if let deniedAt = permissionDeniedAt {
            guard Date().timeIntervalSince(deniedAt) > Self.deniedRetryInterval else {
                return .permissionDenied
            }
            permissionDeniedAt = nil
        }

        let script = Self.probeScript(mediaHosts: Self.mediaHosts)
        let result = await Self.runOSAScript(script)
        switch ArcPermissionClassifier.classify(exitCode: result.exitCode, stderr: result.stderr) {
        case .denied:
            permissionDeniedAt = Date()
            Log.nowPlaying.error("Arc automation permission denied — fallback disabled for a while")
            return .permissionDenied
        case .appNotRunning:
            currentTabID = nil
            return .arcNotRunning
        case .failure:
            Log.nowPlaying.info("Arc probe failed (timeout or script error)")
            return .failed
        case .authorized:
            break
        }

        let snapshots = Self.parseProbeOutput(result.stdout)
        guard let best = BrowserCandidateRanking.best(of: snapshots, currentTabID: currentTabID) else {
            currentTabID = nil
            return .noMedia
        }
        currentTabID = best.tabID
        return .snapshot(best)
    }

    func play() async { await runMediaCommand("m.play()") }
    func pause() async { await runMediaCommand("m.pause()") }
    func togglePlayPause() async { await runMediaCommand("m.paused?m.play():m.pause()") }

    func seek(to seconds: TimeInterval) async {
        let clamped = max(0, seconds)
        await runMediaCommand("m.currentTime=\(String(format: "%.2f", clamped))")
    }

    private func runMediaCommand(_ statement: String) async {
        guard let tabID = currentTabID, Self.isArcRunning() else { return }
        let js = "(()=>{const m=[...document.querySelectorAll('video,audio')]"
            + ".filter(e=>e.readyState>0&&!e.ended).sort((a,b)=>(a.paused?1:0)-(b.paused?1:0))[0];"
            + "if(m){\(statement);}return 'ok'})()"
        let script = Self.commandScript(tabID: tabID, javascript: js)
        _ = await Self.runOSAScript(script)
    }

    static func isArcRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: ArcBrowser.bundleID).isEmpty
    }

    static let tabProbeJS = "(()=>{const m=[...document.querySelectorAll('video,audio')]"
        + ".map(e=>({paused:e.paused,ended:e.ended,ct:e.currentTime,dur:e.duration||0,"
        + "rs:e.readyState,muted:e.muted,rate:e.playbackRate}));"
        + "const md=navigator.mediaSession&&navigator.mediaSession.metadata;"
        + "return JSON.stringify({media:m,meta:md?{title:md.title,artist:md.artist,album:md.album}:null,"
        + "dt:document.title})})()"

    static func probeScript(mediaHosts: [String]) -> String {
        let hostConditions = mediaHosts
            .map { "u contains \"\($0)\"" }
            .joined(separator: " or ")
        return """
        with timeout of \(Int(probeTimeout)) seconds
        set output to ""
        tell application "Arc"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to URL of t
                    if \(hostConditions) then
                        try
                            set probeResult to execute t javascript "\(escapedForAppleScript(tabProbeJS))"
                            set output to output & (id of t) & tab & probeResult & linefeed
                        end try
                    end if
                end repeat
            end repeat
        end tell
        return output
        end timeout
        """
    }

    static func commandScript(tabID: String, javascript: String) -> String {
        """
        with timeout of \(Int(probeTimeout)) seconds
        tell application "Arc"
            repeat with w in windows
                repeat with t in tabs of w
                    if (id of t) is "\(tabID)" then
                        return execute t javascript "\(escapedForAppleScript(javascript))"
                    end if
                end repeat
            end repeat
        end tell
        end timeout
        """
    }

    static func escapedForAppleScript(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func parseProbeOutput(_ stdout: String, sampledAt: Date = Date()) -> [BrowserMediaSnapshot] {
        stdout.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let json = parts[1].data(using: .utf8) else { return nil }
            return BrowserMediaNormalizer.normalize(
                tabID: String(parts[0]), probeJSON: json, sampledAt: sampledAt
            )
        }
    }

    struct ScriptResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    static func runOSAScript(_ script: String) async -> ScriptResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let killer = DispatchWorkItem { [weak process] in
                    if let process, process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + killTimeout, execute: killer)

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    killer.cancel()
                    continuation.resume(returning: ScriptResult(exitCode: -1, stdout: "", stderr: "spawn failed"))
                    return
                }
                killer.cancel()
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                continuation.resume(returning: ScriptResult(
                    exitCode: process.terminationStatus, stdout: stdout, stderr: stderr
                ))
            }
        }
    }
}
