import AppKit
import SwiftUI

struct TimerRing: View {
    var progress: Double
    var isPaused: Bool
    var isEnding: Bool
    var size: CGFloat

    var body: some View {
        let width = max(1.5, size * 0.16)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.004, progress))
                .stroke(style: StrokeStyle(lineWidth: width, lineCap: .round))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.9), value: progress)
    }

    private var tint: Color {
        if isPaused { return .white.opacity(0.4) }
        return isEnding ? .red : .orange
    }
}

struct TimerChip: View {
    var snapshot: SystemTimerSnapshot
    var now: Date
    var ringSize: CGFloat
    var fontSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            TimerRing(
                progress: snapshot.progress(at: now),
                isPaused: snapshot.isPaused,
                isEnding: snapshot.isEnding(at: now),
                size: ringSize
            )
            Text(MediaTimeFormatter.format(snapshot.remaining(at: now)))
                .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(snapshot.isPaused ? 0.5 : 0.85))
        }
    }
}

struct TimerCompactChip: View {
    @ObservedObject private var controller = SystemTimerController.shared
    @ObservedObject private var lang = AppLanguageManager.shared

    var body: some View {
        if let snapshot = controller.snapshot {
            TimerChip(snapshot: snapshot, now: controller.tick, ringSize: 11, fontSize: 10)
                .help(lang.string(snapshot.isPaused ? "timer.paused" : "timer.running"))
        }
    }
}

struct TimerExpandedChip: View {
    @ObservedObject private var controller = SystemTimerController.shared
    @ObservedObject private var lang = AppLanguageManager.shared
    @State private var isHovering = false

    var body: some View {
        if let snapshot = controller.snapshot {
            Button(action: openClock) {
                TimerChip(snapshot: snapshot, now: controller.tick, ringSize: 15, fontSize: 12)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(isHovering ? 0.12 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(lang.string(snapshot.isPaused ? "timer.paused" : "timer.openClock"))
        }
    }

    private func openClock() {
        let url = URL(fileURLWithPath: "/System/Applications/Clock.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }
}
