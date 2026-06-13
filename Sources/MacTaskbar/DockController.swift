import AppKit
import Combine

/// Suppresses the macOS Dock so it won't slide up from the bottom edge over the
/// taskbar.
///
/// Plain auto-hide is NOT enough — the Dock still reveals when you hover the
/// bottom edge. Real suppression sets a very large `autohide-delay` so the Dock
/// effectively never appears, on top of `autohide`. Those keys are only read
/// when the Dock launches, so applying them needs a `killall Dock` (a brief
/// relaunch, no special permission). Reading current state goes through
/// CFPreferences — instant and permission-free.
final class DockController: ObservableObject {
    static let shared = DockController()

    /// True when the Dock is suppressed (won't pop up from the bottom edge).
    @Published private(set) var suppressed: Bool = false

    private let domain = "com.apple.dock"
    private let cfDomain = "com.apple.dock" as CFString
    /// Seconds the Dock waits before revealing on hover. ~1000s ⇒ never.
    private let suppressDelay = "1000"
    /// A read-back delay at/above this is treated as "suppressed".
    private let suppressThreshold = 100.0

    private init() {}

    /// Re-read the live Dock state from preferences (no permission needed).
    func refresh() {
        CFPreferencesAppSynchronize(cfDomain)
        let autohide = (CFPreferencesCopyAppValue("autohide" as CFString, cfDomain) as? Bool) ?? false
        let delay = (CFPreferencesCopyAppValue("autohide-delay" as CFString, cfDomain) as? Double) ?? 0
        let now = autohide && delay >= suppressThreshold
        if now != suppressed { suppressed = now }
    }

    func toggle() {
        setSuppressed(!suppressed)
    }

    func setSuppressed(_ on: Bool) {
        suppressed = on  // optimistic; reconciled after the Dock relaunches

        if on {
            // Hidden AND set to effectively never reveal on hover.
            defaultsWrite(["autohide", "-bool", "true"])
            defaultsWrite(["autohide-delay", "-float", suppressDelay])
            defaultsWrite(["autohide-time-modifier", "-float", "0"])
        } else {
            // Drop our reveal-delay overrides so the Dock behaves normally
            // again (auto-hide left as the user had it).
            defaultsDelete("autohide-delay")
            defaultsDelete("autohide-time-modifier")
        }
        restartDock()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - defaults / killall

    private func defaultsWrite(_ args: [String]) {
        run("/usr/bin/defaults", ["write", domain] + args)
    }

    private func defaultsDelete(_ key: String) {
        // Non-zero exit if the key is absent — harmless, ignore.
        run("/usr/bin/defaults", ["delete", domain, key])
    }

    private func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }

    private func run(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            NSLog("DockController \(launchPath) \(args) failed: \(error)")
        }
    }
}
