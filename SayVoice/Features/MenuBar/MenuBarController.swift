import AppKit
import SwiftUI

/// The status-bar item: a static state icon, a left-click history popover and
/// a right-click menu.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var menu: NSMenu?
    private let status: AppStatus

    // Callbacks
    var onShowSettings: (() -> Void)?
    var onShowAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onPopoverWillShow: (() -> Void)?

    /// History data — refreshed by AppCoordinator before the popover is built.
    var historyEntries: [TranscriptionEntry] = []
    /// Shown in the empty state, so the hint names the key the user actually has.
    var hotkeyName: String = ""

    init(status: AppStatus) {
        self.status = status
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        setupMenu()
        setupPopover()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(for: .idle, appearance: button.effectiveAppearance)

        // Receive both left and right mouse events
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick)
        button.target = self
    }

    private func setupMenu() {
        let m = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        m.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: "About SayVoice", action: #selector(handleAbout), keyEquivalent: "")
        aboutItem.target = self
        m.addItem(aboutItem)
        m.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit SayVoice", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        m.addItem(quitItem)
        self.menu = m
    }

    private func setupPopover() {
        // No contentSize: the hosting controller measures the popover, and a
        // fixed size only fights the view's own 320 pt frame.
        popover.behavior = .transient
    }

    // MARK: - Click Handling

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showHistory()
        }
    }

    /// Opens the history popover anchored to the status item. Also used by
    /// the overlay's "Show all" action.
    func showHistory() {
        guard let button = statusItem.button else { return }
        // Let the coordinator update historyEntries before we build the view
        onPopoverWillShow?()

        popover.contentViewController = NSHostingController(rootView: makeContent())
        // The app is LSUIElement, so it is never activated by a status-item
        // click on its own. Without this the search field gets no caret and
        // the clear confirmation cannot present. Scoped to the popover: the
        // coordinator restores the recording target app for text insertion.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshPopoverContent() {
        guard popover.isShown else { return }
        let controller = NSHostingController(rootView: makeContent())
        // A shown popover keeps the size it was opened with, so after Clear the
        // shorter list would sit in the old frame. Letting the hosting
        // controller publish its preferred size makes the popover follow.
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
    }

    private func makeContent() -> HistoryPopover {
        HistoryPopover(
            entries: historyEntries,
            status: status,
            hotkeyName: hotkeyName,
            onClear: { [weak self] in
                self?.onClearHistory?()
                self?.historyEntries = []
                // Rebuild on the next run-loop turn: swapping the hosting
                // controller while the confirmation dialog is still dismissing
                // pulls the view out from under it.
                Task { @MainActor in self?.refreshPopoverContent() }
            },
            onSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.onShowSettings?()
            }
        )
    }

    private func showMenu() {
        guard let button = statusItem.button, let menu else { return }
        // Temporarily assign the menu to the status item so it opens in place
        statusItem.menu = menu
        button.performClick(nil)
        // Remove it again so the next left-click goes through handleClick
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func handleSettings() {
        onShowSettings?()
    }

    @objc private func handleAbout() {
        onShowAbout?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }

    // MARK: - State Updates

    func setState(_ state: AppState) {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(for: state, appearance: button.effectiveAppearance)
    }
}
