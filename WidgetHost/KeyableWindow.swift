import AppKit

/// NSWindow subclass that can always become the key window.
/// Required because .borderless NSWindow returns canBecomeKey = false by default,
/// which silently prevents makeKeyAndOrderFront from working and breaks text input.
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
