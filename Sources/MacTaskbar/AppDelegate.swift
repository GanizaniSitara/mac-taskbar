import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: TaskbarPanel!
    private let model = TaskbarModel()
    private var refreshTimer: Timer?
    private var tick = 0
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opt this background accessory agent out of App Nap, otherwise macOS
        // throttles/suspends our main-thread timers when the app looks idle and
        // the clock/CPU widgets freeze at their last tick until it wakes.
        // Use the idle-sleep-allowing variant: a menu-bar clock must never keep
        // the Mac awake. Held for the app's lifetime.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Menu-bar taskbar clock and widgets must keep updating"
        )

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
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            ws.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }
        // Activations also feed the Start menu's frequency-of-use ranking.
        ws.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)

        HotkeyMonitor.shared.start()
        model.refresh()
        // First Dock-state read, deferred off the initial render pass so the
        // synchronous Apple Event doesn't reenter the SwiftUI update.
        DispatchQueue.main.async { DockController.shared.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.refresh()
            self.updateFullScreenVisibility()
            // Re-read the macOS Dock auto-hide state every ~5s so the toggle
            // reflects changes made elsewhere (e.g. System Settings).
            self.tick &+= 1
            if self.tick % 5 == 0 { DockController.shared.refresh() }
        }
    }

    @objc private func workspaceChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.model.refresh()
            self?.updateFullScreenVisibility()
        }
    }

    /// Step aside while the focused app is full screen (e.g. Citrix Viewer),
    /// like the Windows taskbar does; come back as soon as focus moves on.
    private func updateFullScreenVisibility() {
        let fullScreen = frontWindowCoversScreen()
        if fullScreen, panel.isVisible {
            panel.orderOut(nil)
        } else if !fullScreen, !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// True when a visible normal window of the frontmost app covers the whole
    /// screen, menu bar included. Catches native full-screen Spaces and apps
    /// that go full screen with a borderless window; a merely zoomed window
    /// stops below the menu bar, so it does not count.
    private func frontWindowCoversScreen() -> Bool {
        guard let screen = NSScreen.main,
              let primary = NSScreen.screens.first,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // CG window bounds are top-left based, measured from the primary screen.
        let target = CGRect(x: screen.frame.minX,
                            y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width,
                            height: screen.frame.height)
        // Any of the app's visible windows, not just the front one: Citrix
        // Viewer floats a full-width 30pt toolbar strip in front of its
        // full-screen session window.
        return windows.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return false }
            return bounds.contains(target)
        }
    }

    @objc private func appActivated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let path = app.bundleURL?.path {
            Task { @MainActor in AppUsageStore.shared.record(path: path) }
        }
        workspaceChanged()
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
