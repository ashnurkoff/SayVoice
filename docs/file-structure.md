# Структура файлов проекта SayVoice

## Дерево проекта

```
SayVoice/
├── SayVoice.xcodeproj/
│
├── SayVoice/                                   ← основной таргет
│   │
│   ├── App/
│   │   ├── SayVoiceApp.swift                   ← точка входа @main
│   │   ├── AppCoordinator.swift                ← оркестратор, state machine
│   │   └── AppState.swift                      ← enum состояний приложения
│   │
│   ├── HotkeyListener/
│   │   ├── HotkeyListener.swift                ← CGEventTap, key-down/up
│   │   └── HotkeyError.swift                   ← ошибки регистрации хоткея
│   │
│   ├── Audio/
│   │   ├── AudioRecorder.swift                 ← actor, AVAudioEngine, PCM буфер
│   │   ├── AudioConverter.swift                ← AVAudioConverter в 16kHz f32
│   │   └── AudioError.swift
│   │
│   ├── Transcription/
│   │   ├── TranscriptionEngine.swift           ← actor, lifecycle модели
│   │   └── TranscriptionError.swift
│   │
│   ├── TextInjection/
│   │   ├── TextInjector.swift                  ← единая точка входа (AX → Pasteboard)
│   │   ├── AXTextInjector.swift                ← AXUIElement логика
│   │   └── PasteboardInjector.swift            ← clipboard + синтетический Cmd+V
│   │
│   ├── UI/
│   │   ├── MenuBarController.swift             ← NSStatusItem, анимация иконки
│   │   ├── OverlayWindowController.swift       ← NSPanel floating (non-activating)
│   │   ├── OverlayView.swift                   ← SwiftUI вид оверлея
│   │   ├── MenuBarPopoverView.swift            ← история + быстрые настройки
│   │   └── SettingsView.swift                  ← полный экран настроек
│   │
│   ├── Settings/
│   │   ├── SettingsStore.swift                 ← @Observable, UserDefaults
│   │   └── SettingsKeys.swift                  ← строковые константы ключей
│   │
│   ├── History/
│   │   ├── TranscriptionHistoryStore.swift     ← @Observable, JSON персистенция
│   │   └── TranscriptionEntry.swift            ← Codable struct записи
│   │
│   ├── Permissions/
│   │   └── PermissionManager.swift             ← проверка + запрос Mic + AX
│   │
│   ├── ModelManagement/
│   │   ├── ModelManager.swift                  ← обнаружение, скачивание модели
│   │   └── ModelDownloadView.swift             ← SwiftUI экран загрузки
│   │
│   └── Resources/
│       ├── Assets.xcassets                     ← иконка, template image для menu bar
│       ├── SayVoice.entitlements               ← App Sandbox = NO
│       └── Info.plist                          ← LSUIElement, NSMicrophoneUsageDescription
│
└── Packages/
    └── CWhisper/                               ← локальный SPM пакет
        ├── Package.swift
        └── Sources/
            ├── CWhisper/                       ← C target (whisper.cpp + ggml)
            │   ├── include/
            │   │   └── whisper_bridge.h        ← C API, видимый Swift
            │   ├── whisper.cpp
            │   ├── ggml.c
            │   ├── ggml-alloc.c
            │   ├── ggml-backend.cpp
            │   ├── ggml-quants.c
            │   ├── ggml-metal.m
            │   └── ggml-metal.metal
            └── WhisperSwift/                   ← Swift target
                ├── WhisperContext.swift
                ├── WhisperTranscriber.swift
                └── WhisperError.swift
```

---

## Описание каждого файла

### App/

**`SayVoiceApp.swift`**
Точка входа (`@main`). Реализует `NSApplicationDelegate`. Вызывает `NSApp.setActivationPolicy(.accessory)` — убирает иконку из Dock. Не содержит `WindowGroup`. Создаёт и хранит `AppCoordinator`.

**`AppCoordinator.swift`**
`@MainActor final class`. Центральный оркестратор. Хранит текущее состояние `AppState`. Реагирует на события от `HotkeyListener`, вызывает `AudioRecorder`, `TranscriptionEngine`, `TextInjector`. Публикует изменения состояния в UI компоненты.

**`AppState.swift`**
```swift
enum AppState {
    case idle
    case recording
    case transcribing
    case injecting
    case error(AppError)
}
```

---

### HotkeyListener/

**`HotkeyListener.swift`**
Создаёт `CGEventTap` на уровне `.cgSessionEventTap`. Проверяет `AXIsProcessTrustedWithOptions` при старте. Вызывает `onKeyDown` / `onKeyUp` колбэки. Конфигурируемый keyCode (дефолт: 61 = Right Option). Управляет `CFMachPort` lifecycle.

**`HotkeyError.swift`**
```swift
enum HotkeyError: Error {
    case tapCreationFailed          // Accessibility не выдан
    case accessibilityNotGranted    // AX проверка провалилась
}
```

---

### Audio/

**`AudioRecorder.swift`**
`actor`. Создаёт `AVAudioEngine`, устанавливает tap на `inputNode`. Хранит pre-allocated ring buffer для PCM Float32 данных. Методы: `startCapture() async throws`, `stopCapture() async -> [Float]`. Tap callback использует только lock-free операции.

**`AudioConverter.swift`**
Инкапсулирует `AVAudioConverter` логику. Принимает `AVAudioPCMBuffer` в аппаратном формате (напр. 48kHz stereo), возвращает `AVAudioPCMBuffer` в формате whisper (16kHz mono Float32).

**`AudioError.swift`**
```swift
enum AudioError: Error {
    case engineStartFailed
    case formatConversionFailed
    case permissionDenied
    case noAudioInput
}
```

---

### Transcription/

**`TranscriptionEngine.swift`**
`actor`. Ленивая загрузка `WhisperContext` при первом вызове. Метод `transcribe(_ samples: [Float]) async throws -> String`. Управляет отменой (Task cancellation) при таймауте. Делегирует в `WhisperTranscriber` из SPM пакета.

**`TranscriptionError.swift`**
```swift
enum TranscriptionError: Error {
    case modelNotLoaded
    case modelLoadFailed(URL)
    case inferenceError
    case emptyResult
    case timeout
    case recordingTooShort        // < 0.3 сек (< 4800 сэмплов)
}
```

---

### TextInjection/

**`TextInjector.swift`**
Единая точка входа. Принимает `text: String`. Получает PID фронтального приложения через `NSWorkspace.shared.frontmostApplication`. Пробует `AXTextInjector`, при провале — `PasteboardInjector`. Добавляет trailing space к тексту.

**`AXTextInjector.swift`**
Реализует инжект через `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`. Возвращает `Bool` (успех/провал). Обрабатывает edge cases: поле не фокусировано, атрибут не settable, password field.

**`PasteboardInjector.swift`**
1. Сохраняет `NSPasteboard.general.string(forType: .string)`
2. Записывает наш текст
3. Создаёт синтетические `CGEvent` (keyDown Cmd+V, keyUp Cmd+V), постит через `.cghidEventTap`
4. Через 300ms восстанавливает буфер обмена

---

### UI/

**`MenuBarController.swift`**
`@MainActor final class`. Создаёт `NSStatusItem` с `variableStatusItemLength`. Реагирует на `AppState` изменения: обновляет SF Symbol, цвет, анимацию. Левый клик → показывает `MenuBarPopoverView`. Правый клик → меню (История, Настройки, Quit).

**`OverlayWindowController.swift`**
`@MainActor final class: NSWindowController`. Создаёт `NSPanel` с флагами `.borderless`, `.nonactivatingPanel`, `.hudWindow`. Уровень окна: `.floating`. Позиционирует в нижней части основного экрана. Методы: `show(message:isRecording:)`, `dismiss(animated:)`.

**`OverlayView.swift`**
SwiftUI `View`. Показывает пульсирующий красный кружок при записи, текст сообщения. Материал `.ultraThinMaterial`, скруглённые углы. Анимация fade-in при появлении.

**`MenuBarPopoverView.swift`**
SwiftUI `View`. Список последних 10 транскрипций с временными метками. Нажатие на запись → копировать в буфер обмена. Кнопка "Очистить историю". Ссылка "Настройки...". Показывается в `NSPopover`.

**`SettingsView.swift`**
SwiftUI `View`. Секции: хоткей (click-to-record пикер), выбор модели, язык (Авто/EN/RU), переключатели (overlay, звук, метод вставки). Открывается через `NSApp.sendAction(Selector("showSettingsWindow:"), ...)` или из popover.

---

### Settings/

**`SettingsStore.swift`**
`@Observable final class`. Читает/пишет `UserDefaults`. Публикует изменения подписчикам. Свойства: `hotkeyCode: Int`, `modelSize: String`, `language: String`, `overlayEnabled: Bool`, `soundFeedback: Bool`, `pasteMethod: String`, `launchAtLogin: Bool`.

**`SettingsKeys.swift`**
Строковые константы:
```swift
enum SettingsKeys {
    static let hotkeyCode     = "sv_hotkey_code"
    static let modelSize      = "sv_model_size"
    static let language       = "sv_language"
    static let overlayEnabled = "sv_overlay_enabled"
    static let soundFeedback  = "sv_sound_feedback"
    static let pasteMethod    = "sv_paste_method"
    static let launchAtLogin  = "sv_launch_at_login"
}
```

---

### History/

**`TranscriptionHistoryStore.swift`**
`@Observable final class`. Хранит `[TranscriptionEntry]` (max 500). Персистирует в `~/Library/Application Support/SayVoice/history.json`. Методы: `append(_:)`, `clear()`, `entries(last:)`.

**`TranscriptionEntry.swift`**
```swift
struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double     // длительность записи
    let language: String?           // определённый язык ("ru", "en")
}
```

---

### Permissions/

**`PermissionManager.swift`**
`@MainActor final class`. Методы:
- `requestMicrophone() async -> Bool`
- `isMicrophoneGranted: Bool` (computed)
- `isAccessibilityGranted: Bool`
- `requestAccessibilityPrompt()` — показывает системный диалог
- `openAccessibilitySettings()` — открывает System Settings
- `openMicrophoneSettings()` — открывает System Settings

---

### ModelManagement/

**`ModelManager.swift`**
`@MainActor final class`. Директория: `~/Library/Application Support/SayVoice/Models/`. Методы: `isModelAvailable(size:) -> Bool`, `downloadModel(size:) async throws` (публикует прогресс через `AsyncStream<Double>`). Поддерживаемые размеры: "tiny", "base", "small".

**`ModelDownloadView.swift`**
SwiftUI `View`. Список доступных моделей с размерами и характеристиками. Кнопка "Скачать" с прогресс-баром. Показывает уже скачанные модели с галочкой.

---

### Resources/

**`Assets.xcassets`**
- `AppIcon.appiconset` — иконка приложения (1024x1024)
- `MenuBarIcon.imageset` — template image 18x18pt для menu bar (чёрный waveform на прозрачном)

**`SayVoice.entitlements`**
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

**`Info.plist`** (ключевые записи)
```xml
<key>LSUIElement</key>          <!-- Нет иконки в Dock -->
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>...</string>
<key>CFBundleDisplayName</key>
<string>SayVoice</string>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
```

---

### Packages/CWhisper/

**`Package.swift`**
Определяет два таргета: `CWhisper` (C/C++/ObjC) и `WhisperSwift` (Swift, зависит от CWhisper). Флаги компиляции: `-std=c++17`, `-O3`, `GGML_USE_METAL`. Линкует Metal, Accelerate, CoreML.

**`whisper_bridge.h`**
Единственный публичный заголовок C-моста. Определяет `SayVoiceWhisperParams`, функции `whisper_bridge_init`, `whisper_bridge_free`, `whisper_bridge_transcribe`, `whisper_bridge_free_string`. Все с `extern "C"`.

**`WhisperContext.swift`**
`actor`. Хранит `OpaquePointer?` к `whisper_context*`. Инициализируется из URL модели. Метод `transcribe(samples: [Float], language: String?) throws -> String`. `deinit` вызывает `whisper_bridge_free`.

**`WhisperTranscriber.swift`**
Высокоуровневый интерфейс. Принимает `[Float]`, возвращает `String`. Настраивает `SayVoiceWhisperParams` (n_threads = ProcessInfo.processInfo.processorCount, language = -1 для авто).

**`WhisperError.swift`**
```swift
enum WhisperError: Error {
    case modelLoadFailed
    case transcriptionFailed
    case invalidSampleCount     // < whisper's minimum
}
```

---

## Итоги

| Метрика | Значение |
|---|---|
| Swift файлов (основной таргет) | 25 |
| Swift файлов (SPM пакет) | 3 |
| C/C++ файлов (vendored whisper.cpp) | 8 |
| Внешних SPM зависимостей | 0 |
| Системных фреймворков | 10 |
