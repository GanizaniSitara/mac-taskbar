import AppKit
import SwiftUI

struct AppEntry: Identifiable, Hashable {
    let id: String   // bundle path
    let name: String
    let icon: NSImage
}

@MainActor
final class StartMenuController {
    static let shared = StartMenuController()
    private var window: NSPanel?

    func toggle(relativeTo anchor: NSWindow?) {
        if let w = window, w.isVisible {
            w.orderOut(nil)
            return
        }
        show(anchor: anchor)
    }

    private func show(anchor: NSWindow?) {
        let apps = AppScanner.scan()
        let model = StartMenuModel(apps: apps)
        let view = StartMenuView(model: model) { [weak self] in
            self?.window?.orderOut(nil)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 520)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.frame.minX + 8,
                y: screen.frame.minY + 56 + 6
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        self.window = panel
    }
}

@MainActor
final class StartMenuModel: ObservableObject {
    @Published var query: String = ""
    let allApps: [AppEntry]

    init(apps: [AppEntry]) { self.allApps = apps }

    var filtered: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allApps }
        return allApps.filter { $0.name.lowercased().contains(q) }
    }
}

struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    let onLaunch: () -> Void
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search apps", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
            .padding(10)
            .background(Color.black.opacity(0.25))

            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(model.filtered) { app in
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: app.id))
                            onLaunch()
                        } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: app.icon)
                                    .resizable().scaledToFit().frame(width: 40, height: 40)
                                Text(app.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                                    .lineLimit(2).multilineTextAlignment(.center)
                                    .frame(height: 28)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08))
        )
    }
}

enum AppScanner {
    static func scan() -> [AppEntry] {
        let roots = [
            "/Applications",
            "/System/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]
        let fm = FileManager.default
        var seen = Set<String>()
        var entries: [AppEntry] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(item)
                if seen.contains(item) { continue }
                seen.insert(item)
                let name = (item as NSString).deletingPathExtension
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 40, height: 40)
                entries.append(AppEntry(id: path, name: name, icon: icon))
            }
            // Also descend one level into /System/Applications/Utilities.
            let utilities = (root as NSString).appendingPathComponent("Utilities")
            if let items = try? fm.contentsOfDirectory(atPath: utilities) {
                for item in items where item.hasSuffix(".app") {
                    let path = (utilities as NSString).appendingPathComponent(item)
                    if seen.contains(item) { continue }
                    seen.insert(item)
                    let name = (item as NSString).deletingPathExtension
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 40, height: 40)
                    entries.append(AppEntry(id: path, name: name, icon: icon))
                }
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
