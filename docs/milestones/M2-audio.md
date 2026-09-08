# M2 — Захват аудио ✅ ЗАВЕРШЁН

**Цель:** Захватить PCM аудио с микрофона во время нажатого хоткея. Конвертировать в формат whisper.cpp: 16kHz, mono, Float32. Убедиться в корректности данных через сохранение отладочного WAV-файла.

**Оценка:** 1-2 рабочих дня
**Зависимости:** M1 завершён (AppCoordinator, HotkeyListener работают)
**Статус:** Завершён

---

## Созданные файлы

### SayVoice/Permissions/PermissionManager.swift
- `@MainActor final class PermissionManager`
- Микрофон: `AVAudioApplication.requestRecordPermission()`
- Accessibility: `AXIsProcessTrustedWithOptions` с литералом `"AXTrustedCheckOptionPrompt"` (macOS 26 concurrency-safe)
- Методы открытия System Settings для обоих разрешений

### SayVoice/Audio/AudioError.swift
- `enum AudioError: Error, LocalizedError`
- Кейсы: `engineStartFailed`, `formatConversionFailed`, `permissionDenied`, `noAudioInput`, `tapAlreadyInstalled`

### SayVoice/Audio/AudioConverter.swift
- `final class AudioConverter: @unchecked Sendable`
- Конвертация из любого формата микрофона → 16kHz mono Float32 через `AVAudioConverter`
- **RC high-pass фильтр (80 Hz cutoff)** — убирает DC offset, гул вентилятора, 50/60 Hz от сети
- `@unchecked Sendable` — используется последовательно из audio tap callback

### SayVoice/Audio/AudioRecorder.swift
- `actor AudioRecorder` — потокобезопасное накопление PCM буфера
- `startCapture()` → `installTap(onBus:)` + `engine.start()`
- `stopCapture() -> [Float]` → `removeTap(onBus:)` + `engine.stop()` + возврат буфера
- `nonisolated appendBufferSync` — конвертация на audio thread, запись через `Task { await self.append() }`
- Логирование входного формата микрофона при старте

## Изменённые файлы

### SayVoice/App/AppCoordinator.swift
- Добавлены `permissionManager`, `audioRecorder`
- `handleKeyDown()` → `audioRecorder.startCapture()`
- `handleKeyUp()` → `audioRecorder.stopCapture()` + логирование peak/RMS + debug WAV
- **Accessibility fix**: `tccutil reset` для очистки stale TCC entries после ребилда (ad-hoc signing)
- Polling с `prompt: false` для ожидания гранта
- Debug WAV: ручная запись RIFF/WAV (44-byte header + Int16 PCM), пиковая нормализация (gain до 0.95)

### SayVoice/HotkeyListener/HotkeyListener.swift
- Добавлен параметр `start(prompt:)` — контролирует показ системного диалога
- Guard `if eventTap != nil { return }` — защита от двойного tap

---

## Проблемы и решения

### 1. Accessibility постоянно сбрасывается
**Симптом:** `AXIsProcessTrusted` возвращает `false` даже при включённом тоггле в System Settings.
**Причина:** Ad-hoc code signing (`CODE_SIGN_IDENTITY: "-"`) — каждый ребилд создаёт новую сигнатуру, TCC database хранит старый хэш.
**Решение:** `tccutil reset Accessibility com.sayvoice.app` перед запросом — удаляет stale entry, macOS создаёт свежую для текущего бинарника.

### 2. Debug WAV не воспроизводится (Float32)
**Симптом:** Quick Look / QuickTime Player показывают ошибку или играют тихо.
**Причина:** Float32 WAV плохо поддерживается стандартными плеерами macOS.
**Решение:** Ручная запись Int16 PCM WAV через `Data.write(to:)`, без AVAudioFile.

### 3. AVAudioFile crash на Int16 буферах
**Симптом:** `EXC_BREAKPOINT` на `file.write(from: buffer)`, ошибка -10877.
**Причина:** AVAudioFile не поддерживает запись Int16 `AVAudioPCMBuffer` напрямую.
**Решение:** Полностью обойти AVAudioFile — писать WAV руками (RIFF header + raw bytes).

### 4. Тихая запись
**Симптом:** Peak ~0.013, RMS ~0.001 — встроенный MacBook микрофон пишет тихо.
**Решение:** Пиковая нормализация до 0.95 в debug WAV. Для whisper.cpp нормализация не нужна — он работает с любым уровнем.

---

## Технические детали

### Формат аудио для whisper.cpp
- Sample rate: **16,000 Hz**
- Channels: **1 (mono)**
- Format: **PCM Float32**, диапазон [-1.0, 1.0]

### Real-time audio thread
`installTap(onBus:)` вызывает callback с реал-тайм приоритетом. Конвертация + `Task{}` допустимы для личного инструмента. Для production — использовать lock-free ring buffer.

### AVAudioEngine lifecycle
`engine.stop()` **не удаляет** tap. Нужно `removeTap(onBus: 0)` перед `stop()`.

---

## Адаптация под macOS 26 (Tahoe)

### Переименованные API AVAudioNode
- `installTapOnBus(_:bufferSize:format:block:)` → `installTap(onBus:bufferSize:format:block:)`
- `removeTapOnBus(_:)` → `removeTap(onBus:)`

### Swift 6 Strict Concurrency
- `AudioConverter` — `@unchecked Sendable` (последовательный вызов с audio thread)
- `PermissionManager` — строковый литерал `"AXTrustedCheckOptionPrompt"` вместо `kAXTrustedCheckOptionPrompt`

---

## Критерии готовности M2

- [x] Нажать хоткей → микрофон активен
- [x] Отпустить → консоль: `[SayVoice] Captured X samples (Y.Z sec)`
- [x] `samples.count > 0` при записи > 0.5 сек
- [x] Debug WAV сохраняется на Desktop и воспроизводится корректно (речь разборчива)
- [x] Повторная запись работает без ошибок
- [x] Отказ в разрешении → graceful error, нет краша
- [x] Память не растёт с каждой записью (буфер очищается после stopCapture)
- [x] High-pass фильтр убирает низкочастотный шум
