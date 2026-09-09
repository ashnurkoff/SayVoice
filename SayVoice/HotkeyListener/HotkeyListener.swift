import CoreGraphics
import ApplicationServices

@MainActor
final class HotkeyListener {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var coordinator: AppCoordinator?

    /// The current hotkey. The fields below duplicate it so the event tap
    /// callback can read them (the callback does not run on the MainActor).
    private(set) var hotkey: Hotkey = .default

    /// Read from the callback for the early filter.
    /// Written only from the MainActor; a torn read of these values is harmless.
    nonisolated(unsafe) fileprivate var keyCode: CGKeyCode = Hotkey.default.keyCode
    nonisolated(unsafe) fileprivate var requiredFlags: UInt64 = Hotkey.default.flags
    nonisolated(unsafe) fileprivate var isModifierOnly: Bool = true
    /// The mouse button number, or -1 when the hotkey is a keyboard one.
    nonisolated(unsafe) fileprivate var mouseButton: Int = -1
    /// Toggle mode: a press starts the recording and the next one stops it.
    nonisolated(unsafe) fileprivate var isToggle: Bool = false

    /// Our hotkey is held right now. Needed so that the release and the
    /// autorepeat are eaten only for our own press: without it the app ate the
    /// keyUp of every "D" typed without modifiers, and the key stopped printing
    /// system-wide.
    nonisolated(unsafe) fileprivate var hotkeyIsDown: Bool = false

    /// The modifiers taken into account when comparing. The other bits (the
    /// NumLock state, for one) are ignored.
    nonisolated fileprivate static let relevantFlags: UInt64 =
        CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]).rawValue

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Changes the trigger mode (hold / toggle).
    func apply(isToggle newValue: Bool) {
        isToggle = newValue
    }

    /// Changes the hotkey on the fly. When the kind of hotkey changes
    /// (modifier ↔ regular key) the tap is recreated: the two kinds run in
    /// different modes.
    func apply(_ new: Hotkey) {
        let modeChanged = new.requiresConsuming != hotkey.requiresConsuming
        hotkey = new
        keyCode = new.keyCode
        requiredFlags = new.flags
        isModifierOnly = new.isModifierOnly
        mouseButton = new.mouseButton ?? -1
        hotkeyIsDown = false

        if modeChanged, eventTap != nil {
            stop()
            try? start(prompt: false)
        }
        print("[SayVoice] Hotkey set to \(new.displayName) (consuming: \(new.requiresConsuming))")
    }

    /// Try to start the event tap.
    /// - Parameter prompt: if `true`, shows the macOS system dialog when Accessibility is not granted.
    func start(prompt: Bool) throws {
        // Already running — skip
        if eventTap != nil { return }

        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        guard granted else {
            throw HotkeyError.accessibilityNotGranted
        }

        // Mouse buttons other than left and right arrive as
        // otherMouseDown/Up with the number in mouseEventButtonNumber.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // The mode depends on the kind of hotkey.
        //
        // .listenOnly observes only: the app does not sit in the synchronous
        // path of keyboard delivery, so there is no input latency and the
        // system does not disable the tap on a timeout. That is enough for a
        // lone modifier, which prints nothing by itself.
        //
        // .defaultTap is needed for a regular key: its events have to be eaten,
        // or the key would both start the recording and type itself (or fire as
        // somebody else's shortcut). Strictly our own hotkey is eaten —
        // everything else passes through untouched.
        let tapOptions: CGEventTapOptions = hotkey.requiresConsuming ? .defaultTap : .listenOnly

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: userInfo
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[SayVoice] Event tap created (\(hotkey.requiresConsuming ? "defaultTap" : "listenOnly")) for \(hotkey.displayName)")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// A mouse button press and release.
    func handleMouse(type: CGEventType, button: Int) {
        guard button == mouseButton else { return }
        switch type {
        case .otherMouseDown: press()
        case .otherMouseUp:   release()
        default:              break
        }
    }

    /// A hotkey press. In toggle mode the release is ignored and the press
    /// alternately starts and stops the recording.
    private func press() {
        if isToggle {
            coordinator?.handleHotkeyToggle()
        } else {
            coordinator?.handleKeyDown()
        }
    }

    private func release() {
        guard !isToggle else { return }
        coordinator?.handleKeyUp()
    }

    func handleEvent(type: CGEventType, code: CGKeyCode, flags: CGEventFlags) {
        guard code == keyCode else { return }

        if isModifierOnly {
            guard type == .flagsChanged else { return }
            // The modifier mask appeared — the key is down; it disappeared — the key is up.
            if flags.rawValue & requiredFlags != 0 {
                press()
            } else {
                release()
            }
            return
        }

        switch type {
        case .keyDown: press()
        case .keyUp:   release()
        default:       break
        }
    }
}

// MARK: - Decision for an event

/// What to do with a keyboard event.
///
/// Deliberately pulled out as a pure function: this is exactly where the bug
/// lived that made the app eat the release of the same letter typed normally,
/// so the key stopped printing system-wide. Logic like this needs a test, not
/// an eyeball inside a callback.
struct HotkeyEventDecision: Equatable {
    /// The event has to be eaten (not passed on to the system).
    let consume: Bool
    /// The event belongs to our hotkey — tell the coordinator.
    let handle: Bool
    /// The new value of "our hotkey is held".
    let isDown: Bool

    static func decide(
        isKeyDown: Bool,
        isAutorepeat: Bool,
        flags: UInt64,
        required: UInt64,
        wasDown: Bool
    ) -> HotkeyEventDecision {
        if isKeyDown {
            if isAutorepeat {
                // Eat a repeat of our own held hotkey; let anybody else's through.
                return .init(consume: wasDown, handle: false, isDown: wasDown)
            }
            let relevant = HotkeyListener.relevantFlags
            let matches = (flags & relevant) == (required & relevant)
            // The same key without the required modifiers is ordinary typing.
            guard matches else { return .init(consume: false, handle: false, isDown: wasDown) }
            return .init(consume: true, handle: true, isDown: true)
        }

        // A release: the modifiers may already be up, so the check is not
        // against them but against whether the press was ours.
        guard wasDown else { return .init(consume: false, handle: false, isDown: false) }
        return .init(consume: true, handle: true, isDown: false)
    }
}

// MARK: - Event tap callback

/// The modifier match is strict: ⌥⌘D must not fire on ⌥⌘⇧D.
private func flagsMatch(_ flags: CGEventFlags, required: UInt64) -> Bool {
    let relevant = HotkeyListener.relevantFlags
    return (flags.rawValue & relevant) == (required & relevant)
}

private let hotkeyEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passRetained(event) }

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            guard let tap = listener.eventTap else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[SayVoice] Re-enabled event tap after system disable")
        }
        return Unmanaged.passRetained(event)
    }

    let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()

    // A hotkey on a mouse button: our button is eaten, or "Back" would keep
    // paging through the history during a dictation. Other buttons are left alone.
    if type == .otherMouseDown || type == .otherMouseUp {
        guard listener.mouseButton >= 0 else { return Unmanaged.passRetained(event) }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard button == listener.mouseButton else { return Unmanaged.passRetained(event) }
        Task { @MainActor in
            listener.handleMouse(type: type, button: button)
        }
        return nil
    }

    guard listener.mouseButton < 0 else { return Unmanaged.passRetained(event) }
    let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    // The early filter: no Task is spawned for every keypress in the system —
    // only for the events of our hotkey.
    guard code == listener.keyCode else { return Unmanaged.passRetained(event) }

    let flags = event.flags

    if listener.isModifierOnly {
        // A modifier is never eaten: an eaten ⌥ would break typing system-wide.
        Task { @MainActor in
            listener.handleEvent(type: type, code: code, flags: flags)
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown || type == .keyUp else { return Unmanaged.passRetained(event) }

    let decision = HotkeyEventDecision.decide(
        isKeyDown: type == .keyDown,
        isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        flags: flags.rawValue,
        required: listener.requiredFlags,
        wasDown: listener.hotkeyIsDown
    )
    listener.hotkeyIsDown = decision.isDown

    if decision.handle {
        Task { @MainActor in
            listener.handleEvent(type: type, code: code, flags: flags)
        }
    }
    // An eaten event neither types itself nor fires as a shortcut of the active application.
    return decision.consume ? nil : Unmanaged.passRetained(event)
}
