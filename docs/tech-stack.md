# Технический стек SayVoice

## 1. Платформа и язык

### Swift + SwiftUI (macOS 14.0+)

**Почему не Electron / Tauri:**
- CGEventTap (глобальный хоткей) требует нативного процесса без web-рантайма
- AXUIElement (текст инжект) — только нативный macOS API
- Electron добавляет ~100-200 MB к бинарнику и ухудшает отзывчивость
- SwiftUI + AppKit даёт лучший нативный feel и производительность

**Почему не Python + PyObjC:**
- Python требует рантайм (3.10+ с ~60 MB зависимостей)
- PyObjC устарел, плохо поддерживает async/await
- Сложнее встроить whisper.cpp (нужен Python-пакет или subprocess)
- Медленнее для продакшн инструмента

**Swift 6 (strict concurrency):** Все компоненты используют `@MainActor`, `actor`, и structured concurrency. Это предотвращает data races на уровне компилятора.

---

## 2. Speech-to-Text: whisper.cpp

### Интеграция: локальный SPM пакет с C-мостом

**Почему не OpenAI Whisper API:**
- Требует интернет + API-ключ пользователя
- Передаёт аудио в облако (проблема приватности)
- Задержка сети добавляет 1-3 сек к каждому запросу
- Стоимость: ~$0.006 за минуту (накапливается при частом использовании)

**Почему не mlx-whisper:**
- Требует Python рантайм (несовместимо с нативным Swift приложением без subprocess)
- Subprocess добавляет IPC-overhead и сложность управления процессом

**Почему whisper.cpp:**
- Написан на C/C++ — напрямую вызывается из Swift через C-мост
- Metal GPU ускорение на Apple Silicon — ~2-3 сек для 10-секундной фразы
- Зрелый проект (ggerganov, 60k+ звёзд на GitHub)
- Поддерживает все модели Whisper без изменений

### Структура SPM пакета

```
Packages/
└── CWhisper/
    ├── Package.swift
    └── Sources/
        ├── CWhisper/                    ← C target
        │   ├── include/
        │   │   └── whisper_bridge.h     ← единственный заголовок, видимый Swift
        │   ├── whisper.cpp              ← vendored (~ 10k строк)
        │   ├── ggml.c
        │   ├── ggml-alloc.c
        │   ├── ggml-backend.cpp
        │   ├── ggml-quants.c
        │   ├── ggml-metal.m             ← Objective-C для Metal интеграции
        │   └── ggml-metal.metal         ← Metal шейдеры
        └── WhisperSwift/                ← Swift target
            ├── WhisperContext.swift     ← actor, OpaquePointer к C структуре
            ├── WhisperTranscriber.swift ← высокоуровневый интерфейс
            └── WhisperError.swift
```

### Package.swift (ключевые моменты)

```swift
// Swift/C++ interop требует явного указания стандарта
.cxxLanguageStandard(.cxx17)

// C target — компилятор флаги
.target(
    name: "CWhisper",
    cSettings: [
        .define("GGML_USE_METAL"),
        .unsafeFlags(["-O3", "-DNDEBUG"])
    ],
    linkerSettings: [
        .linkedFramework("Metal"),
        .linkedFramework("MetalKit"),
        .linkedFramework("Accelerate"),
        .linkedFramework("CoreML")
    ]
)
```

### whisper_bridge.h — C-мост для Swift

```c
// Этот файл — единственная точка контакта между Swift и whisper.cpp.
// Все типы C++, std::, namespace — скрыты внутри .cpp файлов.
// Swift видит только чистый C (extern "C").

#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct whisper_context whisper_context;  // opaque

// Параметры транскрипции
typedef struct {
    int     n_threads;
    int     language;       // -1 = авто-определение
    bool    translate;      // true = переводить на английский
    bool    no_timestamps;
    float   temperature;    // 0.0 = детерминированный режим
} SayVoiceWhisperParams;

// Lifecycle
whisper_context* whisper_bridge_init(const char* model_path);
void             whisper_bridge_free(whisper_context* ctx);

// Транскрипция (возвращает heap-строку, освободить через whisper_bridge_free_string)
char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,    // PCM Float32 @ 16kHz mono
    int32_t               n_samples,
    SayVoiceWhisperParams params
);
void whisper_bridge_free_string(char* str);
```

> **`no_timestamps` всегда `false`.** Whisper декодирует аудио окнами по 30 секунд и
> сдвигает окно на конец последнего распознанного сегмента. Без timestamp-токенов
> сдвиг принудительно равен целым 30 секундам (`whisper.cpp`, `seek_delta = 100*WHISPER_CHUNK_SIZE`),
> и речь, попавшая на стык окон, не декодируется ни в одном из них — на диктовке
> длиннее 30 сек пропадали слова. Сами метки в текст не попадают: bridge собирает
> сегменты через `whisper_full_get_segment_text` при `print_special = false`.

### Выбор модели Whisper

| Модель | Размер | Скорость (M2 Pro) | Качество RU | Качество EN |
|---|---|---|---|---|
| tiny | 75 MB | ~0.5 сек | ★★☆☆☆ | ★★★☆☆ |
| base | 142 MB | ~0.8 сек | ★★★☆☆ | ★★★★☆ |
| **small** | **465 MB** | **~2-3 сек** | **★★★★☆** | **★★★★★** |
| medium | 1.5 GB | ~6-8 сек | ★★★★★ | ★★★★★ |
| large | 3 GB | ~15 сек | ★★★★★ | ★★★★★ |

**Выбор для v1: `ggml-small.bin`** — оптимальный баланс скорости и качества для личного инструмента. На Intel Mac рекомендуется `ggml-base.bin` (меньше время инференса без Metal).

**Источник модели:** Hugging Face — `ggerganov/whisper.cpp` репозиторий предоставляет готовые `.bin` файлы.

---

## 3. Глобальный хоткей: CGEventTap

### Почему не Carbon `RegisterEventHotKey`

- Carbon API устарел (deprecated in macOS 12, но работает)
- Не умеет различать key-down от key-hold для push-to-talk
- Требует постоянный event loop в main thread
- Не позволяет модифицировать или отменять события

### Почему CGEventTap

```
Поток HID событий:
  Клавиатура → IOKit → CGEventTap (наш) → EventQueue → Приложение
```

- Перехватывает события ДО их доставки в приложение
- Чистые `keyDown` и `keyUp` события (не только hotkey-combo)
- Работает из любого состояния системы
- Не требует фокуса нашего приложения
- Tap level: `.cgSessionEventTap` — уровень сессии пользователя

**Дефолтный хоткей:** Right Option (keyCode 61) — не конфликтует с системными shortcuts, удобно удерживать большим пальцем.

---

## 4. Захват аудио: AVAudioEngine

### Почему не AVAudioRecorder

- `AVAudioRecorder` пишет файл; нет доступа к real-time буферу PCM
- Нельзя конвертировать формат "на лету"

### Почему не CoreAudio HAL напрямую

- Требует ~200 строк C-кода (AudioComponent, AudioUnit, callbacks)
- `AVAudioEngine` является обёрткой над CoreAudio — те же возможности, меньше кода

### Pipeline

```
Микрофон (любая частота дискретизации, напр. 48kHz стерео)
    │ installTapOnBus
    ▼
AVAudioConverter
    │ hardware format → 16,000 Hz / 1 ch / Float32
    ▼
Ring buffer (pre-allocated [Float32])
    │ копирование в tap callback (lock-free)
    ▼
[Float32] массив → передаётся в whisper.cpp
```

---

## 5. Инжект текста: двойная стратегия

### Стратегия 1: AXUIElement (приоритет)

```
AXUIElementCreateApplication(pid)
    └─► kAXFocusedUIElementAttribute → focused element
          └─► kAXSelectedTextAttribute = наш текст
                (вставляет в позицию каретки, заменяет выделение)
```

**Работает в:** TextEdit, Notes, Xcode, Pages, Mail, Safari URL bar, большинство нативных AppKit/SwiftUI полей.

### Стратегия 2: Pasteboard + Cmd+V (fallback)

```
1. Сохранить NSPasteboard.general.string(forType: .string)
2. NSPasteboard.setString(нашТекст)
3. CGEvent keyDown(Cmd+V) → post(tap: .cghidEventTap)
4. CGEvent keyUp(Cmd+V)   → post(tap: .cghidEventTap)
5. Task.sleep(300ms)
6. Восстановить буфер обмена
```

**Работает в:** Chrome, Electron (VS Code, Notion app, Discord), Terminal, iTerm2, веб-формы.

**Не работает в:** Password fields (намеренно заблокировано macOS).

---

## 6. Системные фреймворки

| Фреймворк | Используется для |
|---|---|
| `AVFoundation` / `AVFAudio` | `AVAudioEngine`, `AVAudioConverter`, `AVAudioPCMBuffer` |
| `CoreGraphics` | `CGEventTap` (глобальный хоткей), синтетические Cmd+V события |
| `ApplicationServices` | `AXUIElement`, `AXUIElementCreateApplication` (текст инжект) |
| `AppKit` | `NSStatusItem`, `NSPanel`, `NSPasteboard`, `NSSound`, `NSWorkspace` |
| `SwiftUI` | Overlay view, Settings sheet, History popover |
| `Metal` / `MetalKit` | Ускорение ggml (whisper.cpp) на Apple Silicon |
| `Accelerate` | BLAS/vDSP операции в ggml |
| `CoreML` | Опциональное CoreML ускорение whisper (Milestone 5) |
| `ServiceManagement` | `SMAppService.mainApp.register()` (автозапуск при входе) |
| `UserNotifications` | Системные уведомления при ошибках (Milestone 5) |
| `Foundation` | `URLSession` (скачивание модели), `UserDefaults`, `JSONEncoder` |

---

## 7. Внешние зависимости

**Политика:** Ноль внешних SPM зависимостей. Только:
1. Локальный пакет `Packages/CWhisper/` (vendored C-код)
2. Системные фреймворки Apple (нет внешних)

**Обоснование:**
- Нет проблем supply-chain безопасности
- Нет network fetches при `swift package resolve`
- Проект полностью автономен (работает офлайн после скачивания модели)
- Никаких breaking changes из-за обновлений зависимостей

---

## 8. Сборка и дистрибуция

- **Xcode** 15.0+ (или 16.0+ для macOS 14 target)
- **App Sandbox**: отключён (см. [permissions.md](permissions.md))
- **Подпись**: Developer ID Application (для распространения за пределами App Store)
- **Дистрибуция**: прямой `.dmg` / zip, через GitHub Releases
- **Нотаризация**: потребуется для Gatekeeper (xcrun notarytool)

> Для личного использования: достаточно подписи Developer ID или запуска без подписи (с разрешением в System Settings > Privacy & Security).
