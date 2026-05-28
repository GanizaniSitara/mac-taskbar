import AppKit
import ApplicationServices

enum AXBridge {
    static func ensurePermissionPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Activate the app, then try to raise a specific window by title via AX.
    /// Used when we have no direct AXUIElement (CG-only entries).
    static func raiseByTitle(pid: pid_t, title: String) {
        activate(pid: pid)
        guard let window = findWindow(pid: pid, title: title) else { return }
        raise(pid: pid, window: window)
    }

    static func activate(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Activate the app and raise the given AX window. Unminimizes if needed.
    static func raise(pid: pid_t, window: AXUIElement) {
        // 1) Unminimize first — must happen before raise/focus or the window
        //    is still in the Dock genie pocket.
        var minimizedVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedVal) == .success,
           let minimized = minimizedVal as? Bool, minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }

        // 2) Tell the app this is the focused/main window BEFORE activating the
        //    app, otherwise NSRunningApplication.activate() brings whichever
        //    window was previously frontmost (the Terminal-many-windows bug).
        let appElem = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        // 3) Now activate the app so it comes to the front.
        activate(pid: pid)
    }

    @discardableResult
    static func setMinimized(pid: pid_t, window: AXUIElement?, title: String, minimized: Bool) -> Bool {
        guard let target = window ?? findWindow(pid: pid, title: title) else { return false }
        let ok = AXUIElementSetAttributeValue(
            target,
            kAXMinimizedAttribute as CFString,
            minimized as CFTypeRef
        ) == .success
        if ok && !minimized {
            raise(pid: pid, window: target)
        }
        return ok
    }

    @discardableResult
    static func close(pid: pid_t, window: AXUIElement?, title: String) -> Bool {
        guard let target = window ?? findWindow(pid: pid, title: title) else { return false }
        var buttonVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            target,
            kAXCloseButtonAttribute as CFString,
            &buttonVal
        ) == .success,
              let rawButton = buttonVal else { return false }
        let closeButton = rawButton as! AXUIElement
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func quit(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }

    private static func findWindow(pid: pid_t, title: String) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        for window in windows {
            var titleVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleVal) == .success,
               let windowTitle = titleVal as? String,
               windowTitle == title {
                return window
            }
        }
        return nil
    }
}
