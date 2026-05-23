import AppKit
import ApplicationServices

struct WindowEntry: Identifiable, Equatable {
    let id: String          // "pid:index:title"
    let pid: pid_t
    let title: String
    let appName: String
    let bundleID: String?
    let minimized: Bool
    let axElement: AXUIElement

    static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.minimized == rhs.minimized
    }
}

enum WindowEnumerator {
    static func list() -> [WindowEntry] {
        var out: [WindowEntry] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { continue }
            let appName = app.localizedName ?? ""
            let bundle = app.bundleIdentifier

            let pid = app.processIdentifier
            let appElem = AXUIElementCreateApplication(pid)

            var winsVal: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winsVal)
            guard err == .success, let windows = winsVal as? [AXUIElement] else { continue }

            for (idx, win) in windows.enumerated() {
                // Role must be window (skip sheets, drawers).
                var roleVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleVal) == .success,
                   let role = roleVal as? String, role != kAXWindowRole as String { continue }

                var titleVal: CFTypeRef?
                AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleVal)
                let title = (titleVal as? String) ?? ""

                var minVal: CFTypeRef?
                AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minVal)
                let minimized = (minVal as? Bool) ?? false

                let display = title.isEmpty ? appName : title
                let id = "\(pid):\(idx):\(display)"
                out.append(WindowEntry(
                    id: id, pid: pid, title: display, appName: appName,
                    bundleID: bundle, minimized: minimized, axElement: win
                ))
            }
        }
        return out
    }
}
