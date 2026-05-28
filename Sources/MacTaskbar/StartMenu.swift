import AppKit
import SwiftUI

enum AppCategory: String, CaseIterable, Hashable {
    case installed = "Installed"
    case utilities = "Utilities"
    case macOS = "macOS"
    case user = "User"
}

struct AppEntry: Identifiable, Hashable {
    let id: String   // bundle path
    let name: String
    let icon: NSImage
    let category: AppCategory
}

@MainActor
final class StartMenuController {
    static let shared = StartMenuController()
    private var window: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func toggle(relativeTo anchor: NSWindow?) {
        if let w = window, w.isVisible {
            hide()
            return
        }
        show(anchor: anchor)
    }

    func hide() {
        window?.orderOut(nil)
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    private func installDismissMonitors() {
        // Clicks in other apps.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        // Clicks elsewhere in our own app (the taskbar panel, tray icons, etc).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let w = self.window else { return event }
            if event.window !== w { Task { @MainActor in self.hide() } }
            return event
        }
    }

    private func show(anchor: NSWindow?) {
        let apps = AppScanner.scan()
        let model = StartMenuModel(apps: apps)
        let view = StartMenuView(model: model) { [weak self] in
            self?.hide()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 480)

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
        installDismissMonitors()
    }
}

@MainActor
final class StartMenuModel: ObservableObject {
    @Published var query: String = ""
    let allApps: [AppEntry]
    let byCategory: [AppCategory: [AppEntry]]

    init(apps: [AppEntry]) {
        self.allApps = apps
        self.byCategory = Dictionary(grouping: apps, by: { $0.category })
    }

    var filtered: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allApps }
        return allApps.filter { $0.name.lowercased().contains(q) }
    }
}

struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    let onLaunch: () -> Void
    @State private var selected: AppCategory = .installed

    private var isSearching: Bool {
        !model.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left rail — category menu items.
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(AppCategory.allCases, id: \.self) { cat in
                        let count = model.byCategory[cat]?.count ?? 0
                        if count > 0 {
                            categoryRow(cat: cat, count: count)
                        }
                    }
                    Spacer()
                }
                .frame(width: 120)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.20))

                // Right pane — apps in selected category (or search results).
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(currentApps) { app in
                            appRow(app)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.5))
                    .font(.system(size: 11))
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.black.opacity(0.30))
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
    }

    private var currentApps: [AppEntry] {
        if isSearching { return model.filtered }
        return model.byCategory[selected] ?? []
    }

    @ViewBuilder
    private func categoryRow(cat: AppCategory, count: Int) -> some View {
        let isActive = !isSearching && selected == cat
        Button {
            selected = cat
        } label: {
            HStack(spacing: 6) {
                Text(cat.rawValue)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(.white)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(isActive ? 0.7 : 0.25))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Rectangle().fill(Color.white.opacity(isActive ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func appRow(_ app: AppEntry) -> some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: app.id))
            onLaunch()
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable().scaledToFit().frame(width: 22, height: 22)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(StartRowButtonStyle())
    }
}

private struct StartRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.20 : 0.0))
    }
}

enum AppScanner {
    static func scan() -> [AppEntry] {
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        let sources: [(root: String, category: AppCategory, recursive: Bool)] = [
            ("/Applications", .installed, true),
            ("/System/Applications", .macOS, false),
            ("/System/Applications/Utilities", .utilities, false),
            ("/Applications/Utilities", .utilities, false),
            (userApps, .user, true),
        ]
        let fm = FileManager.default
        var seen = Set<String>()
        var entries: [AppEntry] = []

        for src in sources {
            guard let items = try? fm.contentsOfDirectory(atPath: src.root) else { continue }
            for item in items {
                let path = (src.root as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    if seen.contains(item) { continue }
                    seen.insert(item)
                    let name = (item as NSString).deletingPathExtension
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 40, height: 40)
                    entries.append(AppEntry(id: path, name: name, icon: icon, category: src.category))
                } else if src.recursive,
                          let isDir = (try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType),
                          isDir == .typeDirectory {
                    // One level deep — catches things like /Applications/Microsoft\ Office/
                    if let nested = try? fm.contentsOfDirectory(atPath: path) {
                        for n in nested where n.hasSuffix(".app") {
                            if seen.contains(n) { continue }
                            seen.insert(n)
                            let npath = (path as NSString).appendingPathComponent(n)
                            let name = (n as NSString).deletingPathExtension
                            let icon = NSWorkspace.shared.icon(forFile: npath)
                            icon.size = NSSize(width: 40, height: 40)
                            entries.append(AppEntry(id: npath, name: name, icon: icon, category: src.category))
                        }
                    }
                }
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
