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
                DockToggleButton()
                    .frame(width: 40, height: 48)
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
                CPUWidget(model: model)
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
        // SwiftUI .help() doesn't fire on our non-activating panel, so drive the
        // shared tooltip controller on hover (same as the agent icons).
        .onHover { h in
            if h { TooltipController.shared.show(text: "Apps", near: NSEvent.mouseLocation) }
            else { TooltipController.shared.hide() }
        }
    }
}

private struct DockToggleButton: View {
    @ObservedObject private var dock = DockController.shared
    @State private var hover = false

    var body: some View {
        Button {
            dock.toggle()
        } label: {
            Image(systemName: dock.suppressed ? "rectangle" : "rectangle.bottomthird.inset.filled")
                .resizable().scaledToFit()
                .padding(11)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dock.suppressed
                              ? Color.accentColor.opacity(hover ? 0.95 : 0.85)  // lit = actively suppressing
                              : Color.white.opacity(hover ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hover = h
            if h {
                let text = dock.suppressed
                    ? "Dock suppressed (won't pop up) — click to allow it"
                    : "Dock can pop up from the bottom — click to suppress"
                TooltipController.shared.show(text: text, near: NSEvent.mouseLocation)
            } else {
                TooltipController.shared.hide()
            }
        }
    }
}

private struct WindowTile: View {
    let entry: WindowEntry
    let icon: NSImage?
    @State private var hover = false

    var body: some View {
        Button {
            bringForward()
        } label: {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable().scaledToFit().frame(width: 32, height: 32)
                        .opacity(entry.minimized ? 0.55 : 1.0)
                }
                Text(displayLabel(entry))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 11))
                    .foregroundColor(entry.minimized ? Color.white.opacity(0.65) : .white)
                    .italic(entry.minimized)
                    .frame(width: 110, alignment: .leading)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hover ? 0.18 : (entry.minimized ? 0.04 : 0.08)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("\(entry.appName) — \(entry.title)")
        .contextMenu {
            Button {
                bringForward()
            } label: {
                Label("Bring to Front", systemImage: "arrow.up.forward.app")
            }

            Button {
                AXBridge.setMinimized(
                    pid: entry.pid,
                    window: entry.axElement,
                    title: entry.title,
                    minimized: !entry.minimized
                )
            } label: {
                Label(entry.minimized ? "Restore" : "Minimize", systemImage: entry.minimized ? "rectangle" : "minus")
            }
            .disabled(!canControlWindow)

            Button(role: .destructive) {
                AXBridge.close(pid: entry.pid, window: entry.axElement, title: entry.title)
            } label: {
                Label("Close Window", systemImage: "xmark.circle")
            }
            .disabled(!canControlWindow)

            Divider()

            Button {
                AXBridge.quit(pid: entry.pid)
            } label: {
                Label("Quit \(entry.appName)", systemImage: "power")
            }
        }
    }

    private var canControlWindow: Bool {
        entry.axElement != nil || entry.id.hasPrefix("cg:")
    }

    private func bringForward() {
        if let win = entry.axElement {
            AXBridge.raise(pid: entry.pid, window: win)
        } else if entry.id.hasPrefix("cg:") {
            AXBridge.raiseByTitle(pid: entry.pid, title: entry.title)
        } else {
            AXBridge.activate(pid: entry.pid)
        }
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
            openAgent(agent)
        } label: {
            Group {
                if let icon = agent.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit().foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: 26, height: 26)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(hover ? 0.18 : 0.0))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hover = h
            if h {
                TooltipController.shared.show(text: agent.name, near: NSEvent.mouseLocation)
            } else {
                TooltipController.shared.hide()
            }
        }
    }
}

private func openAgent(_ agent: AgentApp) {
    // 1) If the agent already has any AX window, raise it (covers e.g. apps
    //    whose "main UI" window is already open behind everything).
    let appElem = AXUIElementCreateApplication(agent.id)
    var winsVal: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winsVal) == .success,
       let windows = winsVal as? [AXUIElement], let first = windows.first {
        AXBridge.raise(pid: agent.id, window: first)
        return
    }
    // 2) Otherwise re-open the app's bundle, which triggers most menu-bar apps
    //    to surface their preferences / popover / main window — the same effect
    //    you'd get by relaunching them from Spotlight while already running.
    if let app = NSRunningApplication(processIdentifier: agent.id),
       let url = app.bundleURL {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
        return
    }
    // 3) Last-resort fallback: just activate the process.
    AXBridge.activate(pid: agent.id)
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

private func displayLabel(_ entry: WindowEntry) -> String {
    let raw = entry.title.isEmpty ? entry.appName : entry.title
    return TitleCleaner.clean(raw, appName: entry.appName)
}

enum TitleCleaner {
    private static let emDashSep = " — "
    private static let hyphenSep = " - "
    private static let sizeRegex = try! NSRegularExpression(
        pattern: #"^\d+\s*[×xX]\s*\d+$"#
    )

    static func clean(_ title: String, appName: String) -> String {
        let isTerminalish = ["Terminal", "iTerm", "iTerm2", "Alacritty", "Kitty", "WezTerm", "Ghostty"]
            .contains(appName)
        guard isTerminalish else { return title }

        let username = NSUserName()
        for sep in [emDashSep, hyphenSep] {
            if !title.contains(sep) { continue }
            var parts = title.components(separatedBy: sep)

            // Drop leading "user" / "user@host" segments.
            while let first = parts.first,
                  first == username || first.hasPrefix("\(username)@") {
                parts.removeFirst()
            }
            // Drop trailing "WIDTHxHEIGHT" segments.
            while let last = parts.last {
                let range = NSRange(last.startIndex..<last.endIndex, in: last)
                if sizeRegex.firstMatch(in: last, range: range) != nil {
                    parts.removeLast()
                } else { break }
            }

            let result = parts.joined(separator: sep).trimmingCharacters(in: .whitespaces)
            return result.isEmpty ? title : result
        }
        return title
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
