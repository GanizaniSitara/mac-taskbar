import AppKit

/// Watches for the Command key being pressed and released alone (no other key,
/// no mouse click, short hold). When that happens, toggles the Start menu —
/// same UX as the Windows key on Windows.
@MainActor
final class HotkeyMonitor {
    static let shared = HotkeyMonitor()

    private var cmdDownAt: Date?
    private var cmdUsedAsModifier = false
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }

        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlags(event)
        }
        let usedHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            if self.cmdDownAt != nil { self.cmdUsedAsModifier = true }
        }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: usedHandler
        ) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            flagsHandler(event); return event
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { event in usedHandler(event); return event }
        ) {
            monitors.append(m)
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        if cmd {
            if cmdDownAt == nil {
                cmdDownAt = Date()
                cmdUsedAsModifier = false
            }
        } else {
            guard let start = cmdDownAt else { return }
            let elapsed = Date().timeIntervalSince(start)
            cmdDownAt = nil
            let used = cmdUsedAsModifier
            cmdUsedAsModifier = false

            // Tap, not a sustained chord: alone, no other key/mouse, < 300ms.
            if !used && elapsed < 0.30 {
                StartMenuController.shared.toggle(relativeTo: nil)
            }
        }
    }
}
