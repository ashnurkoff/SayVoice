import AppKit
import Combine
import SwiftUI

/// Hotkey assignment field: click, press a key or a mouse button, done.
///
/// Uses a local `NSEvent` monitor, which works while the settings window is
/// active and needs neither an event tap nor accessibility rights. A lone
/// modifier counts on *release*, otherwise holding ⌥ on the way to ⌥⌘D would
/// register as "⌥".
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    /// Called with the new hotkey so the coordinator applies it live.
    var onChange: ((Hotkey) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: String?

    /// A modifier is held but no key has been pressed yet — waiting for release.
    @State private var pendingModifier: CGKeyCode?
    @State private var sawKeyDown = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: DS.Space.s8) {
                if hotkey != .default && !isRecording {
                    Button("Reset") { save(.default) }.buttonStyle(.dsLink)
                }
                Button(action: toggleRecording) {
                    Text(isRecording ? "Press a key or mouse button…" : hotkey.displayName)
                        .font(DS.font(.value))
                        .foregroundStyle(isRecording ? DS.Colors.accent.color : DS.Colors.text.color)
                        .frame(minWidth: 150)
                        .padding(.vertical, 6)
                        .padding(.horizontal, DS.Space.s12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.Colors.surface2.color))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                                .strokeBorder(isRecording ? DS.Colors.accent.color : DS.Colors.line.color, lineWidth: isRecording ? 1.5 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Esc cancels" : "Click to assign another key or mouse button")
            }

            if let rejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.font(.caption)).foregroundStyle(DS.Colors.warn.color)
                    .multilineTextAlignment(.trailing)
            } else if let warning = hotkey.warning {
                Label(warning, systemImage: "info.circle")
                    .font(DS.font(.caption)).foregroundStyle(DS.Colors.muted.color)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stopRecording)
        // A local monitor swallows keys, so it must never outlive the window:
        // onDisappear alone does not always fire when the window closes.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stopRecording() }
    }

    // MARK: - Recording

    private func toggleRecording() { isRecording ? stopRecording() : startRecording() }

    private func startRecording() {
        rejection = nil
        pendingModifier = nil
        sawKeyDown = false
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { event in
            handle(event)
            return nil   // swallowed while recording
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        pendingModifier = nil
        sawKeyDown = false
    }

    private func handle(_ event: NSEvent) {
        let code = CGKeyCode(event.keyCode)
        let cgFlags = Self.cgFlags(from: event.modifierFlags)

        switch event.type {
        case .otherMouseDown:
            // Mouse buttons other than left and right. Utilities such as Logi
            // Options+ can grab a button before the system does — then nothing
            // arrives here and the user simply sees no reaction.
            let button = event.buttonNumber
            if let rejected = Hotkey.validate(mouseButton: button) {
                rejection = rejected.message
                return
            }
            save(Hotkey(mouseButton: button))

        case .keyDown:
            sawKeyDown = true
            pendingModifier = nil
            if code == 53, cgFlags == 0 {   // Esc without modifiers cancels
                stopRecording()
                return
            }
            accept(keyCode: code, flags: cgFlags)

        case .flagsChanged:
            guard let modifier = Hotkey.modifierKeys[code] else { return }
            let isPressed = cgFlags & modifier.mask.rawValue != 0
            if isPressed {
                pendingModifier = code
                sawKeyDown = false
            } else if pendingModifier == code, !sawKeyDown {
                // Pressed and released with nothing in between — that is the hotkey.
                accept(keyCode: code, flags: modifier.mask.rawValue)
            }

        default:
            break
        }
    }

    private func accept(keyCode code: CGKeyCode, flags newFlags: UInt64) {
        if let rejected = Hotkey.validate(keyCode: code, flags: newFlags) {
            rejection = rejected.message
            return
        }
        save(Hotkey(keyCode: code, flags: newFlags))
    }

    private func save(_ new: Hotkey) {
        hotkey = new
        rejection = nil
        stopRecording()
        onChange?(new)
    }

    /// NSEvent flags → the CGEvent masks the listener compares against.
    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: CGEventFlags = []
        if flags.contains(.command)  { result.insert(.maskCommand) }
        if flags.contains(.option)   { result.insert(.maskAlternate) }
        if flags.contains(.control)  { result.insert(.maskControl) }
        if flags.contains(.shift)    { result.insert(.maskShift) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result.rawValue
    }
}
