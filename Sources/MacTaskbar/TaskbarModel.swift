import AppKit
import Combine

final class TaskbarModel: ObservableObject {
    @Published var windows: [WindowEntry] = []
    @Published var agents: [AgentApp] = []
    @Published var axTrusted: Bool = AXBridge.isTrusted
    @Published var cpuUsage: Double = 0          // 0...1
    @Published var cpuHistory: [Double] = []     // most recent last; ~60 samples

    private let cpu = CPUSampler()
    private var cpuTick = 0

    // Stable tile order: we remember the first index each window id was seen
    // at and use that as the sort key, so clicking a window (which reorders
    // AX's internal window list by recency) doesn't shuffle the bar.
    private var order: [String: Int] = [:]
    private var nextSlot = 0

    private func stabilize(_ entries: [WindowEntry]) -> [WindowEntry] {
        let live = Set(entries.map(\.id))
        // Drop ids that have disappeared so their slot can be reclaimed if the
        // same id ever comes back (unlikely — ids encode pid + index/title).
        order = order.filter { live.contains($0.key) }
        for e in entries where order[e.id] == nil {
            order[e.id] = nextSlot
            nextSlot += 1
        }
        return entries.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    func refresh() {
        let next = stabilize(WindowEnumerator.list())
        if next != windows { windows = next }
        let nextAgents = MenuBarAgents.list()
        if nextAgents != agents { agents = nextAgents }
        let t = AXBridge.isTrusted
        if t != axTrusted { axTrusted = t }

        // Sample CPU every 2nd refresh (≈ every 2s given the 1Hz timer).
        cpuTick &+= 1
        if cpuTick % 2 == 0 {
            let u = cpu.sample()
            cpuUsage = u
            cpuHistory.append(u)
            if cpuHistory.count > 60 { cpuHistory.removeFirst(cpuHistory.count - 60) }
        }
    }

    func icon(for entry: WindowEntry) -> NSImage? {
        NSRunningApplication(processIdentifier: entry.pid)?.icon
    }
}
