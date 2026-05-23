import SwiftUI
import AppKit

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    @State private var startMenuOpen = false

    var body: some View {
        ZStack {
            VisualEffectBackground()
            HStack(spacing: 6) {
                StartButton(isOpen: $startMenuOpen)
                    .frame(width: 48, height: 48)
                if !model.axTrusted {
                    AXWarningPill()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.windows) { entry in
                            WindowTile(entry: entry, icon: model.icon(for: entry))
                        }
                    }
                }
                Spacer(minLength: 0)
                AgentStrip(agents: model.agents)
                ClockView()
                    .padding(.trailing, 12)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 56)
    }
}

private struct StartButton: View {
    @Binding var isOpen: Bool
    var body: some View {
        Button {
            StartMenuController.shared.toggle(relativeTo: NSApp.keyWindow ?? NSApp.windows.first)
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .resizable().scaledToFit()
                .padding(10)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.85))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct WindowTile: View {
    let entry: WindowEntry
    let icon: NSImage?
    @State private var hover = false

    var body: some View {
        Button {
            AXBridge.raise(pid: entry.pid, window: entry.axElement)
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable().scaledToFit().frame(width: 24, height: 24)
                        .opacity(entry.minimized ? 0.55 : 1.0)
                }
                Text(entry.title.isEmpty ? entry.appName : entry.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12))
                    .foregroundColor(entry.minimized ? Color.white.opacity(0.65) : .white)
                    .italic(entry.minimized)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hover ? 0.18 : (entry.minimized ? 0.04 : 0.08)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(entry.appName) — \(entry.title)")
    }
}

private struct AXWarningPill: View {
    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Grant Accessibility").font(.system(size: 11))
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private struct AgentStrip: View {
    let agents: [AgentApp]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(agents) { agent in
                AgentIcon(agent: agent)
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct AgentIcon: View {
    let agent: AgentApp
    @State private var hover = false
    var body: some View {
        Button {
            if let app = NSRunningApplication(processIdentifier: agent.id) {
                if #available(macOS 14.0, *) { app.activate() }
                else { app.activate(options: [.activateIgnoringOtherApps]) }
            }
        } label: {
            Group {
                if let icon = agent.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit().foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: 20, height: 20)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(hover ? 0.18 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(agent.name)
    }
}

private struct ClockView: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        Text(now, format: .dateTime.hour().minute())
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundColor(.white)
            .onReceive(timer) { now = $0 }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
