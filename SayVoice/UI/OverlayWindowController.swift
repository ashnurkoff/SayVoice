import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController: NSWindowController {
    let model = OverlayModel()
    private var dismissTask: Task<Void, Never>?
    /// Инкрементируется при каждом show* — completion устаревшего
    /// animateDismiss не должен прятать заново показанную панель.
    private var showGeneration = 0

    /// Фиксированный размер панели. Карточка центрируется внутри, а запас по краям
    /// нужен тени (radius 24 со смещением вниз на 10): край окна её обрезает, и тень
    /// остаётся видна только в вырезах у скруглённых углов.
    /// Размер задаётся здесь и принудительно восстанавливается при каждом показе —
    /// полагаться на текущий размер окна нельзя, см. positionPanel().
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
        // Панель не должна забирать фокус: иначе после клика по «Завершить» активным
        // окажется наше окно, и текст уедет не в то приложение. .nonactivatingPanel
        // не активирует приложение по клику, а becomesKeyOnlyIfNeeded не делает панель
        // ключевой ради кнопки — ключевой она стала бы только ради поля ввода.
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        // По умолчанию оверлей сквозной для мыши — он висит поверх чужих окон и не
        // должен перехватывать клики. Исключение делается только на время записи
        // в режиме переключателя, где в панели есть кнопка «Завершить».
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

    /// - Parameters:
    ///   - isToggleMode: запись не остановится сама — показываем кнопку и подсказку.
    ///   - hotkeyName: подпись хоткея для подсказки.
    ///   - onStop: остановка записи по кнопке в панели.
    func showRecording(
        isToggleMode: Bool = false,
        hotkeyName: String = "",
        onStop: (@MainActor () -> Void)? = nil
    ) {
        dismissTask?.cancel()
        dismissTask = nil
        model.displayState = .recording
        model.isToggleMode = isToggleMode
        model.hotkeyName = hotkeyName
        model.onStop = onStop
        model.resetLevels()
        model.recordingStart = Date()
        // Кликабельной панель делаем только там, где в ней есть кнопка.
        window?.ignoresMouseEvents = !isToggleMode
        showPanel()
    }

    func showTranscribing() {
        dismissTask?.cancel()
        dismissTask = nil
        model.displayState = .transcribing
        model.resetLevels()
        window?.ignoresMouseEvents = true   // кнопки здесь нет — снова пропускаем клики
        showPanel()
    }

    func showResult(text: String) {
        dismissTask?.cancel()
        dismissTask = nil
        model.displayState = .result
        model.message = text
        window?.ignoresMouseEvents = true
        showPanel()
    }

    func showError(message: String) {
        dismissTask?.cancel()
        dismissTask = nil
        model.displayState = .error
        model.message = message
        window?.ignoresMouseEvents = true
        showPanel()
    }

    func updateAudioLevel(_ level: Float) {
        // Каждое обновление попадает в историю — волна эквалайзера
        // скроллится равномерно и в тишине тоже (~12 Гц, только во время записи).
        model.appendLevel(level)
    }

    func dismiss(after delay: TimeInterval = 0) {
        dismissTask?.cancel()
        dismissTask = nil

        if delay > 0 {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.animateDismiss()
            }
        } else {
            animateDismiss()
        }
    }

    // MARK: - Private

    private func showPanel() {
        showGeneration += 1
        positionPanel()
        guard window?.isVisible != true else {
            // Панель могла быть в процессе fade-out — вернуть непрозрачность
            window?.animator().alphaValue = 1.0
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
                // Опустошаем дерево вью: спрятанная панель с "живым" контентом
                // (repeatForever, спрингы) продолжает рендериться на 60fps.
                self.model.displayState = .hidden
            }
        }
    }

    /// Экран, на котором пользователь сейчас работает.
    ///
    /// `NSScreen.main` — это «экран с клавиатурным фокусом», и для фонового приложения
    /// без собственных окон он ненадёжен: при нескольких дисплеях (включая виртуальные —
    /// зеркалирование, шеринг экрана в звонке, Sidecar) он может вернуть не тот экран,
    /// и панель уезжает с центра того дисплея, на который смотрит пользователь.
    /// Позиция курсора — надёжный признак: диктуют туда, где стоит каретка и мышь.
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
        // Размер берём из константы, а НЕ из window.frame: в состоянии .hidden дерево
        // вью пустое, окно схлопывается под содержимое (вплоть до нулевого), и если
        // центрировать по такому размеру — панель уезжает вправо ровно на половину
        // своей будущей ширины, а потом дорастает от точки постановки. Ставим размер
        // и позицию одним setFrame, поэтому текущий размер окна не важен.
        let windowSize = Self.panelSize

        // По X — центр ФИЗИЧЕСКОГО экрана, а не visibleFrame: у visibleFrame вырезан
        // Док, и при Доке слева/справа его середина съезжает в сторону (при левом Доке
        // панель уезжает вправо). Пользователь ждёт панель по центру экрана.
        // По Y — visibleFrame, чтобы не залезть под Док: нижняя треть (~22% высоты),
        // выше полей ввода в чатах.
        var origin = NSPoint(
            x: frame.midX - windowSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.22
        )

        // Страховка: панель не должна вылезать за пределы рабочей области экрана.
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - windowSize.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - windowSize.height))

        window.setFrame(NSRect(origin: origin, size: windowSize), display: false)
    }
}
