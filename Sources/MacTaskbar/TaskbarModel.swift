import AppKit
import Combine

final class TaskbarModel: ObservableObject {
    @Published var windows: [WindowEntry] = []
    @Published var agents: [AgentApp] = []
    @Published var axTrusted: Bool = AXBridge.isTrusted

    func refresh() {
        let next = WindowEnumerator.list()
        if next != windows { windows = next }
        let nextAgents = MenuBarAgents.list()
        if nextAgents != agents { agents = nextAgents }
        let t = AXBridge.isTrusted
        if t != axTrusted { axTrusted = t }
    }

    func icon(for entry: WindowEntry) -> NSImage? {
        NSRunningApplication(processIdentifier: entry.pid)?.icon
    }
}
