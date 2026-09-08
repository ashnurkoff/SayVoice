# Разрешения macOS

## Обзор требований

SayVoice требует два системных разрешения и **выключенный App Sandbox**:

| Разрешение | Назначение | Способ выдачи |
|---|---|---|
| Microphone | Захват голоса через AVAudioEngine | Системный диалог (автоматически) |
| Accessibility | CGEventTap + AXUIElement text injection | Вручную в System Settings |

---

## 1. Microphone (Микрофон)

### Зачем

`AVAudioEngine.inputNode` требует разрешения на доступ к микрофону. Без него `engine.start()` упадёт с ошибкой.

### Как запросить (Swift)

```swift
// macOS 14+
import AVFAudio

func requestMicrophonePermission() async -> Bool {
    return await AVAudioApplication.requestRecordPermission()
}

// Проверка текущего статуса (без диалога)
func checkMicrophoneStatus() -> AVAudioApplication.recordPermission {
    return AVAudioApplication.shared.recordPermission
}
// Возможные значения: .granted, .denied, .undetermined
```

### Info.plist

```xml
<key>NSMicrophoneUsageDescription</key>
<string>SayVoice использует микрофон для записи голоса и транскрипции речи в текст.</string>
```

Без этого ключа macOS крашит приложение при запросе разрешения.

### Поведение при отказе

Если пользователь нажал "Не разрешать" → `AVAudioApplication.requestRecordPermission()` вернёт `false`. Повторный запрос невозможен программно — нужно открыть System Settings:

```swift
if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
    NSWorkspace.shared.open(url)
}
```

---

## 2. Accessibility (Специальные возможности)

### Зачем

Два отдельных использования:

**a) CGEventTap — глобальный хоткей**
`CGEventTapCreate(tap: .cgSessionEventTap, ...)` возвращает `nil` без Accessibility. Приложение не сможет получать события клавиатуры из других приложений.

**b) AXUIElement — инжект текста**
`AXUIElementCreateApplication(pid)` + `AXUIElementSetAttributeValue` требует Accessibility для изменения содержимого текстовых полей в других приложениях.

### Как проверить и направить пользователя

```swift
import ApplicationServices

func isAccessibilityGranted() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func requestAccessibilityWithPrompt() {
    // Показывает системный диалог "SayVoice хочет управлять этим компьютером"
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

func openAccessibilitySettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
```

### Важное поведение

- Нет Info.plist ключа (в отличие от микрофона) — нельзя предоставить описание через plist
- Пользователь должен **вручную** включить SayVoice в `System Settings > Privacy & Security > Accessibility`
- После включения **не требуется перезапуск** приложения (CGEventTap можно создать заново)
- При изменении разрешения (включили/выключили) приложение получает уведомление через `NSWorkspace.shared.notificationCenter` (event: `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`)

### Input Monitoring (на некоторых версиях macOS)

На macOS 13+ CGEventTap с `kCGHIDEventTap` может **дополнительно** требовать Input Monitoring разрешение:

```swift
import IOKit.hid

func checkInputMonitoring() -> Bool {
    return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}
```

Если требуется — открыть `System Settings > Privacy & Security > Input Monitoring`.

---

## 3. App Sandbox — ОТКЛЮЧЁН

### Почему обязательно отключить

| Функция | Требование |
|---|---|
| `CGEventTapCreate(.cgSessionEventTap)` | Без sandbox или с `com.apple.security.temporary-exception.mach-lookup.global-name` |
| `AXUIElementSetAttributeValue` в другие процессы | Без sandbox |
| `CGEvent.post(tap: .cghidEventTap)` (синтетический Cmd+V) | Без sandbox |

Sandboxed приложение может использовать только `CGEventTapCreate(.cgAnnotatedSessionEventTap)` — этот тип даёт только "слушать" события, но CGEventTap для global hotkey с `.cgSessionEventTap` недоступен.

### Последствия

- **Нельзя** публиковать в Mac App Store
- Нужна подпись Developer ID (или локальный запуск)
- Нет автоматических ограничений на доступ к файловой системе (ответственность разработчика)

### SayVoice.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <!-- Никаких других entitlements для v1 не требуется -->
</dict>
</plist>
```

---

## 4. Онбординг Flow (первый запуск)

```
Запуск приложения
      │
      ▼
PermissionManager.checkAll()
      │
      ├─► Микрофон: .undetermined?
      │         └─► показать системный диалог
      │               granted → ✓
      │               denied  → показать инструкции + кнопка "Открыть настройки"
      │
      ├─► Accessibility: false?
      │         └─► показать объяснение + кнопка "Открыть настройки"
      │               (ждать ручного включения)
      │               granted → ✓
      │
      ├─► Модель ggml-small.bin не найдена?
      │         └─► показать ModelDownloadView
      │               скачать (~465 MB с прогресс-баром)
      │               готово → ✓
      │
      ▼
Приложение готово к работе
(overlay: "SayVoice готов. Зажмите ⌥R для записи")
```

### Экраны онбординга (SwiftUI sheets в popover)

**Шаг 1 — Микрофон:**
```
┌─────────────────────────────────────┐
│  🎙  Доступ к микрофону             │
│                                     │
│  SayVoice нужен доступ к            │
│  микрофону для записи голоса.       │
│                                     │
│  [Разрешить доступ]                 │
└─────────────────────────────────────┘
```

**Шаг 2 — Accessibility:**
```
┌─────────────────────────────────────┐
│  ♿  Специальные возможности        │
│                                     │
│  Нужен для:                         │
│  • Глобального хоткея               │
│  • Вставки текста                   │
│                                     │
│  Включите SayVoice в:               │
│  System Settings > Privacy >        │
│  Accessibility                      │
│                                     │
│  [Открыть настройки]  [Проверить]   │
└─────────────────────────────────────┘
```

**Шаг 3 — Загрузка модели:**
```
┌─────────────────────────────────────┐
│  ⬇  Загрузка модели Whisper         │
│                                     │
│  ggml-small (~465 MB)               │
│  ████████░░░░░░  52%                │
│                                     │
│  Загружается один раз.              │
│  Транскрипция работает офлайн.      │
└─────────────────────────────────────┘
```

---

## 5. Сводная таблица

| | Microphone | Accessibility | App Sandbox |
|---|---|---|---|
| **Метод** | Системный диалог | Ручное в System Settings | Всегда выключен |
| **Info.plist ключ** | `NSMicrophoneUsageDescription` | — | — |
| **API проверки** | `AVAudioApplication.shared.recordPermission` | `AXIsProcessTrustedWithOptions` | — |
| **Повторный запрос** | Только через System Settings | Нет диалога, только System Settings | — |
| **При отказе** | Приложение не может записывать | Хоткей не работает, AX инжект не работает | Нет функциональности вообще |
