import AppKit

class PanelManager: ObservableObject {
    @Published var isExpanded      = false
    @Published var timerRunning    = false
    @Published var expansionTrigger = 0   // incremented after window is key → TasksView focuses input

    weak var buttonPanel:   NSPanel?
    weak var contentWindow: NSWindow?

    private let circleSize = NSSize(width: 44,  height: 44)
    private let pillSize   = NSSize(width: 128, height: 44)

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        positionContentWindow()
        contentWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // One run-loop cycle after the window is key, SwiftUI can accept focus
        DispatchQueue.main.async { self.expansionTrigger += 1 }
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        contentWindow?.orderOut(nil)
    }

    func toggle() { isExpanded ? collapse() : expand() }

    // MARK: - Timer state

    func updateForTimer(running: Bool) {
        timerRunning = running
        animateButton(to: running ? pillSize : circleSize)
    }

    // MARK: - Persistence

    func saveButtonFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "buttonFrame_v2")
    }

    func savedButtonFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: "buttonFrame_v2") else { return nil }
        let r = NSRectFromString(s)
        return r.width > 0 ? r : nil
    }

    func saveContentSize(_ size: NSSize) {
        UserDefaults.standard.set(NSStringFromSize(size), forKey: "contentSize_v2")
    }

    func savedContentSize() -> NSSize? {
        guard let s = UserDefaults.standard.string(forKey: "contentSize_v2") else { return nil }
        let sz = NSSizeFromString(s)
        return sz.width > 0 ? sz : nil
    }

    // MARK: - Private

    private func positionContentWindow() {
        guard let bp = buttonPanel, let cw = contentWindow else { return }
        let bf = bp.frame
        let cs = cw.frame.size
        let screen = bp.screen ?? NSScreen.main
        let sf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Appear above the button, left-aligned, clamped to screen
        var x = bf.minX
        var y = bf.maxY + 8
        x = min(x, sf.maxX - cs.width)
        x = max(x, sf.minX)
        y = min(y, sf.maxY - cs.height)
        y = max(y, sf.minY)
        cw.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func animateButton(to size: NSSize) {
        guard let bp = buttonPanel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var frame = bp.frame
            frame.size = size
            bp.animator().setFrame(frame, display: true, animate: true)
        }
    }
}
