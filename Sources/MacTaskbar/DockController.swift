import AppKit
import Combine

/// Controls the real macOS Dock's auto-hide setting so Apple's Dock can be kept
/// out of the way of the bottom taskbar (it otherwise slides up from the bottom
/// edge, overlapping the bar).
///
/// Reading the current state goes through CFPreferences — cheap, instant, and
/// needs no special permission. Writing goes through System Events so the Dock
/// animates immediately with no `killall Dock` restart flash; the first write
/// triggers a one-time Automation permission prompt for System Events.
final class DockController: ObservableObject {
    static let shared = DockController()

    /// True when the macOS Dock is set to auto-hide (i.e. kept out of the way).
    @Published private(set) var autoHidden: Bool = false

    private let dockDomain = "com.apple.dock" as CFString

    private init() {}

    /// Re-read the live Dock auto-hide state from preferences (no permission).
    func refresh() {
        CFPreferencesAppSynchronize(dockDomain)
        let on = (CFPreferencesCopyAppValue("autohide" as CFString, dockDomain) as? Bool) ?? false
        if on != autoHidden { autoHidden = on }
    }

    /// Flip the Dock's auto-hide setting.
    func toggle() {
        setAutoHide(!autoHidden)
    }

    func setAutoHide(_ on: Bool) {
        // Optimistically reflect the intent for instant button feedback…
        autoHidden = on

        var err: NSDictionary?
        let src = "tell application \"System Events\" to set autohide of dock preferences to \(on)"
        NSAppleScript(source: src)?.executeAndReturnError(&err)

        if err != nil {
            NSLog("DockController set autohide error: \(err!)")
            // Write failed (e.g. Automation permission not granted) — snap the
            // toggle back to the real value instead of lying about success.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.refresh()
            }
        }
        // On success, trust the optimistic value; the periodic poll reconciles
        // any later drift without racing the preferences flush.
    }
}
