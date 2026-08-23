#if DEBUG
import SwiftUI

enum DebugGeometry {
    static let enabled = ProcessInfo.processInfo.environment["PI_DEBUG_GEOMETRY"] == "1"
}

struct DebugFrameReporter: View {
    let label: String
    let color: Color

    var body: some View {
        if DebugGeometry.enabled {
            GeometryReader { proxy in
                Rectangle()
                    .strokeBorder(color, lineWidth: 1)
                    .onAppear { report(proxy) }
                    .onChange(of: proxy.frame(in: .global)) { report(proxy) }
            }
            .allowsHitTesting(false)
        }
    }

    private func report(_ proxy: GeometryProxy) {
        let frame = proxy.frame(in: .global)
        print("PI_GEO swiftui[\(label)] globalTopLeftFrame=\(frame)")
    }
}
#endif
