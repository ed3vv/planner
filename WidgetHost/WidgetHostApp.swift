import SwiftUI

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // All window management is done in AppDelegate.
        // Settings scene prevents SwiftUI from auto-creating a window.
        Settings { EmptyView() }
    }
}
