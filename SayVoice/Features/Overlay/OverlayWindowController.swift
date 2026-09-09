import AppKit
import SwiftUI

/// Floating, non-activating panel that hosts the overlay. Positioning and
/// focus rules were tuned on 2026-09-08 and are kept exactly:
/// fixed panel size restored on every show, centred on the screen under the
/// pointer, never key, mouse-transparent unless the content has controls.
@MainActor
final class OverlayWindowController: NSWindowController {
    let model = OverlayModel()
    private var dismissTask: Task<Void, Never>?
    /// Incremented on every show — a stale dismiss completion must not hide
    /// a panel that was shown again meanwhile.
    private var showGeneration = 0

    /// Fixed panel size. The content is centred inside; the margin exists so
    /// the glass shadow is not clipped by the window edge.
    static let panelSize = NSSize(width: 640, height: 280)

    init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        // Never take focus: .nonactivatingPanel keeps the app inactive on click,
        // becomesKeyOnlyIfNeeded keeps the panel non-key for plain buttons.
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        // Mouse-transparent by default: the panel floats over other apps and
        // must not swallow clicks. Enabled only for states with controls.
        panel.ignoresMouseEvents = true

        super.init(window: panel)

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        positionPanel()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func showRecording(isToggleMode: Bool = false, hotkeyName: String = "", onStop: (@MainActor () -> Void)? = nil) {
        cancelDismiss()
        model.displayState = .recording
        model.isToggleMode = isToggleMode
        model.hotkeyName = hotkeyName
        model.onStop = onStop
        model.resetLevels()
        model.recordingStart = Date()
        window?.ignoresMouseEvents = !isToggleMode   // Stop button needs clicks
        showPanel()
    }

    func showTranscribing() {
        cancelDismiss()
        model.displayState = .transcribing
        model.resetLevels()
        window?.ignoresMouseEvents = true
        showPanel()
    }

    func showResult(
        text: String,
        durationSeconds: Double,
        onCopy: (@MainActor () -> Void)?,
        onShowAll: (@MainActor () -> Void)?
    ) {
        cancelDismiss()
        model.displayState = .result
        model.message = text
        model.durationSeconds = durationSeconds
        model.onCopy = onCopy
        model.onShowAll = onShowAll
        window?.ignoresMouseEvents = false          // Copy / Show all + hover
        showPanel()
    }

    func showError(message: String, action: (title: String, handler: @MainActor () -> Void)? = nil) {
        cancelDismiss()
        model.displayState = .error
        model.message = message
        model.errorAction = action
        window?.ignoresMouseEvents = action == nil
        showPanel()
    }

    func updateAudioLevel(_ level: Float) {
        model.appendLevel(level)
    }

    /// Hides the panel after `delay`. While the pointer is over the panel the
    /// countdown pauses, so the user can read a long result or click Copy.
    func dismiss(after delay: TimeInterval = 0) {
        cancelDismiss()
        guard delay > 0 else { animateDismiss(); return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Bounded pause: a pointer left resting on the panel — or a hover
            // state that never clears — must not keep it up forever.
            let deadline = ContinuousClock.now + .seconds(10)
            while let self, self.model.isHovered, !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            self?.animateDismiss()
        }
    }

    // MARK: - Private

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    private func showPanel() {
        showGeneration += 1
        positionPanel()
        guard window?.isVisible != true else {
            window?.animator().alphaValue = 1.0     // may be mid fade-out
            return
        }
        window?.alphaValue = 0
        window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 1.0
        }
    }

    private func animateDismiss() {
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            self.window?.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.showGeneration == generation else { return }
                self.window?.orderOut(nil)
                self.window?.ignoresMouseEvents = true
                self.model.isHovered = false
                // Empty the view tree: a hidden panel with live animations
                // keeps rendering at 60 fps.
                self.model.displayState = .hidden
            }
        }
    }

    /// Screen the user is working on. `NSScreen.main` is unreliable for a
    /// background app with several displays; the pointer position is a
    /// dependable signal — people dictate where the caret and the mouse are.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func positionPanel() {
        guard let window, let screen = targetScreen() else { return }
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        // Size comes from the constant, never from window.frame: in .hidden the
        // view tree is empty and the window can collapse; centring on that
        // size pushed the panel right by half its width.
        let size = Self.panelSize

        // X on the physical screen centre (visibleFrame shifts with a side Dock),
        // Y in the visible frame so the panel never sits under the Dock:
        // lower third, above chat input fields.
        var origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.22
        )
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))

        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
