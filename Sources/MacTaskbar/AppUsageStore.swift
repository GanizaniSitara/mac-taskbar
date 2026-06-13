import AppKit

/// Tracks how often each app is used so the Start menu can rank by frequency
/// instead of alphabetically. Two signals feed it: explicit launches from the
/// Start menu, and app activations observed app-wide (AppDelegate). Counts are
/// keyed by the app bundle path (same as `AppEntry.id`) and persisted in
/// UserDefaults so the ranking survives restarts.
@MainActor
final class AppUsageStore {
    static let shared = AppUsageStore()

    private let key = "appUsageCounts.v1"
    private var counts: [String: Int]

    private init() {
        counts = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    func count(forPath path: String) -> Int { counts[path] ?? 0 }

    func record(path: String) {
        counts[path, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: key)
    }
}
