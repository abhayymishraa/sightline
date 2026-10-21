import AppKit
import ApplicationServices

/// A window (and optionally a split pane inside it) that can receive keyboard focus.
struct FocusCandidate {
    let pid: pid_t
    let window: AXUIElement
    let pane: AXUIElement?
    let frame: CGRect

    func same(as other: FocusCandidate?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && CFEqual(window, other.window) && optEqual(pane, other.pane)
    }
}

private func optEqual(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (a?, b?): CFEqual(a, b)
    default: false
    }
}

/// Moves keyboard focus with the Accessibility API. Never clicks outside terminals and code editors.
@MainActor
final class FocusMover {
    /// Apps whose split panes can be focused one by one.
    private static let splitPaneApps: Set<String> = [
        "com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.sublimetext.4", "com.apple.dt.Xcode",
        "com.google.android.studio",
    ]

    private var timer: Timer?
    private var windowPerScreen: [String: AXUIElement] = [:]      // per display UUID
    private var pointerPerScreen: [String: CGPoint] = [:]          // per display UUID
    private var awakenedApps: Set<pid_t> = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    var displays: [Display] = []

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Remembers, per display, where the pointer was and which window had focus, so returning to a screen restores both.
    private func sample() {
        guard AXIsProcessTrusted() else { return }
        let mouse = Self.mouseLocation
        if let d = displays.first(where: { $0.frame.contains(mouse) }) { pointerPerScreen[d.id] = mouse }
        if let w = frontWindow(), let f = Self.frame(w), let d = screen(containing: f) { windowPerScreen[d.id] = w }
        wakeAccessibilityTree()
    }

    /// Electron editors (VS Code, Cursor) build their accessibility tree only when asked.
    private func wakeAccessibilityTree() {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID,
              !awakenedApps.contains(app.processIdentifier), hasSplitPanes(app) else { return }
        awakenedApps.insert(app.processIdentifier)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: Switching screens

    /// Gives focus to `display`: the window under the gaze point if known, else the window last used there,
    /// else the frontmost window on it. Moves the pointer along only if it sits on another screen.
    func bringForward(_ display: Display, near gazePoint: CGPoint?) {
        var window: (pid: pid_t, element: AXUIElement, frame: CGRect)?
        if let focused = frontWindow(), let f = Self.frame(focused), self.screen(containing: f)?.id == display.id {
            window = nil  // focus is already there
        } else {
            let grown = display.frame.insetBy(dx: -0.08 * display.frame.width, dy: -0.08 * display.frame.height)
            if let gp = gazePoint, grown.contains(gp) {
                let p = CGPoint(x: min(max(gp.x, display.frame.minX + 1), display.frame.maxX - 1),
                                y: min(max(gp.y, display.frame.minY + 1), display.frame.maxY - 1))
                window = frontmostWindow { $0.contains(p) }
            }
            if window == nil, let remembered = windowPerScreen[display.id], let f = Self.frame(remembered),
               self.screen(containing: f)?.id == display.id, let pid = Self.pid(remembered) {
                window = (pid, remembered, f)
            }
            if window == nil { window = frontmostWindow { self.screen(containing: $0)?.id == display.id } }
            if let window {
                bringToFront(window.element, pid: window.pid)
                windowPerScreen[display.id] = window.element
            }
        }

        let mouse = Self.mouseLocation
        guard !display.frame.contains(mouse) else { return }
        let target = window.map { pointerDestination(in: $0.frame, display: display) }
            ?? pointerPerScreen[display.id].flatMap { display.frame.contains($0) ? $0 : nil }
            ?? CGPoint(x: display.frame.midX, y: display.frame.midY)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func pointerDestination(in windowFrame: CGRect, display: Display) -> CGPoint {
        if let p = pointerPerScreen[display.id], display.frame.contains(p), windowFrame.contains(p) { return p }
        let r = windowFrame.intersection(display.frame)
        return r.isNull ? CGPoint(x: display.frame.midX, y: display.frame.midY) : CGPoint(x: r.midX, y: r.midY)
    }

    // MARK: Within one screen

    /// The window, and pane in a terminal or editor, under `point`. Points near a window edge do not count.
    func candidate(at point: CGPoint) -> FocusCandidate? {
        guard let (pid, window, frame) = frontmostWindow({ $0.contains(point) }) else { return nil }
        let margin = min(min(frame.width, frame.height) * 0.1, 60)
        guard frame.insetBy(dx: margin, dy: margin).contains(point) else { return nil }

        var pane: AXUIElement?
        if let app = NSRunningApplication(processIdentifier: pid), hasSplitPanes(app) {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(point.x), Float(point.y), &hit) == .success {
                pane = Self.ancestors(of: hit!).first { el in
                    guard let f = Self.frame(el) else { return false }
                    let m = min(min(f.width, f.height) * 0.1, 60)
                    return f.width >= 320 && f.height >= 150 && f.width * f.height < 0.9 * frame.width * frame.height
                        && f.insetBy(dx: m, dy: m).contains(point)
                }
            }
        }
        return FocusCandidate(pid: pid, window: window, pane: pane, frame: frame)
    }

    func apply(_ t: FocusCandidate, clickToFocusPanes: Bool) {
        let focused = frontWindow()
        if focused == nil || !CFEqual(t.window, focused!) {
            // Only side-by-side windows switch; never raise a window that sits mostly behind the focused one.
            if let focused, let ff = Self.frame(focused) {
                let overlap = ff.intersection(t.frame)
                let smaller = min(ff.width * ff.height, t.frame.width * t.frame.height)
                if !overlap.isNull && overlap.width * overlap.height > 0.1 * smaller { return }
            }
            bringToFront(t.window, pid: t.pid)
        }
        if let d = screen(containing: t.frame) { windowPerScreen[d.id] = t.window }

        guard let pane = t.pane, !focusIsInside(pane, pid: t.pid) else { return }
        let element = Self.focusableText(in: pane) ?? pane
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard clickToFocusPanes else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.focusIsInside(pane, pid: t.pid), let f = Self.frame(pane) else { return }
            self.click(at: CGPoint(x: f.midX, y: f.midY))
        }
    }

    /// A real click for apps that ignore AXFocused on panes. The pointer goes back where it was.
    private func click(at p: CGPoint) {
        let old = Self.mouseLocation
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CGWarpMouseCursorPosition(old)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    // MARK: Helpers

    private func hasSplitPanes(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return Self.splitPaneApps.contains(id) || id.hasPrefix("com.jetbrains.")
    }

    func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        return Self.element(ax, kAXFocusedWindowAttribute) ?? Self.element(ax, kAXMainWindowAttribute)
    }

    private func bringToFront(_ window: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func focusIsInside(_ pane: AXUIElement, pid: pid_t) -> Bool {
        guard let focused = Self.element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute) else { return false }
        return Self.ancestors(of: focused).contains { CFEqual($0, pane) }
    }

    func screen(containing frame: CGRect) -> Display? {
        displays.max { a, b in
            let ia = a.frame.intersection(frame), ib = b.frame.intersection(frame)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }.flatMap { $0.frame.intersects(frame) ? $0 : nil }
    }

    /// Frontmost normal window (front-to-back window server order) matching `test`, resolved to its AX element.
    private func frontmostWindow(_ test: (CGRect) -> Bool) -> (pid: pid_t, element: AXUIElement, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.width > 80, bounds.height > 60,
                  test(bounds) else { continue }
            if let element = Self.accessibilityWindow(pid: pid, frame: bounds) { return (pid, element, bounds) }
        }
        return nil
    }

    private static func accessibilityWindow(pid: pid_t, frame bounds: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { w in
            guard let f = frame(w) else { return false }
            return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2
                && abs(f.width - bounds.width) < 2 && abs(f.height - bounds.height) < 2
        }
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(el, &pid) == .success ? pid : nil
    }

    private static func ancestors(of el: AXUIElement) -> [AXUIElement] {
        var out = [el]
        var current = el
        while out.count < 40, let parent = element(current, kAXParentAttribute) {
            out.append(parent)
            current = parent
        }
        return out
    }

    /// Breadth-first search for a text area that accepts focus (the terminal or editor buffer).
    private static func focusableText(in root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty && visited < 400 {
            let el = queue.removeFirst()
            visited += 1
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            if let role = role as? String, role == kAXTextAreaRole || role == kAXTextFieldRole {
                var settable = DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(el, kAXFocusedAttribute as CFString, &settable) == .success, settable.boolValue {
                    return el
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
               let kids = children as? [AXUIElement] { queue += kids }
        }
        return nil
    }

    static var mouseLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }
}
