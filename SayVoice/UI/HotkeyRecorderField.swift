import AppKit
import SwiftUI

/// Поле назначения хоткея: клик — «Нажмите клавишу» — нажатие сохраняется.
///
/// Ловим нажатия локальным монитором `NSEvent`: он работает, пока окно настроек
/// активно, и не требует ни отдельного event tap'а, ни прав доступности.
///
/// Модификатор-одиночка засчитывается **на отпускании**: иначе, зажав ⌥ ради ⌥⌘D,
/// пользователь получил бы хоткей «⌥» ещё до того, как дотянулся до D.
struct HotkeyRecorderField: View {
    @Binding var hotkey: Hotkey
    /// Вызывается при сохранении нового хоткея — координатор применяет его на лету.
    var onChange: ((Hotkey) -> Void)?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: String?

    /// Модификатор зажат, но клавиша ещё не нажата — ждём отпускания.
    @State private var pendingModifier: CGKeyCode?
    @State private var sawKeyDown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Хоткей записи")
                Spacer()

                Button(action: toggleRecording) {
                    Text(isRecording ? "Нажмите клавишу или кнопку мыши…" : hotkey.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        .frame(minWidth: 140)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(isRecording ? 0.03 : 0.07))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                                    lineWidth: isRecording ? 1.5 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Esc — отмена" : "Нажмите, чтобы назначить другую клавишу или кнопку мыши")

                if hotkey != .default && !isRecording {
                    Button("Сбросить") { save(.default) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }

            if let rejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else if let warning = hotkey.warning {
                Label(warning, systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    // MARK: - Запись

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        rejection = nil
        pendingModifier = nil
        sawKeyDown = false
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { event in
            handle(event)
            return nil   // события съедаются, пока идёт запись хоткея
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
            // Кнопки мыши, кроме левой и правой. Логи-утилиты вроде Options+ могут
            // перехватывать кнопку раньше системы — тогда сюда ничего не придёт,
            // и пользователь просто не увидит реакции.
            let button = event.buttonNumber
            if let rejected = Hotkey.validate(mouseButton: button) {
                rejection = rejected.message
                return
            }
            save(Hotkey(mouseButton: button))

        case .keyDown:
            sawKeyDown = true
            pendingModifier = nil
            // Esc без модификаторов — отмена.
            if code == 53, cgFlags == 0 {
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
                // Модификатор нажали и отпустили, ничего не нажав между — это он и есть.
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

    /// NSEvent отдаёт свои флаги — переводим в те же маски, с которыми работает
    /// слушатель на CGEvent.
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
