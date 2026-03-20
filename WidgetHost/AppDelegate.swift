import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let panelManager = PanelManager()
    let appTracker   = AppTracker()
    let taskStore    = TaskStore()
    let clockStore   = ClockStore()

    private var buttonPanel:   NSPanel!
    private var contentWindow: KeyableWindow!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupButtonPanel()
        setupContentWindow()
        connectTracking()
    }

    // MARK: - Button Panel
    // Small floating circle/pill. nonactivatingPanel so it never steals focus.

    private func setupButtonPanel() {
        let origin: NSPoint
        if let saved = panelManager.savedButtonFrame() {
            origin = saved.origin
        } else {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            origin = NSPoint(x: screen.minX + 24, y: screen.minY + 40)
        }

        buttonPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: 44, height: 44)),
            styleMask:   [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        buttonPanel.level              = .floating
        buttonPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        buttonPanel.isOpaque           = false
        buttonPanel.backgroundColor    = .clear
        buttonPanel.hasShadow          = false
        buttonPanel.isMovableByWindowBackground = true
        buttonPanel.minSize            = NSSize(width: 44, height: 44)
        buttonPanel.delegate           = self

        panelManager.buttonPanel = buttonPanel

        let root = CollapsedButtonView(panelManager: panelManager, clockStore: clockStore)
            .colorScheme(.dark)
        buttonPanel.contentView = NSHostingView(rootView: root)
        buttonPanel.orderFrontRegardless()
    }

    // MARK: - Content Window
    // Normal NSWindow — activates properly, text input and buttons just work.

    private func setupContentWindow() {
        let size = panelManager.savedContentSize() ?? NSSize(width: 320, height: 510)

        contentWindow = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask:   [.borderless, .fullSizeContentView, .resizable],
            backing:     .buffered,
            defer:       false
        )
        contentWindow.level              = .floating
        contentWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentWindow.isOpaque           = false
        contentWindow.backgroundColor    = .clear
        contentWindow.hasShadow          = false
        // false = AppKit never intercepts clicks for dragging → all SwiftUI events work
        contentWindow.isMovableByWindowBackground = false
        contentWindow.minSize            = NSSize(width: 260, height: 300)
        contentWindow.maxSize            = NSSize(width: 800, height: 1000)
        contentWindow.delegate           = self

        panelManager.contentWindow = contentWindow

        let root = ExpandedContentView(
            panelManager: panelManager,
            clockStore:   clockStore,
            appTracker:   appTracker,
            taskStore:    taskStore
        )
        .colorScheme(.dark)
        contentWindow.contentView = DraggableHostingView(rootView: root)
        // Not shown yet — PanelManager.expand() positions and shows it
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        if (notification.object as? NSWindow) === contentWindow {
            panelManager.saveContentSize(contentWindow.frame.size)
        }
    }

    func windowDidMove(_ notification: Notification) {
        if (notification.object as? NSPanel) === buttonPanel {
            panelManager.saveButtonFrame(buttonPanel.frame)
        }
    }

    // MARK: - Clock → tracking

    private func connectTracking() {
        clockStore.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                running ? self?.appTracker.enableTracking()
                        : self?.appTracker.disableTracking()
                self?.panelManager.updateForTimer(running: running)
            }
            .store(in: &cancellables)
    }
}
