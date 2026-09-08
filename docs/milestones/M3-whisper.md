# M3 — Интеграция whisper.cpp

**Цель:** Транскрибировать захваченное аудио локально через whisper.cpp с Metal ускорением. Результат — строка текста в консоли. Поддержка русского и английского языков без ручной настройки.

**Оценка:** 3-4 рабочих дня (самый сложный этап)
**Зависимости:** M2 завершён (AudioRecorder возвращает `[Float]`)
**Критерий готовности:** "Hello, world" → "hello, world" в консоли; "Привет, мир" → "Привет, мир" — оба без изменения настроек

---

## Задачи

### 1. Получение исходников whisper.cpp

Скачать или клонировать конкретный тег (не latest — для воспроизводимости):

```bash
# Вариант A: клонировать
git clone --depth 1 --branch v1.7.4 https://github.com/ggerganov/whisper.cpp
cd whisper.cpp

# Вариант B: скачать архив релиза
# https://github.com/ggerganov/whisper.cpp/releases/tag/v1.7.4
```

Необходимые файлы для копирования в `Packages/CWhisper/Sources/CWhisper/`:

| Файл | Откуда в репозитории |
|---|---|
| `whisper.cpp` | `src/whisper.cpp` или корень |
| `whisper.h` | `include/whisper.h` |
| `ggml.c` | `ggml/src/ggml.c` |
| `ggml.h` | `ggml/include/ggml.h` |
| `ggml-alloc.c` | `ggml/src/ggml-alloc.c` |
| `ggml-alloc.h` | `ggml/include/ggml-alloc.h` |
| `ggml-backend.cpp` | `ggml/src/ggml-backend.cpp` |
| `ggml-backend.h` | `ggml/include/ggml-backend.h` |
| `ggml-quants.c` | `ggml/src/ggml-quants.c` |
| `ggml-quants.h` | `ggml/include/ggml-quants.h` |
| `ggml-metal.m` | `ggml/src/ggml-metal.m` |
| `ggml-metal.metal` | `ggml/src/ggml-metal.metal` |

> **Внимание:** Структура репозитория whisper.cpp меняется между версиями. Для v1.7.x `ggml` вынесен в подпапку. Проверяйте актуальные пути в репозитории.

### 2. whisper_bridge.h — C API для Swift

```c
// Packages/CWhisper/Sources/CWhisper/include/whisper_bridge.h
#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque указатель на whisper_context (C++ объект, скрыт от Swift)
typedef struct whisper_context whisper_context;

// Параметры транскрипции
typedef struct {
    int     n_threads;      // Количество потоков CPU (рекомендуется: ProcessorCount)
    int     language;       // -1 = авто-определение, иначе индекс языка whisper
    bool    translate;      // Переводить на английский (false для нас)
    bool    no_timestamps;  // true = не добавлять временные метки в вывод
    float   temperature;    // 0.0 = детерминированный, 1.0 = случайный
} SayVoiceWhisperParams;

// Lifecycle модели
whisper_context* whisper_bridge_init(const char* model_path);
void             whisper_bridge_free(whisper_context* ctx);

// Транскрипция
// Возвращает heap-строку (UTF-8). Освободить через whisper_bridge_free_string().
// Возвращает NULL при ошибке.
char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,     // PCM Float32 @ 16kHz mono, [-1.0, 1.0]
    int32_t               n_samples,
    SayVoiceWhisperParams params
);
void whisper_bridge_free_string(char* str);

#ifdef __cplusplus
}
#endif
```

### 3. whisper_bridge.cpp — реализация C-моста

```cpp
// Packages/CWhisper/Sources/CWhisper/whisper_bridge.cpp
// Этот файл компилируется как C++ и связывает C API с whisper.cpp API

#include "include/whisper_bridge.h"
#include "whisper.h"    // whisper.cpp public API
#include <cstring>
#include <string>

whisper_context* whisper_bridge_init(const char* model_path) {
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = true;   // включить Metal GPU
    return whisper_init_from_file_with_params(model_path, params);
}

void whisper_bridge_free(whisper_context* ctx) {
    if (ctx) whisper_free(ctx);
}

char* whisper_bridge_transcribe(
    whisper_context*      ctx,
    const float*          samples,
    int32_t               n_samples,
    SayVoiceWhisperParams bridge_params
) {
    if (!ctx || !samples || n_samples <= 0) return nullptr;

    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads        = bridge_params.n_threads;
    params.translate        = bridge_params.translate;
    params.no_timestamps    = bridge_params.no_timestamps;
    params.temperature      = bridge_params.temperature;
    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.single_segment   = false;

    // Установка языка
    if (bridge_params.language == -1) {
        params.language = "auto";
    } else {
        // Для упрощения: auto всегда (расширить в M5)
        params.language = "auto";
    }

    int result = whisper_full(ctx, params, samples, n_samples);
    if (result != 0) return nullptr;

    // Собираем все сегменты в одну строку
    std::string output;
    const int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            if (!output.empty() && output.back() != ' ') output += " ";
            output += text;
        }
    }

    // Trim whitespace
    size_t start = output.find_first_not_of(" \t\n\r");
    size_t end   = output.find_last_not_of(" \t\n\r");
    if (start == std::string::npos) return nullptr;
    output = output.substr(start, end - start + 1);

    if (output.empty()) return nullptr;

    // Возвращаем heap-строку (Swift освободит через whisper_bridge_free_string)
    char* cstr = new char[output.size() + 1];
    std::strcpy(cstr, output.c_str());
    return cstr;
}

void whisper_bridge_free_string(char* str) {
    delete[] str;
}
```

### 4. Package.swift для CWhisper

```swift
// Packages/CWhisper/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CWhisper",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperSwift", targets: ["WhisperSwift"])
    ],
    targets: [
        // C/C++/ObjC target — whisper.cpp + ggml
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include",
            cSettings: [
                .define("GGML_USE_METAL"),
                .define("NDEBUG"),
                .headerSearchPath("."),  // для include "whisper.h" внутри .cpp файлов
                .unsafeFlags(["-O3"])
            ],
            cxxSettings: [
                .define("GGML_USE_METAL"),
                .unsafeFlags(["-O3", "-std=c++17"])
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreML")
            ]
        ),
        // Swift обёртка
        .target(
            name: "WhisperSwift",
            dependencies: ["CWhisper"],
            path: "Sources/WhisperSwift"
        )
    ],
    cxxLanguageStandard: .cxx17
)
```

### 5. WhisperError.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperError.swift
import Foundation

enum WhisperError: Error, LocalizedError {
    case modelLoadFailed(String)    // путь к модели
    case transcriptionFailed
    case invalidSampleCount(Int)    // получено сэмплов
    case contextIsNil

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Не удалось загрузить модель: \(path)"
        case .transcriptionFailed:       return "Транскрипция не удалась"
        case .invalidSampleCount(let n): return "Некорректное количество сэмплов: \(n)"
        case .contextIsNil:              return "Whisper context не инициализирован"
        }
    }
}
```

### 6. WhisperContext.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperContext.swift
import Foundation
import CWhisper

/// Actor изолирует доступ к C-указателю whisper_context*.
/// Инференс НЕ на MainActor — не блокирует UI.
actor WhisperContext {
    private var ctx: OpaquePointer?

    /// Инициализация из файла модели. Выполняется ~1-5 сек (загрузка в память + Metal компиляция).
    init(modelURL: URL) throws {
        let path = modelURL.path
        guard let context = whisper_bridge_init(path) else {
            throw WhisperError.modelLoadFailed(path)
        }
        self.ctx = OpaquePointer(context)
    }

    /// Транскрипция [Float32] в String.
    /// Вызов блокирует actor executor на время инференса (~2-10 сек).
    func transcribe(samples: [Float], language: String = "auto") throws -> String {
        guard let ctx = self.ctx else {
            throw WhisperError.contextIsNil
        }

        guard samples.count > 0 else {
            throw WhisperError.invalidSampleCount(samples.count)
        }

        let params = SayVoiceWhisperParams(
            n_threads: Int32(ProcessInfo.processInfo.processorCount),
            language: -1,       // авто-определение
            translate: false,
            no_timestamps: true,
            temperature: 0.0
        )

        guard let rawResult = samples.withUnsafeBufferPointer({ ptr in
            whisper_bridge_transcribe(
                UnsafeMutablePointer(mutating: OpaquePointer(ctx) as UnsafePointer<whisper_context>),
                ptr.baseAddress,
                Int32(samples.count),
                params
            )
        }) else {
            throw WhisperError.transcriptionFailed
        }

        defer { whisper_bridge_free_string(rawResult) }
        let result = String(cString: rawResult)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
        if let ctx = ctx {
            whisper_bridge_free(UnsafeMutablePointer(mutating: OpaquePointer(ctx) as UnsafePointer<whisper_context>))
        }
    }
}
```

> **Примечание:** Приведение типов `OpaquePointer ↔ UnsafeMutablePointer<whisper_context>` требует аккуратности из-за C opaque структур. Точный код зависит от финального API whisper_bridge.h.

### 7. WhisperTranscriber.swift

```swift
// Packages/CWhisper/Sources/WhisperSwift/WhisperTranscriber.swift
import Foundation

/// Высокоуровневый интерфейс над WhisperContext
public final class WhisperTranscriber {
    private let context: WhisperContext

    public init(modelURL: URL) async throws {
        self.context = try await WhisperContext(modelURL: modelURL)
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        try await context.transcribe(samples: samples)
    }
}
```

### 8. TranscriptionError.swift (основной таргет)

```swift
// SayVoice/Transcription/TranscriptionError.swift
import Foundation

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(URL)
    case inferenceError(Error)
    case emptyResult
    case timeout
    case recordingTooShort(Int)     // sample count

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:         return "Модель не загружена. Скачайте в настройках."
        case .modelLoadFailed(let u): return "Не удалось загрузить модель: \(u.lastPathComponent)"
        case .inferenceError(let e):  return "Ошибка транскрипции: \(e.localizedDescription)"
        case .emptyResult:            return "Не услышал ничего"
        case .timeout:                return "Превышено время транскрипции"
        case .recordingTooShort:      return ""   // тихо игнорировать
        }
    }
}
```

### 9. ModelManager.swift

```swift
// SayVoice/ModelManagement/ModelManager.swift
import Foundation

@MainActor
final class ModelManager: ObservableObject {

    enum ModelSize: String, CaseIterable {
        case tiny  = "ggml-tiny"
        case base  = "ggml-base"
        case small = "ggml-small"

        var fileSize: String {
            switch self {
            case .tiny:  return "75 MB"
            case .base:  return "142 MB"
            case .small: return "465 MB"
            }
        }

        var fileName: String { "\(rawValue).bin" }

        // Hugging Face direct download URL (ggerganov/whisper.cpp репозиторий)
        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }
    }

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SayVoice/Models")
    }()

    func modelURL(for size: ModelSize) -> URL {
        Self.modelsDirectory.appendingPathComponent(size.fileName)
    }

    func isModelAvailable(_ size: ModelSize) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: size).path)
    }

    func downloadModel(_ size: ModelSize) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try FileManager.default.createDirectory(
                        at: Self.modelsDirectory,
                        withIntermediateDirectories: true
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(from: size.downloadURL)
                    let totalBytes = response.expectedContentLength

                    let tempURL = Self.modelsDirectory.appendingPathComponent(size.fileName + ".tmp")
                    guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
                        throw URLError(.cannotCreateFile)
                    }

                    let handle = try FileHandle(forWritingTo: tempURL)
                    defer { try? handle.close() }

                    var downloadedBytes: Int64 = 0
                    var chunk = Data()
                    chunk.reserveCapacity(65536)

                    for try await byte in bytes {
                        chunk.append(byte)
                        downloadedBytes += 1

                        if chunk.count >= 65536 {
                            try handle.write(contentsOf: chunk)
                            chunk.removeAll(keepingCapacity: true)

                            if totalBytes > 0 {
                                let progress = Double(downloadedBytes) / Double(totalBytes)
                                continuation.yield(progress)
                            }
                        }
                    }

                    if !chunk.isEmpty {
                        try handle.write(contentsOf: chunk)
                    }

                    // Атомарное перемещение из temp в финальное место
                    let finalURL = Self.modelsDirectory.appendingPathComponent(size.fileName)
                    _ = try? FileManager.default.removeItem(at: finalURL)
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)

                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

### 10. TranscriptionEngine.swift

```swift
// SayVoice/Transcription/TranscriptionEngine.swift
import Foundation
import WhisperSwift

actor TranscriptionEngine {
    private var transcriber: WhisperTranscriber?
    private let modelManager: ModelManager
    private let modelSize: ModelManager.ModelSize

    static let minimumSampleCount = 4800   // 0.3 сек @ 16kHz

    init(modelManager: ModelManager, modelSize: ModelManager.ModelSize = .small) {
        self.modelManager = modelManager
        self.modelSize = modelSize
    }

    func ensureLoaded() async throws {
        guard transcriber == nil else { return }

        let modelURL = await modelManager.modelURL(for: modelSize)
        guard await modelManager.isModelAvailable(modelSize) else {
            throw TranscriptionError.modelNotLoaded
        }

        transcriber = try await WhisperTranscriber(modelURL: modelURL)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard samples.count >= Self.minimumSampleCount else {
            throw TranscriptionError.recordingTooShort(samples.count)
        }

        try await ensureLoaded()

        guard let transcriber else {
            throw TranscriptionError.modelNotLoaded
        }

        // Таймаут 15 сек
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await transcriber.transcribe(samples)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw TranscriptionError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()

            if result.isEmpty {
                throw TranscriptionError.emptyResult
            }
            return result
        }
    }
}
```

### 11. Подключение к AppCoordinator (обновление для M3)

```swift
// Добавить в AppCoordinator:
private let modelManager = ModelManager()
private lazy var transcriptionEngine = TranscriptionEngine(modelManager: modelManager)

// Обновить handleKeyUp():
func handleKeyUp() {
    guard state == .recording else { return }
    state = .transcribing

    Task {
        let samples = await audioRecorder.stopCapture()

        do {
            let text = try await transcriptionEngine.transcribe(samples)
            print("✅ Transcription: \(text)")
            overlayController?.show(message: text)
            overlayController?.dismiss(after: 2.0)
            state = .idle

        } catch TranscriptionError.recordingTooShort {
            state = .idle  // тихо

        } catch TranscriptionError.modelNotLoaded {
            // TODO: показать ModelDownloadView
            state = .error(.modelNotLoaded)

        } catch TranscriptionError.emptyResult {
            state = .error(.transcriptionFailed("Не услышал ничего"))

        } catch {
            state = .error(.transcriptionFailed(error.localizedDescription))
        }
    }
}
```

---

## Типичные ошибки компиляции и решения

### "C++ header 'xxx.h' cannot be included in a Swift bridging header"

**Причина:** Swift не может напрямую импортировать C++ заголовки.
**Решение:** `whisper_bridge.h` должен быть **чистым C** (`extern "C"`, без `std::`, без `namespace`). whisper.h включается только в `.cpp` файлы.

### "symbol not found: _whisper_init_from_file"

**Причина:** SPM C target не компилирует `.cpp` файлы.
**Решение:** Убедиться что `whisper.cpp` и `ggml.c` находятся в папке `Sources/CWhisper/` (не в подпапках). SPM автоматически компилирует все `.c`, `.cpp`, `.m` файлы в таргете.

### Metal шейдеры не компилируются

**Причина:** `ggml-metal.metal` нужно включить в таргет как ресурс.
**Решение в Package.swift:**
```swift
resources: [.process("ggml-metal.metal")]
```

### "Use of undeclared type 'ggml_type'"

**Причина:** `whisper.cpp` включает `ggml.h`, но путь не найден.
**Решение:** Добавить в `cSettings`:
```swift
.headerSearchPath(".")  // чтобы "ggml.h" находился относительно CWhisper/
```

### Очень медленный инференс (>20 сек)

**Причина:** Metal GPU не используется (ggml собирается без флага).
**Решение:** Убедиться что `GGML_USE_METAL` определён в cSettings/cxxSettings. Проверить в консоли: whisper.cpp должен печатать `ggml_metal_init: device=Apple M1...`.

---

## Скачивание модели при первом запуске

Последовательность:
1. `TranscriptionEngine.ensureLoaded()` → `ModelManager.isModelAvailable(.small)` → false
2. Кидает `TranscriptionError.modelNotLoaded`
3. `AppCoordinator` перехватывает → показывает `ModelDownloadView` в popover/sheet
4. Пользователь нажимает "Скачать" → `ModelManager.downloadModel(.small)` с прогрессом
5. По завершении: повторный вызов `transcriptionEngine.ensureLoaded()` загружает модель

---

## Критерии готовности M3

- [x] Проект компилируется с `Packages/CWhisper/` без ошибок — **0 errors, 0 warnings**
- [x] Консоль при старте: `ggml_metal_init: device=Apple M3 Pro` (Metal активен, GPU)
- [x] Первый запуск: открывается экран скачивания модели — **ModelDownloadView автоматически при отсутствии модели**
- [x] После скачивания: model file существует в `~/Library/Application Support/SayVoice/Models/ggml-small.bin`
- [x] Сказать "Hello" → консоль: `[SayVoice] Transcription: Hello.` — **авто-определение EN работает**
- [x] Сказать "Привет" → консоль: `[SayVoice] Transcription: Привет.` — **авто-определение RU (p=0.846)**
- [x] Смешанная речь → авто-определение: `params.language = "auto"` корректно выбирает язык сегмента
- [x] Тишина / <0.3 сек → `recordingTooShort` без краша (порог 4800 сэмплов = 0.3 сек)
- [x] Повторная запись сразу после первой работает (модель загружается один раз, хранится в actor)

**Дата завершения: 2026-02-25**

---

## Заметки по реализации (отличия от плана)

### whisper.cpp v1.7.4 — финальная конфигурация

1. **Metal шейдер**: `GGML_METAL_EMBED_LIBRARY` — шейдер препроцессирован (inline ggml-common.h + ggml-metal-impl.h) и встроен как C-массив в `ggml-metal-embed.c`. Не используем `.process()` ресурсы SPM.

2. **Заголовки разделены на два каталога:**
   - `include/` — только `whisper_bridge.h` (publicHeadersPath, виден из Swift)
   - `ggml-headers/` — whisper.h, ggml.h, ggml-alloc.h и пр. (внутренние, только C/C++)

3. **Package.swift ключевые флаги:**
   - `-fno-objc-arc` — ggml-metal.m использует manual reference counting
   - `-Wno-ambiguous-macro` — MIN/MAX macro redefinition в ggml
   - `GGML_USE_ACCELERATE`, `ACCELERATE_NEW_LAPACK`, `ACCELERATE_LAPACK_ILP64`
   - `GGML_METAL_EMBED_LIBRARY` вместо runtime .metal loading

4. **OpaquePointer**: `whisper_context` — forward-declared C struct → Swift импортирует как `OpaquePointer`. Прямое присвоение `self.ctx = context`, без двойной конверсии.

5. **params.language = "auto"** (строка, не int -1 как в первоначальном плане) — whisper.cpp API принимает строку.

6. **Кастомный log callback** (`sayvoice_log_callback`): фильтрует вывод whisper.cpp/ggml — только ошибки + ключевые диагностические строки (GPU name, model size, auto-detected language). Убраны сотни строк шума.

7. **ggml-metal.m патч**: `#if GGML_METAL_EMBED_LIBRARY → [NSBundle mainBundle]` вместо `SWIFTPM_MODULE_BUNDLE` (которого нет без ресурсов). Также silenced "skipping kernel" warnings для bf16 ядер.

### Тестовая фраза

```
"Раз, два, три. Проверка связи. Меня зовут Алекс."
```
Транскрипция корректна, Metal GPU активен, время инференса ~2-3 сек на Apple M3 Pro.
