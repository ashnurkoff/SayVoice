import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private var animationTimer: Timer?
    private var animationFrame = 0
    private let popover = NSPopover()
    private var menu: NSMenu?

    // Callbacks
    var onShowSettings: (() -> Void)?
    var onDownloadModel: (() -> Void)?
    var onQuit: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onPopoverWillShow: (() -> Void)?

    // History data — updated by AppCoordinator before showing popover
    var historyEntries: [TranscriptionEntry] = []

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupButton()
        setupMenu()
        setupPopover()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.idleIcon()

        // Receive both left and right mouse events
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick)
        button.target = self
    }

    // MARK: - Icons

    /// Размер глифа: дефолтные ~13pt выглядят мельче соседних иконок меню-бара.
    private static let iconPointSize: CGFloat = 16

    /// Микрофон, template — система сама рисует его белым на тёмном меню-баре.
    private static func idleIcon() -> NSImage? {
        let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "SayVoice")?
            .withSymbolConfiguration(.init(pointSize: iconPointSize, weight: .regular))
        img?.isTemplate = true
        return img
    }

    /// Кадр анимации записи: белый микрофон + (мигающая) красная точка-индикатор.
    /// Не template: template-рендер монохромный и убил бы красный цвет точки.
    private static func recordingIcon(showDot: Bool) -> NSImage {
        let size = NSSize(width: 21, height: 21)
        let img = NSImage(size: size, flipped: false) { rect in
            // labelColor — динамический: белый на тёмном меню-баре, чёрный на светлом
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)
                .applying(.init(paletteColors: [.labelColor]))
            if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let micSize = mic.size
                let origin = NSPoint(
                    x: (rect.width - micSize.width) / 2,
                    y: (rect.height - micSize.height) / 2
                )
                mic.draw(in: NSRect(origin: origin, size: micSize))
            }
            if showDot {
                let d: CGFloat = 6.5
                let dotRect = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    /// Вспомогательные статусные иконки — всегда белые (template, без tint).
    private static func statusIcon(_ symbolName: String, description: String) -> NSImage? {
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: iconPointSize, weight: .regular))
        img?.isTemplate = true
        return img
    }

    private func setupMenu() {
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "SayVoice", action: nil, keyEquivalent: ""))
        m.addItem(.separator())
        let downloadItem = NSMenuItem(title: "Скачать модель...", action: #selector(handleDownloadModel), keyEquivalent: "")
        downloadItem.target = self
        m.addItem(downloadItem)
        m.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        m.addItem(settingsItem)
        m.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit SayVoice", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        m.addItem(quitItem)
        self.menu = m
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 400)
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
        // Let coordinator update historyEntries before we build the view
        onPopoverWillShow?()

        let view = HistoryPopoverView(
            entries: historyEntries,
            onClear: { [weak self] in
                self?.onClearHistory?()
                // Refresh popover with empty list
                self?.historyEntries = []
                self?.refreshPopoverContent()
            },
            onSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.onShowSettings?()
            }
        )

        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshPopoverContent() {
        guard popover.isShown else { return }
        let view = HistoryPopoverView(
            entries: historyEntries,
            onClear: { [weak self] in
                self?.onClearHistory?()
                self?.historyEntries = []
                self?.refreshPopoverContent()
            },
            onSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.onShowSettings?()
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func showMenu() {
        guard let button = statusItem.button, let menu else { return }
        // Temporarily assign menu to statusItem so it shows at the correct position
        statusItem.menu = menu
        button.performClick(nil)
        // Remove menu so next left-click goes through handleClick again
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func handleDownloadModel() {
        onDownloadModel?()
    }

    @objc private func handleSettings() {
        onShowSettings?()
    }

    @objc private func handleQuit() {
        onQuit?()
    }

    // MARK: - State Updates

    func setState(_ state: AppState) {
        guard let button = statusItem.button else { return }

        // Иконка всегда белая (адаптивная): цвет несёт только красная точка записи
        button.contentTintColor = nil

        switch state {
        case .idle:
            stopAnimation()
            button.image = Self.idleIcon()

        case .recording:
            startPulseAnimation(button: button)

        case .transcribing:
            stopAnimation()
            button.image = Self.statusIcon("ellipsis.circle", description: "Transcribing")

        case .injecting:
            stopAnimation()
            button.image = Self.statusIcon("checkmark.circle", description: "Done")

        case .error:
            stopAnimation()
            button.image = Self.statusIcon("exclamationmark.triangle", description: "Error")
        }
    }

    // MARK: - Animation

    private func startPulseAnimation(button: NSStatusBarButton) {
        // Белый микрофон постоянен, мигает только красная точка-индикатор
        let frames = [Self.recordingIcon(showDot: true), Self.recordingIcon(showDot: false)]
        animationFrame = 0
        button.image = frames[0]
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self, weak button] in
                guard let self, let button else { return }
                self.animationFrame = (self.animationFrame + 1) % frames.count
                button.image = frames[self.animationFrame]
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
    }
}
