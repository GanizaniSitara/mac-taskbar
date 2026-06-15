import AppKit
import ApplicationServices

// Private SPI used by yabai/Hammerspoon/etc. to map an AXUIElement window to
// its CGWindowID — gives us a stable per-window identity that doesn't depend
// on the AX windows-array index (which shuffles on focus changes).
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ outId: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowEntry: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let title: String
    let appName: String
    let bundleID: String?
    let minimized: Bool
    let axElement: AXUIElement?   // nil = no AX handle; raise by title or fall back to app activate

    static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.id == rhs.id && lhs.minimized == rhs.minimized
    }
}

enum WindowEnumerator {
    static func list() -> [WindowEntry] {
        let myPid = ProcessInfo.processInfo.processIdentifier

        // 1) On-screen windows via CGWindowList (works without AX permission).
        let cgWindowsByPid: [pid_t: [(id: CGWindowID, title: String)]] = collectCGWindows(myPid: myPid)

        var out: [WindowEntry] = []

        let hiddenRegularBundles: Set<String> = ["com.apple.finder"]

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            if app.processIdentifier == myPid { continue }
            if let b = app.bundleIdentifier, hiddenRegularBundles.contains(b) { continue }
            let appName = app.localizedName ?? ""
            let bundle = app.bundleIdentifier
            let pid = app.processIdentifier

            // 2) AX windows (works only with Accessibility permission). Gives us
            //    minimized state + an AXUIElement we can directly raise.
            var axSawAnyWindow = false
            var emittedCount = 0
            let appElem = AXUIElementCreateApplication(pid)
            var winsVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &winsVal) == .success,
               let windows = winsVal as? [AXUIElement] {
                axSawAnyWindow = !windows.isEmpty
                for win in windows {
                    var roleVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(win, kAXRoleAttribute as CFString, &roleVal) == .success,
                       let role = roleVal as? String, role != kAXWindowRole as String { continue }

                    var minVal: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minVal)
                    let minimized = (minVal as? Bool) ?? false

                    // Subrole — only show "standard" user-facing windows. Dialogs,
                    // floating palettes, system overlays, etc. have other subroles
                    // and shouldn't get a taskbar tile.
                    // EXCEPTION: a minimized window often reports a non-standard
                    // subrole (e.g. Terminal flips AXStandardWindow -> AXDialog
                    // while minimized). Don't subrole-filter minimized windows or
                    // they vanish from the bar and can't be restored.
                    if !minimized {
                        var subroleVal: CFTypeRef?
                        AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleVal)
                        if let sub = subroleVal as? String,
                           sub != (kAXStandardWindowSubrole as String) { continue }
                    }

                    var titleVal: CFTypeRef?
                    AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleVal)
                    let title = (titleVal as? String) ?? ""

                    // Tiny / zero-size windows are almost always background
                    // helpers — UNLESS they're minimized (Dock collapses them
                    // to near-zero AX size, which is exactly what we DO want
                    // to surface in the bar).
                    if !minimized {
                        var sizeVal: CFTypeRef?
                        if AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeVal) == .success,
                           let raw = sizeVal {
                            // swiftlint:disable:next force_cast
                            let axValue = raw as! AXValue
                            var size = CGSize.zero
                            if AXValueGetValue(axValue, .cgSize, &size),
                               size.width < 40 || size.height < 40 { continue }
                        }
                    }

                    let display = title.isEmpty ? appName : title

                    // Try for the stable CGWindowID; fall back to a (pid,title)
                    // composite if the private SPI is unavailable.
                    var wid: CGWindowID = 0
                    let stableID: String
                    if _AXUIElementGetWindow(win, &wid) == .success && wid != 0 {
                        stableID = "ax:\(wid)"
                    } else {
                        stableID = "ax:\(pid):\(display)"
                    }

                    out.append(WindowEntry(
                        id: stableID,
                        pid: pid, title: display, appName: appName,
                        bundleID: bundle, minimized: minimized, axElement: win
                    ))
                    emittedCount += 1
                }
            }

            // 3) CGWindowList fallback — only for apps where AX gave us nothing
            //    (no permission, app doesn't expose AX, etc.). If AX returned
            //    even one window, trust it exclusively to avoid double-emitting
            //    when AX/CG title strings differ slightly.
            if !axSawAnyWindow {
                for cg in cgWindowsByPid[pid] ?? [] {
                    let display = cg.title.isEmpty ? appName : cg.title
                    out.append(WindowEntry(
                        id: "cg:\(pid):\(cg.id):\(display)",
                        pid: pid, title: display, appName: appName,
                        bundleID: bundle, minimized: false, axElement: nil
                    ))
                    emittedCount += 1
                }
            }

            // 4) Running but windowless app — still show a tile (Dock-style).
            if emittedCount == 0 {
                out.append(WindowEntry(
                    id: "app:\(pid)", pid: pid, title: appName, appName: appName,
                    bundleID: bundle, minimized: false, axElement: nil
                ))
            }
        }
        return out
    }

    private static func collectCGWindows(myPid: pid_t) -> [pid_t: [(id: CGWindowID, title: String)]] {
        var byPid: [pid_t: [(id: CGWindowID, title: String)]] = [:]
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return byPid
        }
        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPid else { continue }
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w < 40 || h < 40 { continue }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            byPid[pid, default: []].append((id: wid, title: title))
        }
        return byPid
    }
}
