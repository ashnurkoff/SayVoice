# M4 — Инжект текста

**Цель:** Транскрибированный текст автоматически вставляется в активное текстовое поле. Двойная стратегия: AXUIElement (нативные приложения) и Pasteboard + Cmd+V (все остальные).

**Оценка:** 1-2 рабочих дня
**Зависимости:** M3 завершён (TranscriptionEngine возвращает String)
**Критерий готовности:** Матрица тестирования пройдена — текст вставляется в TextEdit, Safari, Chrome, Xcode

---

## Задачи

### 1. AXTextInjector.swift

```swift
// SayVoice/TextInjection/AXTextInjector.swift
import AppKit
import ApplicationServices

/// Инжект текста через Accessibility API.
/// Вставляет текст в позицию каретки или заменяет выделение.
final class AXTextInjector {

    /// Попытка инжекта через AX API.
    /// - Returns: true если успешно, false если нужен fallback
    func inject(text: String, targetPID: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(targetPID)
        return injectIntoApp(text: text, appElement: app)
    }

    private func injectIntoApp(text: String, appElement: AXUIElement) -> Bool {
        // Шаг 1: Получить сфокусированный элемент
        var focusedElementRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard result == .success, let focusedElement = focusedElementRef else {
            return false
        }

        let element = focusedElement as! AXUIElement

        // Шаг 2: Проверить, что это текстовое поле (не readonly)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        // Даже если AXValue не settable, AXSelectedText может быть доступен

        // Шаг 3: Попытаться вставить через AXSelectedText (предпочтительно — уважает позицию каретки)
        if injectViaSelectedText(text: text, element: element) {
            return true
        }

        // Шаг 4: Fallback — заменить весь AXValue (менее предпочтительно)
        if settable.boolValue {
            return injectViaFullValue(text: text, element: element)
        }

        return false
    }

    /// Вставляет текст в текущую позицию каретки, заменяя выделение если есть.
    private func injectViaSelectedText(text: String, element: AXUIElement) -> Bool {
        var isSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable)
        guard isSettable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }

    /// Добавляет текст к текущему значению поля (fallback для AXSelectedText).
    private func injectViaFullValue(text: String, element: AXUIElement) -> Bool {
        var currentValueRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValueRef)
        let existing = (currentValueRef as? String) ?? ""

        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            (existing + text) as CFString
        )
        return result == .success
    }
}
```

### 2. PasteboardInjector.swift

```swift
// SayVoice/TextInjection/PasteboardInjector.swift
import AppKit
import CoreGraphics

/// Инжект текста через буфер обмена + синтетический Cmd+V.
/// Работает в любом приложении, которое поддерживает Paste.
final class PasteboardInjector {

    private let kVKeyCode: CGKeyCode = 9   // virtual key code для 'v'

    func inject(text: String) {
        let pasteboard = NSPasteboard.general

        // Сохранить текущее содержимое буфера обмена
        let savedString = pasteboard.string(forType: .string)
        let savedTypes = pasteboard.types ?? []

        // Записать наш текст
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Небольшая задержка чтобы буфер успел обновиться
        Thread.sleep(forTimeInterval: 0.02)

        // Синтетический Cmd+V
        sendCmdV()

        // Восстановить буфер через 300ms (достаточно для завершения Paste)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let saved = savedString {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            } else if !savedTypes.isEmpty {
                // Буфер был не строковым — просто очищаем (не можем восстановить бинарные данные)
                // В production: сохранять NSPasteboardItem целиком
            }
        }
    }

    private func sendCmdV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: kVKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

> **Улучшение для production:** Для полного сохранения буфера обмена нужно сохранять все `NSPasteboardItem` объекты, включая бинарные данные (RTF, изображения). Базовая реализация сохраняет только строку.

### 3. TextInjector.swift

```swift
// SayVoice/TextInjection/TextInjector.swift
import AppKit

/// Единая точка входа для инжекта текста.
/// Стратегия: AX (нативные приложения) → Pasteboard (универсальный fallback).
@MainActor
final class TextInjector {
    private let axInjector = AXTextInjector()
    private let pasteboardInjector = PasteboardInjector()

    /// Вставить text в активное текстовое поле фронтального приложения.
    func inject(text: String) {
        guard !text.isEmpty else { return }

        // Добавляем пробел в конце для удобного продолжения набора
        let textWithSpace = text + " "

        let frontApp = NSWorkspace.shared.frontmostApplication
        let pid = frontApp?.processIdentifier ?? 0

        if pid > 0 {
            let axSuccess = axInjector.inject(text: textWithSpace, targetPID: pid_t(pid))
            if axSuccess {
                return  // AX сработал
            }
        }

        // Fallback: Pasteboard + Cmd+V
        pasteboardInjector.inject(text: textWithSpace)
    }
}
```

### 4. Подключение к AppCoordinator (обновление для M4)

```swift
// Добавить в AppCoordinator:
private let textInjector = TextInjector()

// Обновить handleKeyUp() — добавить инжект после транскрипции:
func handleKeyUp() {
    guard state == .recording else { return }
    state = .transcribing

    Task {
        let samples = await audioRecorder.stopCapture()

        do {
            let text = try await transcriptionEngine.transcribe(samples)

            // Инжектируем ПЕРЕД сменой состояния — активное окно ещё наше
            state = .injecting
            overlayController?.show(message: text)
            textInjector.inject(text: text)

            // Сохраняем в историю
            historyStore.append(TranscriptionEntry(
                id: UUID(),
                date: Date(),
                text: text,
                durationSeconds: Double(samples.count) / 16_000.0,
                language: nil
            ))

            // Overlay исчезает через 1.5 сек
            overlayController?.dismiss(after: 1.5)
            state = .idle

        } catch TranscriptionError.recordingTooShort {
            state = .idle

        } catch TranscriptionError.emptyResult {
            overlayController?.show(message: "Не услышал ничего")
            overlayController?.dismiss(after: 2.0)
            state = .idle

        } catch TranscriptionError.modelNotLoaded {
            // Показать экран скачивания
            state = .error(.modelNotLoaded)

        } catch {
            state = .error(.transcriptionFailed(error.localizedDescription))
        }
    }
}
```

---

## Матрица тестирования

Для каждого приложения проверить: нажать хоткей → сказать фразу → текст появляется.

| Приложение | Ожидаемая стратегия | Тест |
|---|---|---|
| **TextEdit** (RTF) | AX — `kAXSelectedText` | Создать документ, кликнуть в текст, записать |
| **TextEdit** (Plain) | AX — `kAXSelectedText` | Тот же сценарий |
| **Notes.app** | AX — `kAXSelectedText` | Создать заметку, кликнуть |
| **Xcode** (редактор) | AX — `kAXSelectedText` | Открыть .swift файл |
| **Safari** (URL bar) | AX — `kAXSelectedText` | Кликнуть в адресную строку |
| **Safari** (текстовое поле) | AX или Pasteboard | Открыть любую форму |
| **Chrome** (текстовое поле) | Pasteboard fallback | Открыть google.com, кликнуть поиск |
| **VS Code** (Electron) | Pasteboard fallback | Открыть любой файл |
| **Terminal** | Pasteboard fallback | Открыть терминал |
| **Slack** (Electron) | Pasteboard fallback | Кликнуть в поле сообщения |
| **Notion** (Electron) | Pasteboard fallback | Кликнуть в страницу |
| **Password field** | Должен NOT вставлять | Проверить в любом login form |

### Процедура теста для каждого приложения:
1. Переключиться в тестируемое приложение
2. Кликнуть в текстовое поле (установить фокус и каретку)
3. Нажать Right Option, сказать "тестовая фраза", отпустить
4. Проверить: текст появился в поле

---

## Известные ограничения

### Chrome / Electron приложения
AX injection не работает (Chromium блокирует `AXSelectedTextAttribute`). Pasteboard fallback надёжно работает. **Это нормально и ожидаемо.**

### Поля ввода пароля
macOS намеренно блокирует как AX, так и синтетические события для password fields. SayVoice не вставит текст в пароль — **это правильное поведение с точки зрения безопасности.** Показываем сообщение в overlay (опционально).

### Remote Desktop / Screen Sharing
Синтетические CGEvents могут не прокидываться в remote session. Это known limitation — не исправляем в v1.

### Терминальные приложения
Terminal.app: Pasteboard + Cmd+V работает. iTerm2: аналогично. Для Terminal нужно убедиться что focus в окне, не в меню.

---

## Технические детали

### Порядок проверки AX атрибутов

```
1. kAXFocusedUIElementAttribute  → находим сфокусированный элемент
2. kAXSelectedTextAttribute      → пробуем вставить в каретку (предпочтительно)
   └─► isSettable? → нет → fallback
3. kAXValueAttribute             → заменяем всё значение (если AXSelectedText недоступен)
   └─► isSettable? → нет → выходим, передаём в Pasteboard
```

### Почему AXSelectedText предпочтительнее AXValue

- `AXSelectedText` = вставить в позицию каретки, не трогает остальной текст
- `AXValue` = заменить всё содержимое поля (теряем существующий текст если нет каретки в конце)

### Thread safety PasteboardInjector

`PasteboardInjector.inject()` вызывается с `@MainActor`. `sendCmdV()` постит события через `CGEventTapCreate` — это безопасно с main thread.

`Thread.sleep(0.02)` — синхронная пауза для гарантии обновления буфера перед постингом Cmd+V. Допустимо т.к. вызывается с MainActor только при активном инжекте (не блокирует UI постоянно).

### Сохранение и восстановление буфера обмена

Delay 300ms достаточен для большинства приложений. Некоторые (особенно тяжёлые Electron) могут читать буфер медленно — в этом случае текст уже вставлен к моменту восстановления буфера.

---

## Критерии готовности M4

- [x] TextEdit: текст вставляется в позицию каретки — **AX via kAXSelectedText, работает**
- [x] Safari search bar: текст вставляется — **AX, работает**
- [x] Chrome input: текст вставляется через pasteboard fallback — **Paste → Chrome, работает**
- [x] Xcode: текст вставляется в позицию курсора — **AX, работает**
- [x] Существующий текст в буфере обмена восстанавливается после вставки — **через 300ms Task.sleep**
- [x] Overlay показывает транскрибированный текст 2.0 сек, потом fade out — **2.0 сек (не 1.5 как в плане)**
- [x] Password field: текст НЕ вставляется (без краша) — **AX blocked + CGEvent blocked = корректно**
- [x] Пустая транскрипция: overlay "Не услышал ничего", без попытки инжекта — **TranscriptionError.emptyResult**
- [x] Вставляемый текст имеет trailing space для удобного продолжения набора — **`text + " "`**

**Дата завершения: 2026-02-25**

---

## Заметки по реализации (отличия от плана)

1. **PasteboardInjector** — `@MainActor`, восстановление буфера через `Task { @MainActor in try? await Task.sleep(for: .seconds(0.3)) }` вместо `DispatchQueue.main.asyncAfter` (Swift 6 strict concurrency safe).

2. **AXTextInjector** — `focusedRef as! AXUIElement` (force cast после проверки `.success`), вместо `as?` conditional cast (Clang ошибка: "conditional downcast to CoreFoundation type always succeeds").

3. **Sublime Text, VS Code, Terminal** — pasteboard fallback работает корректно. Лог: `Text injected via Paste → Sublime Text` (без слова "failed").

4. **Overlay timeout** — 2.0 сек (не 1.5 как в исходном плане). Достаточно для прочтения транскрипции.

5. **historyStore** — не реализован (scope M5). `AppCoordinator.handleKeyUp()` не вызывает `historyStore.append()`.

6. **Тестовые фразы** — RU: "Раз, два, три, четыре, пять. Проверка микрофона." (p=0.987), EN: "1, 2, 3, 4, 5, check in, check in." (p=0.946), Mixed: "Hello, привет, проверка, testing 123." (p=0.690). Все вставлены корректно в Sublime Text через pasteboard.
