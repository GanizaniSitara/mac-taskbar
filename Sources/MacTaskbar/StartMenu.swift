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

/// Borderless panel that CAN become key, so the search field receives typing
/// and the key monitor can drive arrow/enter/escape navigation. A plain
/// borderless NSPanel never becomes key, which is why keys did nothing before.
final class StartMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class StartMenuController {
    static let shared = StartMenuController()
    private var window: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var model: StartMenuModel?
    private var previousApp: NSRunningApplication?

    func toggle(relativeTo anchor: NSWindow?) {
        if let w = window, w.isVisible {
            hide()
            return
        }
        show(anchor: anchor)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        model = nil
        for m in [globalMonitor, localMonitor, keyMonitor] {
            if let m { NSEvent.removeMonitor(m) }
        }
        globalMonitor = nil; localMonitor = nil; keyMonitor = nil
    }

    /// Dismiss and hand keyboard focus back to whatever app was frontmost when
    /// the menu opened (used for Escape — a launch lets the new app take over).
    private func hideAndRestore() {
        let prev = previousApp
        hide()
        guard let prev, prev.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if #available(macOS 14.0, *) {
            prev.activate()
        } else {
            prev.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func launch(_ app: AppEntry) {
        AppUsageStore.shared.record(path: app.id)
        NSWorkspace.shared.open(URL(fileURLWithPath: app.id))
        hide()
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

    private func installKeyMonitor() {
        // Consume navigation keys; let everything else (typing) reach the
        // focused search field. Codes: 125 down, 126 up, 36/76 return, 53 esc.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let code = Int(event.keyCode)
            switch code {
            case 125, 126, 36, 76, 53:       // up / down / enter / escape
                Task { @MainActor in self.handleNavKey(code) }
                return nil
            case 123, 124:                   // left / right
                // Only hijack for pane switching when not typing a search, so
                // they still move the cursor inside the search field.
                if self.model?.searching == false {
                    Task { @MainActor in self.handleNavKey(code) }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func handleNavKey(_ code: Int) {
        guard let model else { return }
        switch code {
        case 125: model.navigateDown()                                             // down
        case 126: model.navigateUp()                                               // up
        case 123: if !model.searching { model.focusedPane = .categories }          // left → category rail
        case 124: model.focusedPane = .apps                                        // right → apps
        case 36, 76:                                                               // return / enter
            if model.focusedPane == .categories { model.focusedPane = .apps }
            else if let app = model.selectedApp { launch(app) }
        case 53: hideAndRestore()                                                  // escape
        default: break
        }
    }

    private func show(anchor: NSWindow?) {
        let apps = AppScanner.scan()
        let model = StartMenuModel(apps: apps)
        self.model = model
        let view = StartMenuView(model: model) { [weak self] app in
            self?.launch(app)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 480)

        let panel = StartMenuPanel(
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

        // Remember who had focus so Escape can return it, then become active so
        // the panel can be key and actually receive keystrokes.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
        installDismissMonitors()
        installKeyMonitor()
    }
}

/// Which pane keyboard navigation is currently driving. The layout top-to-
/// bottom is: category rail / app list, then the search field — so Down walks
/// apps → search, and Up walks search → apps.
enum StartPane { case apps, categories, search }

@MainActor
final class StartMenuModel: ObservableObject {
    @Published var query: String = "" {
        didSet {
            selectionIndex = 0
            searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
            if focusedPane == .categories { focusedPane = .apps }
        }
    }
    @Published var selectedCategory: AppCategory = .installed { didSet { selectionIndex = 0 } }
    @Published var selectionIndex: Int = 0
    @Published private(set) var searching: Bool = false
    @Published var focusedPane: StartPane = .apps

    let allApps: [AppEntry]
    let byCategory: [AppCategory: [AppEntry]]

    init(apps: [AppEntry]) {
        self.allApps = apps
        self.byCategory = Dictionary(grouping: apps, by: { $0.category })
        // Start on the first category that actually has apps.
        if (byCategory[selectedCategory]?.isEmpty ?? true),
           let firstNonEmpty = AppCategory.allCases.first(where: { !(byCategory[$0]?.isEmpty ?? true) }) {
            selectedCategory = firstNonEmpty
        }
    }

    var isSearching: Bool { searching }

    var filtered: [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allApps }
        return allApps.filter { $0.name.lowercased().contains(q) }
    }

    var currentApps: [AppEntry] {
        isSearching ? filtered : (byCategory[selectedCategory] ?? [])
    }

    var selectedApp: AppEntry? {
        let apps = currentApps
        guard apps.indices.contains(selectionIndex) else { return nil }
        return apps[selectionIndex]
    }

    /// Non-empty categories in display order — what arrow nav walks through.
    var visibleCategories: [AppCategory] {
        AppCategory.allCases.filter { !(byCategory[$0]?.isEmpty ?? true) }
    }

    /// Down arrow: advance within the focused pane, falling through to the
    /// search field once we reach the bottom of the app/category list.
    func navigateDown() {
        switch focusedPane {
        case .categories:
            let cats = visibleCategories
            if let i = cats.firstIndex(of: selectedCategory), i < cats.count - 1 {
                selectedCategory = cats[i + 1]
            } else {
                focusedPane = .search
            }
        case .apps:
            if selectionIndex < currentApps.count - 1 {
                selectionIndex += 1
            } else {
                focusedPane = .search
            }
        case .search:
            break   // already at the bottom
        }
    }

    /// Up arrow: reverse of navigateDown — from the search field back up into
    /// the app list.
    func navigateUp() {
        switch focusedPane {
        case .categories:
            let cats = visibleCategories
            if let i = cats.firstIndex(of: selectedCategory), i > 0 {
                selectedCategory = cats[i - 1]
            }
        case .apps:
            if selectionIndex > 0 { selectionIndex -= 1 }
        case .search:
            focusedPane = .apps
        }
    }
}

struct StartMenuView: View {
    @ObservedObject var model: StartMenuModel
    let onLaunch: (AppEntry) -> Void
    @FocusState private var searchFocused: Bool

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

                // Right pane — apps in selected category (or search results),
                // ranked by frequency of use.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(model.currentApps.enumerated()), id: \.element.id) { idx, app in
                                AppRow(app: app,
                                       isSelected: idx == model.selectionIndex,
                                       selectionFocused: model.focusedPane == .apps,
                                       onLaunch: onLaunch)
                                    .id(app.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: model.selectionIndex) { _ in scrollToSelection(proxy) }
                    .onChange(of: model.selectedCategory) { _ in scrollToSelection(proxy) }
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
                    .focused($searchFocused)
                    .onSubmit { if let app = model.selectedApp { onLaunch(app) } }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(model.focusedPane == .search
                        ? Color.accentColor.opacity(0.30)
                        : Color.black.opacity(0.30))
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08)))
        .onAppear { searchFocused = true }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let apps = model.currentApps
        guard apps.indices.contains(model.selectionIndex) else { return }
        // No anchor → scroll the minimal amount to reveal the row, so arrow nav
        // only moves the list when the selection reaches an edge (not a jump to
        // centre on every keypress).
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(apps[model.selectionIndex].id)
        }
    }

    @ViewBuilder
    private func categoryRow(cat: AppCategory, count: Int) -> some View {
        let isActive = !model.isSearching && model.selectedCategory == cat
        let isFocused = isActive && model.focusedPane == .categories
        Button {
            model.selectedCategory = cat
            model.focusedPane = .categories
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
                Rectangle().fill(isFocused
                    ? Color.accentColor.opacity(0.35)
                    : Color.white.opacity(isActive ? 0.14 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

private struct AppRow: View {
    let app: AppEntry
    let isSelected: Bool
    let selectionFocused: Bool
    let onLaunch: (AppEntry) -> Void
    @State private var hover = false

    var body: some View {
        Button {
            onLaunch(app)
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
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Visual hover highlight ONLY — must not touch the keyboard selection or
        // scroll, or hovering re-enters the scroll-to-selection feedback loop.
        .onHover { hover = $0 }
    }

    private var rowBackground: Color {
        // Dimmer accent when focus has moved to the category rail, so it's clear
        // which pane the arrows are driving.
        if isSelected { return Color.accentColor.opacity(selectionFocused ? 0.35 : 0.16) }
        if hover { return Color.white.opacity(0.10) }
        return .clear
    }
}

enum AppScanner {
    @MainActor
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
        // Rank by frequency of use (desc), then alphabetically for ties and for
        // never-used apps. Grouping into categories preserves this order.
        return entries.sorted { a, b in
            let ca = AppUsageStore.shared.count(forPath: a.id)
            let cb = AppUsageStore.shared.count(forPath: b.id)
            if ca != cb { return ca > cb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
