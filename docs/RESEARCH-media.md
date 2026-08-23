# Research: media

## Recommendation
Use the ungive "mediaremote-adapter" technique as the single primary provider for BOTH reading and controlling global Now Playing on macOS 26: spawn Apple-signed /usr/bin/perl, which mediaremoted trusts (it reports bundle ID com.apple.perl5), have it dlopen a small bundled helper framework (MediaRemoteAdapter.framework, BSD-3-Clause) via DynaLoader, and consume newline-delimited JSON from its stdout with Foundation Process + Pipe ("stream" for live updates, "get" for snapshots, "send"/"seek" for commands). This is exactly what the actively maintained notch apps (boring.notch, mew-notch, DockDoor) ship today. Wrap it behind a NowPlayingProviding protocol with an AppleScript provider (Spotify + Music apps) as a fallback selected at runtime via the adapter's "test" command, and as the seek path for players that ignore MediaRemote seek. VERIFIED LIVE on this exact machine (macOS 26.6.2, build 25G83, Perl 5.34.1): adapter `test` exits 0 (fully functional), `stream`/`get` work, terminates cleanly on SIGTERM, while a direct in-process MRMediaRemoteGetNowPlayingInfo call returns nil (still blocked for unentitled processes, as it has been since macOS 15.4). All needed sources and PREBUILT VERIFIED BINARIES are already vendored locally at ~/vendor/mediaremote-adapter/ — the implementation agent needs no network access.

## Implementation notes
════════════════════════════════════════════════════
0. VERIFIED FACTS (macOS 26.6.2 / 25G83, this machine, 2026-08-22)
════════════════════════════════════════════════════
- Since macOS 15.4, mediaremoted verifies entitlements: MRMediaRemoteGetNowPlayingInfo / RegisterForNowPlayingNotifications return nothing for processes without com.apple.mediaremote.services (or a com.apple.* bundle ID). CONFIRMED STILL BLOCKED on 26.6.2: a plain swiftc-compiled binary calling MRMediaRemoteGetNowPlayingInfo via CFBundleGetFunctionPointerForName got nil.
- /usr/bin/perl is an Apple platform binary identified as com.apple.perl5 by mediaremoted → it IS granted access. CONFIRMED on 26.6.2: `perl mediaremote-adapter.pl <fw> <testclient> test` → exit 0 (the test simulates playback via MPNowPlayingInfoCenter in a helper and reads it back through MediaRemote inside perl — exit 0 is conclusive proof the read path works).
- `stream` emits `{"type":"data","diff":false,"payload":{}}` immediately when nothing plays, streams NDJSON updates, and exits cleanly on SIGTERM. CONFIRMED.
- MRMediaRemoteSendCommand / MRMediaRemoteSetElapsedTime called DIRECTLY from an unentitled app still work (the 15.4 block only covers reads). boring.notch main branch relies on this today. However, route commands through the perl adapter anyway — it is guaranteed-entitled and future-proof.
- Local toolchain: /usr/bin/perl 5.34.1, Xcode 26.6 clang builds the framework in ~2 s; cmake NOT installed (not needed — see 2b).

════════════════════════════════════════════════════
1. VENDORED, ALREADY-VERIFIED ARTIFACTS (no network needed)
════════════════════════════════════════════════════
~/vendor/mediaremote-adapter/
├── ungive-adapter/                 # full source of github.com/ungive/mediaremote-adapter (master, BSD-3-Clause)
│   ├── bin/mediaremote-adapter.pl  # THE perl script (8.4 KB), sha256 984d622eeebbcb17656d157a49272b02fb741593ae2ec624d1926c12d955c8a1
│   ├── src/adapter/*.m, src/private/MediaRemote.m, src/utility/*.m, include/MediaRemoteAdapter.h
│   └── src/test/*.m                # TestClient source
├── prebuilt/
│   ├── MediaRemoteAdapter.framework/MediaRemoteAdapter   # arm64 dylib compiled+verified on this Mac, sha256 d7b9ce…5eb3
│   └── MediaRemoteAdapterTestClient                      # verified test helper
└── ejbills-swiftpm-fork/           # github.com/ejbills/mediaremote-adapter — SPM package alternative (see §7)

Re-verify any time:
  D=~/vendor/mediaremote-adapter
  /usr/bin/perl $D/ungive-adapter/bin/mediaremote-adapter.pl $D/prebuilt/MediaRemoteAdapter.framework $D/prebuilt/MediaRemoteAdapterTestClient test && echo OK   # exits 0

════════════════════════════════════════════════════
2. BUNDLING INTO THE APP
════════════════════════════════════════════════════
(a) Copy into the Xcode project:
  - mediaremote-adapter.pl → target "Copy Bundle Resources" (ends up in Contents/Resources/).
  - MediaRemoteAdapter.framework → "Frameworks, Libraries, and Embedded Content" with EMBED WITHOUT SIGNING or Embed & Sign (either works for an unsandboxed personal app; the framework must NOT be linked against — set to "Do Not Embed"+copy-files phase to Frameworks/ is also fine, the app never links it; it is ONLY passed as an argv to perl and loaded by perl's DynaLoader).
  - MediaRemoteAdapterTestClient → Copy Bundle Resources (optional but recommended, enables the `test` fallback gate).
  Runtime paths: scriptURL = Bundle.main.url(forResource:"mediaremote-adapter", withExtension:"pl"); frameworkPath = Bundle.main.privateFrameworksPath! + "/MediaRemoteAdapter.framework" (this is exactly what boring.notch and mew-notch do).
(b) Rebuilding the framework from source WITHOUT cmake (verified command):
  cd ~/vendor/mediaremote-adapter/ungive-adapter
  mkdir -p out/MediaRemoteAdapter.framework
  clang -dynamiclib -fobjc-arc -fmodules -Iinclude -Isrc -o out/MediaRemoteAdapter.framework/MediaRemoteAdapter src/adapter/*.m src/private/*.m src/utility/*.m -framework Foundation -framework AppKit
  clang -fobjc-arc -fmodules -Iinclude -Isrc -o out/MediaRemoteAdapterTestClient src/test/*.m -framework Foundation -framework AppKit -framework MediaPlayer
  (The .framework directory only needs the inner Mach-O named exactly like the framework basename; no Info.plist required — the perl script does basename minus ".framework" and dlopens FRAMEWORK_PATH/MediaRemoteAdapter. Add -arch arm64 -arch x86_64 for universal; arm64-only is fine on this machine.)
(c) How the perl script works internally (bin/mediaremote-adapter.pl): argv = FRAMEWORK_PATH [TEST_CLIENT_PATH] FUNCTION [PARAMS|OPTIONS]; it DynaLoader::dl_load_file()s the framework binary, passes options/params to the native code via environment variables (MEDIAREMOTEADAPTER_OPTION_<name>, MEDIAREMOTEADAPTER_PARAM_adapter_<fn>_<idx>_<name>, MEDIAREMOTEADAPTER_TEST_CLIENT_PATH), resolves symbol adapter_<function>[_env], installs it as a perl xsub and calls it. The native code runs an NSRunLoop, registers MediaRemote notifications and prints NDJSON to stdout. ALWAYS PASS ABSOLUTE PATHS.

════════════════════════════════════════════════════
3. PROVIDER ARCHITECTURE
════════════════════════════════════════════════════
protocol NowPlayingProviding: AnyObject {
    var stateStream: AsyncStream<NowPlayingState?> { get }   // nil == nothing playing
    func start() async; func stop()
    func play(); func pause(); func togglePlayPause(); func nextTrack(); func previousTrack()
    var canSeek: Bool { get }; func seek(to seconds: Double)
}
struct NowPlayingState { title, artist, album: String; bundleIdentifier: String; isPlaying: Bool; duration: TimeInterval; elapsedTime: TimeInterval; elapsedTimestamp: Date; playbackRate: Double; artwork: NSImage?; shuffleMode/repeatMode: Int? }
UI-side live position (do NOT poll): position(at now) = elapsedTime + (isPlaying ? playbackRate * now.timeIntervalSince(elapsedTimestamp) : 0), clamped to duration.

Providers:
1. MediaRemoteAdapterProvider (primary, all sources incl. Spotify/Music/browsers — anything that publishes to Now Playing).
2. ScriptingPlayerProvider (fallback; two configs: Spotify "com.spotify.client", Music "com.apple.Music"; 1–2 s polling timer; only when the app is running per NSRunningApplication).
Selection at app launch: run `perl script.pl FW TESTCLIENT test` (Process, waitUntilExit, ~5 s timeout). Exit 0 → MediaRemoteAdapterProvider. Non-zero → ScriptingPlayerProvider(s). Cache the result per OS build (re-run after macOS updates). Note: `test` may briefly register a fake now-playing item system-wide when nothing is playing — harmless.

════════════════════════════════════════════════════
4. READING — launch args + JSON event shapes
════════════════════════════════════════════════════
Process: executableURL=/usr/bin/perl
arguments = [scriptPath, frameworkPath, "stream", "--debounce=100"]                    // diff mode (default): payload carries only changed keys
   or      [scriptPath, frameworkPath, "stream", "--no-diff", "--debounce=100"]        // every event is full state (simpler merge, but re-emits full artwork each time; add --no-artwork if you don't render art)
One-shot:  [scriptPath, frameworkPath, "get", "--now"]                                  // single JSON dict or `null`
process.standardOutput = Pipe(); read line-by-line (NDJSON, one JSON object per line; lines can be several hundred KB when artwork is embedded — use a growing buffer split on \n, never assume one read == one line). stderr lines are non-fatal diagnostics unless the process exits non-zero; NEVER auto-restart after a non-zero exit.

stream event shape:  {"type":"data","diff":<bool>,"payload":{…}}
  - type is always "data".
  - diff=false → payload IS the complete current state (empty {} payload = nothing playing).
  - diff=true → merge payload over previous full state; a key explicitly set to null means "key vanished — remove it".
payload keys (same for get): bundleIdentifier, parentApplicationBundleIdentifier (prefer it over bundleIdentifier when present — browser helper processes), playing(Bool), title, artist, album, duration(seconds Double), elapsedTime(seconds Double), timestamp(String "yyyy-MM-dd'T'HH:mm:ss'Z'" UTC — parse with ISO8601DateFormatter; it is the moment elapsedTime was sampled), playbackRate(Double), artworkData(base64 String), artworkMimeType, shuffleMode(1 off/2 albums/3 tracks), repeatMode(1 off/2 one/3 all), plus occasionally composer, genre, mediaType, trackNumber, queueIndex, uniqueIdentifier, isMusicApp, etc. Mandatory non-null in `get`: bundleIdentifier, playing, title (otherwise `get` prints literally `null`).
Optional flags: --micros renames duration→durationMicros, elapsedTime→elapsedTimeMicros, timestamp→timestampEpochMicros (numeric epoch µs — easier than date parsing); --no-artwork drops artwork keys; get --now adds elapsedTimeNow (±1 s estimate).

ARTWORK TRANSPORT: base64 inside artworkData + artworkMimeType (image/jpeg | image/png), transported over the same stdout pipe; decode Data(base64Encoded: str.trimmingCharacters(in:.whitespacesAndNewlines)) → NSImage. Artwork lags track changes by a moment (it loads async in the player) — keep previous artwork while title/artist unchanged; the adapter already re-uses artwork in stream mode when it briefly unloads. Typical size 100–500 KB per event.

════════════════════════════════════════════════════
5. SENDING COMMANDS + SEEK
════════════════════════════════════════════════════
Each command = short-lived one-shot Process (fire and forget; mew-notch pattern). Reap it: set terminationHandler or call waitUntilExit on a background queue to avoid zombies.
  [script, fw, "send", "<ID>"] with IDs: 0 kMRPlay, 1 kMRPause, 2 kMRTogglePlayPause, 3 kMRStop, 4 kMRNextTrack, 5 kMRPreviousTrack, 6 kMRToggleShuffle, 7 kMRToggleRepeat, 8/9 start/endForwardSeek, 10/11 start/endBackwardSeek, 12 kMRGoBackFifteenSeconds, 13 kMRSkipFifteenSeconds.
  [script, fw, "seek", "<POSITION_MICROSECONDS>"]   // Int(seconds * 1_000_000)
  [script, fw, "shuffle", "<1|2|3>"], [script, fw, "repeat", "<1|2|3>"], [script, fw, "speed", "<N>"]
SEEK SUPPORT MATRIX: MediaRemote seek (adapter `seek`, or direct MRMediaRemoteSetElapsedTime) works for players that honor the remote-command seek (Apple Music, Safari/Chrome media sessions generally do). Some players ignore it (mew-notch ships an explicit fallback for exactly this) → after issuing adapter seek, if bundleIdentifier is com.apple.Music also run AppleScript `tell application "Music" to set player position to <seconds>`; if com.spotify.client run `tell application "Spotify" to set player position to <seconds>`. Optimistically update local elapsedTime immediately so the UI doesn't snap back. AppleScript seek is second-granularity.
(Alternative used by boring.notch: direct function pointers from /System/Library/PrivateFrameworks/MediaRemote.framework via CFBundleGetFunctionPointerForName — "MRMediaRemoteSendCommand" as (@convention(c)(Int, AnyObject?)->Void), "MRMediaRemoteSetElapsedTime" as (@convention(c)(Double)->Void), "MRMediaRemoteSetShuffleMode"/"MRMediaRemoteSetRepeatMode" as (@convention(c)(Int)->Void). Works unentitled on 26.x today; zero process-spawn latency; keep as an optimization, not the contract.)

════════════════════════════════════════════════════
6. APPLESCRIPT FALLBACK PROVIDER (secondary)
════════════════════════════════════════════════════
Requires Info.plist NSAppleEventsUsageDescription + one-time TCC Automation prompt per target app; target app must be running (guard with NSRunningApplication.runningApplications(withBundleIdentifier:)); poll every 1–2 s with NSAppleScript/OSAScript on a background thread.
Spotify state fetch (boring.notch verbatim, returns a 10-item list):
  tell application "Spotify"
    set playerState to player state is playing
    set currentTrackName to name of current track
    set currentTrackArtist to artist of current track
    set currentTrackAlbum to album of current track
    set trackPosition to player position          -- seconds
    set trackDuration to duration of current track -- MILLISECONDS: divide by 1000
    set shuffleState to shuffling
    set repeatState to repeating
    set currentVolume to sound volume
    set artworkURL to artwork url of current track -- https URL; download with URLSession, cache by URL
    return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL}
  end tell
Music state fetch: same fields except duration is SECONDS, shuffle is `shuffle enabled`, repeat is `song repeat` (off/one/all), and artwork is raw bytes: `set artData to data of artwork 1 of current track` (returns picture data via NSAppleEventDescriptor.data — slow, fetch only on track change).
Controls (both apps): `tell application "Spotify"|"Music" to playpause` / `next track` / `previous track` / `set player position to <seconds>` / `set sound volume to <0-100>`. Music extra: `set favorited of current track to true|false`.
Browsers/other apps: NOT reachable via AppleScript media scripting — the adapter is the only universal read path.

════════════════════════════════════════════════════
7. ALTERNATIVE PACKAGING: ejbills SPM fork (vendored at ~/vendor/mediaremote-adapter/ejbills-swiftpm-fork)
════════════════════════════════════════════════════
Swift package "MediaRemoteAdapter" (used by DockDoor): compiles the adapter ObjC (CIMediaRemote target) into a dynamic framework built by SPM itself; run.pl is a bundle resource; MediaController passes Bundle(for: MediaController.self).executablePath (the SPM-built dylib) to run.pl. Differences: ONE persistent `loop` perl process handles BOTH streaming and commands (commands written to its stdin as lines: play, pause, toggle_play_pause, next_track, previous_track, stop, set_time <seconds>, set_shuffle_mode <0|1|2>, set_repeat_mode <0|1|2>, toggle_shuffle, toggle_repeat, skip_fifteen_seconds, go_back_fifteen_seconds, like_track…), payload keys are ALWAYS micros (durationMicros/elapsedTimeMicros/timestampEpochMicros) plus applicationName/PID/artworkDataBase64, prints literal line "NIL" when nothing plays, auto-restarts listener every 100 events (memory hygiene), computed currentElapsedTime interpolation built in, SIGPIPE ignored. Add via local path in Package.swift/Xcode, set the product to Embed & Sign. Pick this if you prefer library ergonomics over vendored files; pick the ungive files (§2) if you want zero SPM magic and the `test` gating. Both are BSD-3-Clause (attribution: "Jonas van den Berg and contributors"; keep the copyright header/LICENSE in the vendored files).

════════════════════════════════════════════════════
8. TEARDOWN
════════════════════════════════════════════════════
- stream process: fileHandleForReading.readabilityHandler = nil (or cancel the reading Task), process.terminate() (SIGTERM — verified clean exit), process.waitUntilExit(), close both pipe ends. Do this in deinit AND on app termination (NSApplication.willTerminateNotification). Perl dies automatically if the app is killed and the pipe breaks, but explicit terminate avoids orphaned perl processes.
- one-shot command processes: terminationHandler = { _ in } to reap.
- signal(SIGPIPE, SIG_IGN) once at startup (writing to a dead child otherwise kills the app).
- If the stream process exits with code != 0: do NOT relaunch in a loop; re-run `test` and fall back to the AppleScript provider.

════════════════════════════════════════════════════
9. REPO PATHS READ (for provenance)
════════════════════════════════════════════════════
- ungive/mediaremote-adapter: README.md, bin/mediaremote-adapter.pl, CMakeLists.txt, src/adapter/{test.m,keys.m,get.m,stream.m,send.m,seek.m}, src/utility/helpers.m (timestamp format line 126), src/test/{main.m,NowPlayingTest.m}
- TheBoredTeam/boring.notch: boringNotch/MediaControllers/NowPlayingController.swift (adapter stream + direct MRMediaRemoteSendCommand/SetElapsedTime pointers, NowPlayingUpdate/NowPlayingPayload Codable, JSONLinesPipeHandler actor), boringNotch/MediaControllers/MediaControllerProtocol.swift, SpotifyController.swift, AppleMusicController.swift, boringNotch/helpers/MediaChecker.swift, bundled at repo root mediaremote-adapter/mediaremote-adapter.pl
- monuk7735/mew-notch: MewNotch/Utils/Helpers/Media/NowPlaying.swift (stream --no-diff; send/seek via one-shot adapter processes; AppleScript seek fallback for Music/Spotify), resources MewNotch/Resources/Libs/{mediaremote-adapter.pl, MediaRemoteAdapter.framework}
- ejbills/mediaremote-adapter: Package.swift, Sources/MediaRemoteAdapter/{MediaController.swift,TrackInfo.swift,Resources/run.pl}, Sources/CIMediaRemote/*

## Code sketch
import AppKit
import Combine

// MARK: - Contract

struct NowPlayingState: Equatable {
    var bundleIdentifier = ""
    var title = "", artist = "", album = ""
    var isPlaying = false
    var duration: TimeInterval = 0          // seconds
    var elapsedTime: TimeInterval = 0       // seconds, sampled at `elapsedTimestamp`
    var elapsedTimestamp = Date()
    var playbackRate: Double = 0
    var artwork: Data?                      // decoded from base64; render NSImage(data:)
    var shuffleMode: Int?, repeatMode: Int?

    /// Live position without polling.
    func position(at now: Date = .now) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, duration) }
        return min(elapsedTime + playbackRate * now.timeIntervalSince(elapsedTimestamp), duration)
    }
}

protocol NowPlayingProviding: AnyObject {
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { get }  // nil = nothing playing
    func start(); func stop()
    func play(); func pause(); func togglePlayPause()
    func nextTrack(); func previousTrack()
    func seek(to seconds: TimeInterval)
}

// MARK: - Adapter payload (keys match mediaremote-adapter default output)

private struct AdapterEvent: Decodable {
    let type: String?            // "data"
    let diff: Bool?
    let payload: Payload
    struct Payload: Decodable {
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let title: String?, artist: String?, album: String?
        let playing: Bool?
        let duration: Double?, elapsedTime: Double?   // seconds
        let timestamp: String?                        // "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let playbackRate: Double?
        let artworkData: String?, artworkMimeType: String?
        let shuffleMode: Int?, repeatMode: Int?
    }
}

// MARK: - Primary provider (perl + MediaRemoteAdapter.framework)

final class MediaRemoteAdapterProvider: NowPlayingProviding {
    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }

    private let scriptPath: String     // Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")!.path
    private let frameworkPath: String  // Bundle.main.privateFrameworksPath! + "/MediaRemoteAdapter.framework"
    private let testClientPath: String?
    private var streamProcess: Process?
    private var readTask: Task<Void, Never>?
    private static let iso = ISO8601DateFormatter()

    init(scriptPath: String, frameworkPath: String, testClientPath: String?) {
        self.scriptPath = scriptPath; self.frameworkPath = frameworkPath; self.testClientPath = testClientPath
        signal(SIGPIPE, SIG_IGN)
    }

    /// Gate: exit 0 == perl loophole functional on this OS. Run once at startup.
    static func isFunctional(script: String, framework: String, testClient: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script, framework, testClient, "test"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func start() {
        guard streamProcess == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptPath, frameworkPath, "stream", "--no-diff", "--debounce=100"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.terminationHandler = { [weak self] proc in
            if proc.terminationStatus != 0 { self?.subject.send(nil) }  // fatal: caller should fall back, do NOT relaunch blindly
        }
        do { try p.run() } catch { return }
        streamProcess = p
        readTask = Task.detached { [weak self] in
            // NDJSON: lines can be >300 KB (base64 artwork); bytes.lines handles buffering.
            guard let self else { return }
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    guard let data = line.data(using: .utf8),
                          let event = try? JSONDecoder().decode(AdapterEvent.self, from: data) else { continue }
                    self.apply(event)
                }
            } catch { /* pipe closed */ }
        }
    }

    private func apply(_ event: AdapterEvent) {
        let pl = event.payload
        // --no-diff mode: every event is the full state; empty payload => nothing playing.
        guard let title = pl.title, !title.isEmpty else { subject.send(nil); return }
        var s = NowPlayingState()
        s.bundleIdentifier = pl.parentApplicationBundleIdentifier ?? pl.bundleIdentifier ?? ""
        s.title = title; s.artist = pl.artist ?? ""; s.album = pl.album ?? ""
        s.isPlaying = pl.playing ?? false
        s.duration = pl.duration ?? 0
        s.elapsedTime = pl.elapsedTime ?? 0
        s.elapsedTimestamp = pl.timestamp.flatMap { Self.iso.date(from: $0) } ?? Date()
        s.playbackRate = pl.playbackRate ?? (s.isPlaying ? 1 : 0)
        s.shuffleMode = pl.shuffleMode; s.repeatMode = pl.repeatMode
        if let b64 = pl.artworkData {
            s.artwork = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let prev = subject.value, prev.title == s.title, prev.artist == s.artist {
            s.artwork = prev.artwork   // artwork loads late / flickers — keep previous for same track
        }
        subject.send(s)
    }

    // MARK: commands — one-shot perl processes (kMR IDs: 0 play, 1 pause, 2 toggle, 4 next, 5 prev)
    private func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptPath, frameworkPath] + args
        p.terminationHandler = { _ in }        // reap; avoid zombies
        try? p.run()
    }
    func play()            { run(["send", "0"]) }
    func pause()           { run(["send", "1"]) }
    func togglePlayPause() { run(["send", "2"]) }
    func nextTrack()       { run(["send", "4"]) }
    func previousTrack()   { run(["send", "5"]) }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int(seconds * 1_000_000))])              // MediaRemote timeline, microseconds
        // Some players ignore MediaRemote seek — AppleScript belt-and-suspenders (mew-notch pattern):
        let bid = subject.value?.bundleIdentifier
        let script: String? = switch bid {
            case "com.apple.Music":     "tell application \"Music\" to set player position to \(seconds)"
            case "com.spotify.client":  "tell application \"Spotify\" to set player position to \(seconds)"
            default: nil
        }
        if let script { DispatchQueue.global().async { NSAppleScript(source: script)?.executeAndReturnError(nil) } }
        // Optimistic local update so the UI doesn't snap back:
        if var s = subject.value { s.elapsedTime = seconds; s.elapsedTimestamp = Date(); subject.send(s) }
    }

    func stop() {
        readTask?.cancel(); readTask = nil
        if let p = streamProcess, p.isRunning { p.terminationHandler = nil; p.terminate(); p.waitUntilExit() }  // SIGTERM: verified clean
        streamProcess = nil
    }
    deinit { stop() }
}

// MARK: - Wiring (AppDelegate / @main)
// let script  = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")!.path
// let fw      = Bundle.main.privateFrameworksPath! + "/MediaRemoteAdapter.framework"
// let tc      = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path
// provider = if tc == nil || MediaRemoteAdapterProvider.isFunctional(script: script, framework: fw, testClient: tc!) {
//     MediaRemoteAdapterProvider(scriptPath: script, frameworkPath: fw, testClientPath: tc)
// } else {
//     ScriptingPlayerProvider()   // AppleScript polling fallback, §6 of implementation notes
// }
// provider.start()
// NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in provider.stop() }

## Risks
1) The whole technique rides on mediaremoted allowlisting com.apple.* bundle IDs (perl = com.apple.perl5). Apple could close this in any macOS update (the adapter README's first line begs Apple not to). Mitigation is built in: run the `test` command at startup (and after OS updates) and fall back to the AppleScript provider; never auto-relaunch a stream that exited non-zero. As of macOS 26.6.2 (verified today, 2026-08-22) it is fully functional. 2) ungive warns the CLI/JSON API "may experience breaking changes across minor revisions" — the risk is eliminated here because the exact script + framework are vendored and pinned at ~/vendor/mediaremote-adapter (sha256 of the .pl: 984d622e…c8a1). 3) The prebuilt framework was compiled arm64-only with clang (no CMake) and is linker-signed (ad-hoc); fine for this personal unsandboxed app, but re-sign or rebuild if Gatekeeper/hardened-runtime distribution ever matters. It must be re-built if the app ever needs x86_64. 4) `test` may briefly publish a fake now-playing entry system-wide when nothing is playing (documented; helper has no bundle ID so other adapter consumers ignore it). 5) Artwork events are large (100–500 KB base64 per emission); in --no-diff mode use --no-artwork if art isn't rendered, or accept the bandwidth; artwork can arrive seconds after the track change and can transiently vanish — keep the previous image while title/artist match. 6) Browser sources only expose what the site publishes via the Media Session API — elapsed/duration or artwork may be missing or stale for some sites; bundleIdentifier may be a helper process, prefer parentApplicationBundleIdentifier. 7) Seek: MediaRemote `seek` is honored by Apple Music and most Media-Session browsers but ignored by some players (Spotify historically inconsistent) — always double-fire the AppleScript `set player position` for com.spotify.client / com.apple.Music; AppleScript path requires the one-time Automation (TCC) prompt and NSAppleEventsUsageDescription in Info.plist, and only works while the target app runs. 8) Direct MRMediaRemoteSendCommand from the app (boring.notch's current approach) still works unentitled on 26.6.2 but is the likelier next thing Apple blocks — routing commands through perl (as sketched) is the safer default at the cost of ~50 ms process spawn per command. 9) Leaked perl children if teardown is skipped: always terminate() + waitUntilExit() the stream process on quit and reap one-shot processes via terminationHandler; ignore SIGPIPE. 10) Timestamp parsing: default format is exactly "yyyy-MM-dd'T'HH:mm:ss'Z'" (second granularity, UTC); if sub-second precision matters use --micros and read timestampEpochMicros instead. 11) License obligations: BSD-3-Clause (ungive and ejbills) — retain copyright headers and LICENSE file in the vendored copies; no other obligations for personal use.

## Sources
- https://github.com/ungive/mediaremote-adapter (README.md, bin/mediaremote-adapter.pl, src/adapter/*.m, src/utility/helpers.m, src/test/*.m; BSD-3-Clause; badge: tested macOS 26.0 25A5316i)
- https://github.com/ejbills/mediaremote-adapter (Package.swift, Sources/MediaRemoteAdapter/MediaController.swift, Sources/MediaRemoteAdapter/TrackInfo.swift, Sources/MediaRemoteAdapter/Resources/run.pl, Sources/CIMediaRemote/*)
- https://github.com/TheBoredTeam/boring.notch (boringNotch/MediaControllers/NowPlayingController.swift, boringNotch/MediaControllers/MediaControllerProtocol.swift, boringNotch/MediaControllers/SpotifyController.swift, boringNotch/MediaControllers/AppleMusicController.swift, boringNotch/helpers/MediaChecker.swift, mediaremote-adapter/mediaremote-adapter.pl)
- https://github.com/monuk7735/mew-notch (MewNotch/Utils/Helpers/Media/NowPlaying.swift, MewNotch/Resources/Libs/mediaremote-adapter.pl, MewNotch/Resources/Libs/MediaRemoteAdapter.framework)
- https://github.com/aviwad/LyricFever/issues/94 (macOS 15.4 MediaRemote entitlement block; Mx-Iris comment on com.apple.* bundle-ID allowlist)
- https://github.com/Mx-Iris/MediaRemoteWizard (SIP-disable injection alternative — rejected)
- https://github.com/ungive/media-control (brew CLI built on the same adapter)
- Local verification on this machine, macOS 26.6.2 (25G83), Perl 5.34.1, 2026-08-22: adapter `test` exit 0; `get` and `stream --no-artwork --debounce=100` functional, clean SIGTERM exit; direct MRMediaRemoteGetNowPlayingInfo from unentitled swiftc binary returned nil; artifacts vendored at ~/vendor/mediaremote-adapter/