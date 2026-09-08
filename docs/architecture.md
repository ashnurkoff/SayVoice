# Архитектура SayVoice

## 1. Диаграмма компонентов

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SayVoiceApp.swift                            │
│       @main · NSApplicationDelegate · activationPolicy: .accessory │
└────────────────────────┬────────────────────────────────────────────┘
                         │ создаёт и владеет
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  AppCoordinator  (@MainActor class)                 │
│                                                                     │
│  Единственный источник истины. Реагирует на события компонентов,   │
│  управляет переходами состояний, координирует вызовы.              │
└──┬──────┬──────┬──────┬──────┬──────┬──────────────────────────────┘
   │      │      │      │      │      │
   │      │      │      │      │      └──► TranscriptionHistoryStore
   │      │      │      │      └─────────► SettingsStore
   │      │      │      └────────────────► TextInjector
   │      │      └───────────────────────► TranscriptionEngine  (actor)
   │      └──────────────────────────────► AudioRecorder        (actor)
   └─────────────────────────────────────► HotkeyListener
                                           MenuBarController
                                           OverlayWindowController
                                           PermissionManager
```

### Ответственности компонентов

| Компонент | Ответственность |
|---|---|
| `AppCoordinator` | State machine, оркестрация, единственный источник истины |
| `HotkeyListener` | CGEventTap, key-down/up события, конфигурация хоткея |
| `AudioRecorder` | AVAudioEngine, захват PCM Float32 @ 16kHz mono |
| `TranscriptionEngine` | Загрузка модели, вызов whisper.cpp, управление actor lifecycle |
| `TextInjector` | AXUIElement инжект + pasteboard fallback |
| `MenuBarController` | NSStatusItem, SF Symbol анимация по состоянию |
| `OverlayWindowController` | NSPanel floating overlay без захвата фокуса |
| `SettingsStore` | @Observable, UserDefaults, настройки пользователя |
| `TranscriptionHistoryStore` | In-memory + JSON, последние 500 записей |
| `PermissionManager` | Запрос и проверка Microphone + Accessibility |

---

## 2. State Machine

```
                    ┌─────────────────────────────────────────────┐
                    │                   IDLE                      │
                    │  • Иконка: "waveform" (серая, статичная)    │
                    │  • Overlay: скрыт                           │
                    └──────────────────┬──────────────────────────┘
                                       │ hotkey keyDown
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │                RECORDING                    │
                    │  • AudioRecorder.startCapture()             │
                    │  • Иконка: "waveform" красная, пульсирует   │
                    │  • Overlay: "● Запись..."                   │
                    └──────────────────┬──────────────────────────┘
                                       │ hotkey keyUp
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │              TRANSCRIBING                   │
                    │  • AudioRecorder.stopCapture() → [Float32]  │
                    │  • TranscriptionEngine.transcribe() async   │
                    │  • Иконка: "ellipsis.circle" оранжевая      │
                    │  • Overlay: "Транскрибирую..."              │
                    └──────────────────┬──────────────────────────┘
                                       │ результат String
                                       ▼
                    ┌─────────────────────────────────────────────┐
                    │               INJECTING                     │
                    │  • TextInjector.inject(text)                │
                    │  • Overlay: показывает транскрибированный   │
                    │    текст (зелёный), 1.5 сек                 │
                    └──────────────────┬──────────────────────────┘
                                       │ инжект завершён
                                       ▼
                                     IDLE
```

### Переходы при ошибках

Из **любого** состояния при ошибке → IDLE:

```
RECORDING   → ошибка микрофона    → Overlay: "Ошибка микрофона"   → IDLE
TRANSCRIBING → пустой результат   → Overlay: "Не услышал ничего"  → IDLE
TRANSCRIBING → таймаут (>10 сек)  → Overlay: "Превышено время"    → IDLE
TRANSCRIBING → запись < 0.3 сек   → тихо игнорируется             → IDLE
INJECTING   → AX denied           → Overlay: "Нет доступа AX"     → IDLE
```

---

## 3. Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   Полный поток данных                           │
└─────────────────────────────────────────────────────────────────┘

[Пользователь зажимает Right Option]
        │
        ▼
CGEventTap callback (произвольный поток)
  └─► Task { @MainActor in coordinator.handleKeyDown() }
        │
        ▼
AppCoordinator.handleKeyDown()
  └─► state = .recording
  └─► menuBarController.setState(.recording)
  └─► overlayController.show("● Запись...")
  └─► await audioRecorder.startCapture()
        │
        │   [AVAudioEngine installTapOnBus]
        │   [lock-free ring buffer ← PCM Float32 chunks @ 16kHz]
        │
[Пользователь отпускает Right Option]
        │
        ▼
CGEventTap callback (произвольный поток)
  └─► Task { @MainActor in coordinator.handleKeyUp() }
        │
        ▼
AppCoordinator.handleKeyUp()
  └─► state = .transcribing
  └─► overlayController.show("Транскрибирую...")
  └─► let samples = await audioRecorder.stopCapture()  // → [Float32]
        │
        ▼
  [Проверка: samples.count < 4800? (< 0.3 сек) → IDLE, тихо]
        │
        ▼
  await transcriptionEngine.transcribe(samples)
    └─► WhisperContext.transcribe([Float32])  // actor, фоновый поток
          └─► whisper_transcribe_pcm() C вызов
          └─► возвращает String
        │
        ▼
AppCoordinator получает String
  └─► state = .injecting
  └─► textInjector.inject(text: result)
        ├─► AXUIElement попытка (kAXSelectedTextAttribute)
        │     успех → вставлено
        │     провал ↓
        └─► Pasteboard fallback
              └─► сохранить буфер → вставить текст
              └─► CGEvent: keyDown Cmd+V → keyUp Cmd+V
              └─► через 300ms: восстановить буфер
        │
        ▼
  overlayController.show(result, 1.5 сек → fade out)
  historyStore.append(TranscriptionEntry(...))
  state = .idle
```

---

## 4. Swift 6 Concurrency Паттерны

### 4.1 Разделение акторов

```swift
// Главный поток UI — @MainActor
@MainActor
final class AppCoordinator { ... }

@MainActor
final class MenuBarController { ... }

@MainActor
final class OverlayWindowController { ... }

// Изолированные акторы (не MainActor — не блокируют UI)
actor AudioRecorder { ... }         // накопление PCM буфера
actor TranscriptionEngine { ... }   // lifecycle модели
actor WhisperContext { ... }        // C-указатель на whisper_context*
```

### 4.2 CGEventTap → MainActor переход

```swift
// CGEventTap callback вызывается на произвольном системном потоке.
// Никогда не вызывайте AppCoordinator напрямую — только через Task.
let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    let coordinator = Unmanaged<AppCoordinator>.fromOpaque(refcon!).takeUnretainedValue()
    Task { @MainActor in
        coordinator.handle(type: type, event: event)
    }
    return Unmanaged.passRetained(event)
}
```

### 4.3 AVAudioEngine tap — реал-тайм поток

```swift
// НЕЛЬЗЯ в tap callback:
//   - Task { await actor.method() }  // может аллоцировать
//   - Swift async/await вызовы
//   - Любые аллокации (особенно на real-time потоке)
//
// МОЖНО:
//   - Запись в заранее выделенный lock-free ring buffer
//   - OSAtomicAdd для счётчиков
//   - Memcpy в pre-allocated буфер

inputNode.installTapOnBus(0, bufferSize: 4096, format: fmt) { buffer, _ in
    // Минимальная работа: копируем floats в ring buffer
    self.ringBuffer.write(buffer)  // lock-free
}
```

### 4.4 Переключение контекстов

```swift
// AudioRecorder — actor, вызывается с MainActor
func stopCapture() async -> [Float] {
    // Выполняется на actor executor AudioRecorder
    engine.inputNode.removeTapOnBus(0)
    engine.stop()
    defer { pcmBuffer = [] }
    return pcmBuffer  // копия
}

// TranscriptionEngine — actor, держит тяжёлый WhisperContext
func transcribe(_ samples: [Float]) async throws -> String {
    // Выполняется на actor executor TranscriptionEngine (не MainActor!)
    guard let ctx = whisperContext else { throw TranscriptionError.modelNotLoaded }
    return try await ctx.transcribe(samples: samples)
}
```

---

## 5. Управление памятью

- **Модель whisper.cpp** (~465 MB) загружается один раз при первом обращении и держится в памяти всё время работы приложения (дешевле повторная загрузка, пока приложение запущено).
- `whisper_context*` — raw C-указатель, освобождается через `whisper_free()` в `deinit` актора `WhisperContext`.
- PCM буфер очищается после каждой транскрипции (`defer { pcmBuffer = [] }`).
- История транскрипций — максимум 500 записей, старые удаляются при добавлении новых.

---

## 6. Ошибки и граничные случаи

| Ситуация | Обработка |
|---|---|
| Accessibility не выдан | `HotkeyListener` возвращает `.tapCreationFailed`; onboarding flow |
| Микрофон не выдан | `PermissionManager` показывает системный alert |
| Модель не скачана | `TranscriptionEngine` бросает `.modelNotLoaded`; открывается `ModelDownloadView` |
| Запись < 0.3 сек | Тихо игнорируется, возврат в IDLE |
| Пустой результат Whisper | Overlay: "Не услышал ничего", возврат в IDLE |
| Таймаут транскрипции | `Task.sleep` + cancellation через 10 сек |
| AX инжект провалился | Автоматический fallback на Pasteboard, без ошибки пользователю |
| Pasteboard провалился | Логируем, Overlay: "Не удалось вставить текст" |
| Password field | AX возвращает ошибку; fallback тоже не работает; Overlay предупреждает |
