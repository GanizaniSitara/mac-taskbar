import SwiftUI
import AppKit

struct CPUWidget: View {
    @ObservedObject var model: TaskbarModel
    @State private var hover = false

    var body: some View {
        Button {
            CPUDetailController.shared.toggle()
        } label: {
            CPUSparkline(samples: Array(model.cpuHistory.suffix(15)))
                .frame(width: 24, height: 32)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hover ? 0.18 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("CPU \(Int((model.cpuUsage * 100).rounded()))% — click for top processes")
    }

}

private struct CPUSparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = max(samples.count, 1)
            let stride = n > 1 ? w / CGFloat(n - 1) : 0

            // Filled area
            Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * stride
                    let y = h - CGFloat(v) * h
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                p.addLine(to: CGPoint(x: CGFloat(max(n - 1, 0)) * stride, y: h))
                p.closeSubpath()
            }
            .fill(LinearGradient(
                colors: [Color(red: 0.05, green: 0.85, blue: 0.45).opacity(0.55), Color(red: 0.05, green: 0.85, blue: 0.45).opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))

            // Stroke
            Path { p in
                for (i, v) in samples.enumerated() {
                    let x = CGFloat(i) * stride
                    let y = h - CGFloat(v) * h
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color(red: 0.05, green: 0.85, blue: 0.45), lineWidth: 1.4)
        }
    }
}

@MainActor
final class CPUDetailController {
    static let shared = CPUDetailController()
    private var panel: NSPanel?
    private var refreshTimer: Timer?

    func toggle() {
        if let p = panel, p.isVisible { hide(); return }
        show()
    }

    func hide() {
        refreshTimer?.invalidate(); refreshTimer = nil
        panel?.orderOut(nil)
    }

    private func show() {
        let model = CPUDetailModel()
        model.reload()
        let view = CPUDetailView(model: model)
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 180, height: 360)
        host.frame = NSRect(origin: .zero, size: size)

        let p = panel ?? NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.frame.maxX - size.width - 12,
                y: screen.frame.minY + 56 + 6
            )
            p.setFrameOrigin(origin)
        }
        p.orderFrontRegardless()
        panel = p

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in model.reload() }
        }
    }
}

@MainActor
final class CPUDetailModel: ObservableObject {
    @Published var procs: [TopProc] = []

    func reload() {
        // ps can block ~50ms; do it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snap = TopProcesses.snapshot(limit: 12)
            DispatchQueue.main.async { self?.procs = snap }
        }
    }
}

struct CPUDetailView: View {
    @ObservedObject var model: CPUDetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top CPU").font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.black.opacity(0.25))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.procs) { proc in
                        HStack(spacing: 6) {
                            Text(proc.command)
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(String(format: "%.0f%%", proc.cpu))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 36, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
    }
}
