import Cocoa
import ApplicationServices

@MainActor
final class WindowSnapper {
    static let shared = WindowSnapper()
    
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }

        // Use a safe, read-only global monitor. We never block or swallow events.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.clickCount == 2 {
                self?.handleDoubleClick(event: event)
            }
        }
        
        // Also add a local monitor just in case they click our own windows (though MacTaskbar is a panel)
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.clickCount == 2 {
                self?.handleDoubleClick(event: event)
            }
            return event
        }
    }

    private func handleDoubleClick(event: NSEvent) {
        let loc = NSEvent.mouseLocation // Cocoa coordinates (bottom-left)
        guard let primary = NSScreen.screens.first else { return }
        
        let axLoc = CGPoint(x: loc.x, y: primary.frame.height - loc.y)
        let sys = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        let err = AXUIElementCopyElementAtPosition(sys, Float(axLoc.x), Float(axLoc.y), &element)
        guard err == .success, let el = element else { return }

        var roleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleVal)
        let role = (roleVal as? String) ?? ""

        if role == kAXWindowRole as String || role == kAXToolbarRole as String || role == kAXStaticTextRole as String {
            var windowElem: AXUIElement = el
            if role != kAXWindowRole as String {
                var current: AXUIElement? = el
                while let cur = current {
                    var r: CFTypeRef?
                    AXUIElementCopyAttributeValue(cur, kAXRoleAttribute as CFString, &r)
                    if (r as? String) == (kAXWindowRole as String) {
                        windowElem = cur
                        break
                    }
                    var p: CFTypeRef?
                    if AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &p) == .success, let parent = p {
                        // swiftlint:disable:next force_cast
                        current = (parent as! AXUIElement)
                    } else {
                        current = nil
                    }
                }
            }
            
            var subroleVal: CFTypeRef?
            AXUIElementCopyAttributeValue(windowElem, kAXSubroleAttribute as CFString, &subroleVal)
            if let sub = subroleVal as? String, sub != (kAXStandardWindowSubrole as String) {
                return
            }

            guard let screen = getScreen(for: loc) else { return }

            let taskbarReserve: CGFloat = 58
            let targetFrame = calculateMaximizedAXFrame(for: screen, reservingBottom: taskbarReserve)

            var position = targetFrame.origin
            var size = targetFrame.size

            // Wait a tiny fraction of a second to let the OS native zoom start/finish, then override it.
            // This prevents our frame set from being overwritten by the OS animation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let axPos = AXValueCreate(.cgPoint, &position),
                   let axSize = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(windowElem, kAXSizeAttribute as CFString, axSize)
                    AXUIElementSetAttributeValue(windowElem, kAXPositionAttribute as CFString, axPos)
                    AXUIElementSetAttributeValue(windowElem, kAXSizeAttribute as CFString, axSize)
                }
            }
        }
    }

    private func getScreen(for cocoaLoc: CGPoint) -> NSScreen? {
        return NSScreen.screens.first(where: { NSMouseInRect(cocoaLoc, $0.frame, false) })
    }

    private func calculateMaximizedAXFrame(for screen: NSScreen, reservingBottom: CGFloat) -> CGRect {
        let visible = screen.visibleFrame
        guard let primary = NSScreen.screens.first else { return .zero }
        
        let axY = primary.frame.height - visible.maxY
        let axHeight = visible.height - reservingBottom
        
        return CGRect(
            x: visible.minX,
            y: axY,
            width: visible.width,
            height: axHeight
        )
    }
}
