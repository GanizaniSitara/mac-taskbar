import AppKit

struct AgentApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let bundleID: String?
}

enum MenuBarAgents {
    static func list() -> [AgentApp] {
        let mine = ProcessInfo.processInfo.processIdentifier
        var out: [AgentApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .accessory else { continue }
            if app.processIdentifier == mine { continue }
            // Skip Apple system agents we don't want cluttering the bar.
            if let b = app.bundleIdentifier, isHiddenAgent(b) { continue }
            guard let name = app.localizedName, !name.isEmpty else { continue }
            out.append(AgentApp(
                id: app.processIdentifier,
                name: name,
                icon: app.icon,
                bundleID: app.bundleIdentifier
            ))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static let hiddenBundles: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.wallpaper.agent",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.WebKit.GPU",
        "com.apple.WebKit.Networking",
        "com.apple.WebKit.WebContent",
        "com.apple.universalaccessd",
    ]

    private static func isHiddenAgent(_ bundleID: String) -> Bool {
        if hiddenBundles.contains(bundleID) { return true }
        // Drop Apple background helpers that aren't user-facing agents.
        if bundleID.hasPrefix("com.apple.") {
            // Keep user-facing Apple menu-bar agents like Time Machine, AirPort, etc. — but
            // those are rare these days. Default Apple = hidden; user can adjust later.
            return true
        }
        return false
    }
}
