import Foundation
import Darwin

/// Samples system-wide CPU usage by diffing `host_processor_info` tick counters
/// between calls. First call returns 0 (no baseline yet).
final class CPUSampler {
    private var previous: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

    func sample() -> Double {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info = info else { return 0 }
        defer {
            let addr = vm_address_t(bitPattern: info)
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, addr, size)
        }

        var current: [(UInt32, UInt32, UInt32, UInt32)] = []
        current.reserveCapacity(Int(numCPUs))
        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            current.append((
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }

        defer { previous = current }
        guard previous.count == current.count else { return 0 }

        var used: Double = 0
        var total: Double = 0
        for i in 0..<current.count {
            let p = previous[i]
            let c = current[i]
            let dU = Double(c.0 &- p.0)
            let dS = Double(c.1 &- p.1)
            let dI = Double(c.2 &- p.2)
            let dN = Double(c.3 &- p.3)
            used += dU + dS + dN
            total += dU + dS + dI + dN
        }
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, used / total))
    }
}

struct TopProc: Identifiable {
    let id: Int32
    let pid: Int32
    let cpu: Double
    let command: String
}

enum TopProcesses {
    static func snapshot(limit: Int = 12) -> [TopProc] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aco", "pid,%cpu,comm", "-r"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }

        var result: [TopProc] = []
        let lines = out.split(separator: "\n").dropFirst()    // header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Expected: "<pid> <pcpu> <comm-with-spaces>"
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]) else { continue }
            let cmd = String(parts[2])
            // Last path component for readability.
            let display = (cmd as NSString).lastPathComponent
            result.append(TopProc(id: pid, pid: pid, cpu: cpu, command: display))
            if result.count >= limit { break }
        }
        return result
    }
}
