import AppKit

/// A single floating panel reused for all hover tooltips. Lives at popUpMenu
/// level so it draws above our own taskbar panel and any other app.
@MainActor
final class TooltipController {
    static let shared = TooltipController()
    private var panel: NSPanel?
    private var showTask: DispatchWorkItem?

    func show(text: String, near screenPoint: NSPoint, delay: TimeInterval = 0.15) {
        showTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.present(text: text, near: screenPoint)
        }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        panel?.orderOut(nil)
    }

    private func present(text: String, near screenPoint: NSPoint) {
        let font = NSFont.systemFont(ofSize: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding = NSEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        let contentSize = NSSize(
            width: ceil(textSize.width) + padding.left + padding.right,
            height: ceil(textSize.height) + padding.top + padding.bottom
        )

        let p = panel ?? makePanel()
        panel = p

        let container = p.contentView!
        container.subviews.forEach { $0.removeFromSuperview() }

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentSize))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.masksToBounds = true
        container.addSubview(effect)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.frame = NSRect(
            x: padding.left, y: padding.bottom,
            width: contentSize.width - padding.left - padding.right,
            height: contentSize.height - padding.top - padding.bottom
        )
        effect.addSubview(label)

        // Position above the icon (icon sits near screenPoint), centered horizontally.
        // Clamp to the main screen so it doesn't run off the edges.
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        var origin = NSPoint(
            x: screenPoint.x - contentSize.width / 2,
            y: screenPoint.y + 18
        )
        origin.x = max(screenFrame.minX + 4, min(origin.x, screenFrame.maxX - contentSize.width - 4))

        p.setFrame(NSRect(origin: origin, size: contentSize), display: true)
        p.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 24)))
        return p
    }
}
