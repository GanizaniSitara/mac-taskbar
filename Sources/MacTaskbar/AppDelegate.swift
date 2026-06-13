import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: TaskbarPanel!
    private let model = TaskbarModel()
    private var refreshTimer: Timer?
    private var tick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        AXBridge.ensurePermissionPrompt()

        panel = TaskbarPanel()
        let view = TaskbarView(model: model)
        panel.contentView = NSHostingView(rootView: view)
        positionPanel()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        let ws = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            ws.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }

        HotkeyMonitor.shared.start()
        model.refresh()
        // First Dock-state read, deferred off the initial render pass so the
        // synchronous Apple Event doesn't reenter the SwiftUI update.
        DispatchQueue.main.async { DockController.shared.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.refresh()
            // Re-read the macOS Dock auto-hide state every ~5s so the toggle
            // reflects changes made elsewhere (e.g. System Settings).
            self.tick &+= 1
            if self.tick % 5 == 0 { DockController.shared.refresh() }
        }
    }

    @objc private func workspaceChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.model.refresh()
        }
    }

    @objc private func screenChanged() { positionPanel() }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let h: CGFloat = 56
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: h
        )
        panel.setFrame(frame, display: true)
    }
}
