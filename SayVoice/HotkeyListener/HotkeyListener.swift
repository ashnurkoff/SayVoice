import CoreGraphics
import ApplicationServices

@MainActor
final class HotkeyListener {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private weak var coordinator: AppCoordinator?

    /// Текущий хоткей. Поля ниже дублируют его для чтения из колбэка event tap'а
    /// (колбэк вызывается не на MainActor).
    private(set) var hotkey: Hotkey = .default

    /// Читается из колбэка для раннего фильтра.
    /// Запись — только с MainActor; torn read этих значений не является проблемой.
    nonisolated(unsafe) fileprivate var keyCode: CGKeyCode = Hotkey.default.keyCode
    nonisolated(unsafe) fileprivate var requiredFlags: UInt64 = Hotkey.default.flags
    nonisolated(unsafe) fileprivate var isModifierOnly: Bool = true
    /// Номер кнопки мыши или -1, если хоткей клавиатурный.
    nonisolated(unsafe) fileprivate var mouseButton: Int = -1
    /// Режим переключателя: нажатие начинает запись, следующее — останавливает.
    nonisolated(unsafe) fileprivate var isToggle: Bool = false

    /// Наш хоткей сейчас зажат. Нужен, чтобы съедать отпускание и автоповтор только
    /// у своего нажатия: без этого приложение съедало keyUp у любой «D», набранной
    /// без модификаторов, и клавиша переставала печататься во всей системе.
    nonisolated(unsafe) fileprivate var hotkeyIsDown: Bool = false

    /// Модификаторы, которые учитываются при сравнении. Остальные биты
    /// (например, состояние NumLock) игнорируются.
    nonisolated fileprivate static let relevantFlags: UInt64 =
        CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]).rawValue

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Сменить хоткей на лету. Если меняется вид хоткея (модификатор ↔ обычная клавиша),
    /// tap пересоздаётся: у этих видов разные режимы работы.
    /// Сменить режим срабатывания (удержание / переключатель).
    func apply(isToggle newValue: Bool) {
        isToggle = newValue
    }

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

        // Кнопки мыши, кроме левой и правой, приходят как otherMouseDown/Up
        // с номером в поле mouseEventButtonNumber.
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // Режим зависит от вида хоткея.
        //
        // .listenOnly — только наблюдение: приложение не встаёт в синхронный путь
        // доставки клавиатуры, поэтому нет задержки ввода и система не отключает tap
        // по таймауту. Этого достаточно для модификатора-одиночки, который сам по себе
        // ничего не печатает.
        //
        // .defaultTap нужен для обычной клавиши: её события приходится съедать, иначе
        // клавиша и запустит запись, и напечатается (или сработает как чужой шорткат).
        // Съедается строго свой хоткей — всё остальное пропускается нетронутым.
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

    /// Нажатие и отпускание кнопки мыши.
    func handleMouse(type: CGEventType, button: Int) {
        guard button == mouseButton else { return }
        switch type {
        case .otherMouseDown: press()
        case .otherMouseUp:   release()
        default:              break
        }
    }

    /// Нажатие хоткея. В режиме переключателя отпускание игнорируется,
    /// а нажатие попеременно запускает и останавливает запись.
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
            // Маска модификатора появилась — клавиша нажата, исчезла — отпущена.
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

// MARK: - Решение по событию

/// Что сделать с клавиатурным событием.
///
/// Вынесено отдельной чистой функцией намеренно: именно здесь была ошибка, из-за
/// которой приложение съедало отпускание у обычного набора той же буквы, и клавиша
/// переставала печататься во всей системе. Такую логику нужно проверять тестом,
/// а не на глаз внутри колбэка.
struct HotkeyEventDecision: Equatable {
    /// Событие нужно съесть (не пропускать дальше в систему).
    let consume: Bool
    /// Событие относится к нашему хоткею — сообщить координатору.
    let handle: Bool
    /// Новое состояние «наш хоткей зажат».
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
                // Повтор своего зажатого хоткея съедаем, чужой пропускаем.
                return .init(consume: wasDown, handle: false, isDown: wasDown)
            }
            let relevant = HotkeyListener.relevantFlags
            let matches = (flags & relevant) == (required & relevant)
            // Та же клавиша без нужных модификаторов — обычный набор текста.
            guard matches else { return .init(consume: false, handle: false, isDown: wasDown) }
            return .init(consume: true, handle: true, isDown: true)
        }

        // Отпускание: модификаторы уже могут быть отпущены, поэтому сверяемся
        // не с ними, а с тем, было ли нажатие нашим.
        guard wasDown else { return .init(consume: false, handle: false, isDown: false) }
        return .init(consume: true, handle: true, isDown: false)
    }
}

// MARK: - Event tap callback

/// Совпадение модификаторов — строгое: ⌥⌘D не должен срабатывать на ⌥⌘⇧D.
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

    // Хоткей на кнопке мыши: свою кнопку съедаем, иначе «Назад» продолжит листать
    // страницы во время диктовки. Чужие кнопки не трогаем.
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

    // Ранний фильтр: не спауним Task на каждое системное нажатие клавиш —
    // только на события нашего хоткея.
    guard code == listener.keyCode else { return Unmanaged.passRetained(event) }

    let flags = event.flags

    if listener.isModifierOnly {
        // Модификатор никогда не съедаем: съеденный ⌥ сломал бы ввод во всей системе.
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
    // Съеденное событие не напечатается и не сработает как шорткат активного приложения.
    return decision.consume ? nil : Unmanaged.passRetained(event)
}
