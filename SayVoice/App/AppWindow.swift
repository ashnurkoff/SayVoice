import AppKit
import SwiftUI

/// The one way the app creates a standard window. Fixed size unless asked,
/// centred, kept alive after close so it can be shown again.
enum AppWindow {
    @MainActor
    static func make(title: String, size: NSSize, resizable: Bool = false, content: some View) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.contentView?.frame = NSRect(origin: .zero, size: size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// Brings a window to the front and activates the app — menu-bar apps are
    /// not active when a window is requested from the status item.
    @MainActor
    static func present(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
