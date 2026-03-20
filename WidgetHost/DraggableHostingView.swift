import AppKit
import SwiftUI

// Used as the content window's contentView.
// Provides resize cursors; isMovableByWindowBackground=false on the window
// means AppKit never intercepts clicks for dragging, so all SwiftUI events work.
class DraggableHostingView<Content: View>: NSHostingView<Content> {

    private let edgeSize: CGFloat = 8

    override func resetCursorRects() {
        super.resetCursorRects()
        let b = bounds
        let e = edgeSize

        addCursorRect(NSRect(x: e,        y: b.maxY - e, width: b.width - 2*e, height: e), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: e,        y: 0,          width: b.width - 2*e, height: e), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0,        y: e,          width: e, height: b.height - 2*e), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.maxX-e, y: e,          width: e, height: b.height - 2*e), cursor: .resizeLeftRight)

        addCursorRect(NSRect(x: 0,        y: b.maxY-e, width: e, height: e), cursor: .crosshair)
        addCursorRect(NSRect(x: b.maxX-e, y: b.maxY-e, width: e, height: e), cursor: .crosshair)
        addCursorRect(NSRect(x: 0,        y: 0,        width: e, height: e), cursor: .crosshair)
        addCursorRect(NSRect(x: b.maxX-e, y: 0,        width: e, height: e), cursor: .crosshair)
    }
}
