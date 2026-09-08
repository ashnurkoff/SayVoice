# M5 — Полировка

**Цель:** Feature-complete v1.0, приятный в ежедневном использовании. Настройки, история транскрипций, звуковая обратная связь, онбординг, обработка ошибок.

**Оценка:** 3-5 рабочих дней
**Зависимости:** M4 завершён (полный pipeline работает)
**Критерий готовности:** Приложение можно использовать ежедневно без открытия Xcode

---

## 5a — Настройки

### SettingsKeys.swift

```swift
// SayVoice/Settings/SettingsKeys.swift
enum SettingsKeys {
    static let hotkeyCode     = "sv_hotkey_code"
    static let modelSize      = "sv_model_size"
    static let language       = "sv_language"
    static let overlayEnabled = "sv_overlay_enabled"
    static let soundFeedback  = "sv_sound_feedback"
    static let pasteMethod    = "sv_paste_method"
    static let launchAtLogin  = "sv_launch_at_login"
    static let hasCompletedOnboarding = "sv_onboarding_done"
}
```

### SettingsStore.swift

```swift
// SayVoice/Settings/SettingsStore.swift
import Foundation
import Observation

@Observable
final class SettingsStore {

    // Хоткей (keyCode + modifiers)
    var hotkeyCode: Int {
        didSet { UserDefaults.standard.set(hotkeyCode, forKey: SettingsKeys.hotkeyCode) }
    }

    // Модель: "tiny" | "base" | "small"
    var modelSize: String {
        didSet { UserDefaults.standard.set(modelSize, forKey: SettingsKeys.modelSize) }
    }

    // Язык: "auto" | "ru" | "en"
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: SettingsKeys.language) }
    }

    var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: SettingsKeys.overlayEnabled) }
    }

    var soundFeedback: Bool {
        didSet { UserDefaults.standard.set(soundFeedback, forKey: SettingsKeys.soundFeedback) }
    }

    // "auto" | "ax" | "pasteboard"
    var pasteMethod: String {
        didSet { UserDefaults.standard.set(pasteMethod, forKey: SettingsKeys.pasteMethod) }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: SettingsKeys.hasCompletedOnboarding) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.hotkeyCode     = defaults.object(forKey: SettingsKeys.hotkeyCode) as? Int ?? 61
        self.modelSize      = defaults.string(forKey: SettingsKeys.modelSize) ?? "small"
        self.language       = defaults.string(forKey: SettingsKeys.language) ?? "auto"
        self.overlayEnabled = defaults.object(forKey: SettingsKeys.overlayEnabled) as? Bool ?? true
        self.soundFeedback  = defaults.object(forKey: SettingsKeys.soundFeedback) as? Bool ?? true
        self.pasteMethod    = defaults.string(forKey: SettingsKeys.pasteMethod) ?? "auto"
        self.launchAtLogin  = defaults.bool(forKey: SettingsKeys.launchAtLogin)
        self.hasCompletedOnboarding = defaults.bool(forKey: SettingsKeys.hasCompletedOnboarding)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        // SMAppService (macOS 13+)
        // import ServiceManagement
        // if enabled {
        //     try? SMAppService.mainApp.register()
        // } else {
        //     try? SMAppService.mainApp.unregister()
        // }
    }
}
```

### SettingsView.swift

```swift
// SayVoice/UI/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var isRecordingHotkey = false

    var body: some View {
        Form {
            // MARK: - Хоткей
            Section("Хоткей") {
                LabeledContent("Хоткей записи") {
                    Button(hotkeyLabel) {
                        isRecordingHotkey.toggle()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(isRecordingHotkey ? .red : .primary)
                }

                if isRecordingHotkey {
                    Text("Нажмите клавишу для назначения...")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            // MARK: - Модель
            Section("Модель распознавания") {
                Picker("Модель", selection: Binding(
                    get: { settings.modelSize },
                    set: { settings.modelSize = $0 }
                )) {
                    Text("Tiny (75 MB, быстрая, менее точная)").tag("tiny")
                    Text("Base (142 MB, баланс)").tag("base")
                    Text("Small (465 MB, рекомендуется)").tag("small")
                }
                .pickerStyle(.radioGroup)

                Text("Модели хранятся в ~/Library/Application Support/SayVoice/Models/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Язык
            Section("Язык распознавания") {
                Picker("Язык", selection: Binding(
                    get: { settings.language },
                    set: { settings.language = $0 }
                )) {
                    Text("Авто (определяется автоматически)").tag("auto")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .pickerStyle(.radioGroup)
            }

            // MARK: - Интерфейс
            Section("Интерфейс") {
                Toggle("Показывать overlay при записи", isOn: Binding(
                    get: { settings.overlayEnabled },
                    set: { settings.overlayEnabled = $0 }
                ))

                Toggle("Звуковая обратная связь", isOn: Binding(
                    get: { settings.soundFeedback },
                    set: { settings.soundFeedback = $0 }
                ))
            }

            // MARK: - Вставка
            Section("Метод вставки текста") {
                Picker("Метод", selection: Binding(
                    get: { settings.pasteMethod },
                    set: { settings.pasteMethod = $0 }
                )) {
                    Text("Авто (AX → Буфер обмена)").tag("auto")
                    Text("Только AX (нативные приложения)").tag("ax")
                    Text("Только буфер обмена (универсальный)").tag("pasteboard")
                }
                .pickerStyle(.radioGroup)
            }

            // MARK: - Система
            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 500)
    }

    private var hotkeyLabel: String {
        // В M5 реализовать красивое отображение keyCode как символа клавиши
        settings.hotkeyCode == 61 ? "⌥ Right Option" : "KeyCode: \(settings.hotkeyCode)"
    }
}
```

---

## 5b — История транскрипций

### TranscriptionEntry.swift

```swift
// SayVoice/History/TranscriptionEntry.swift
import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    let language: String?       // "ru", "en", nil = неизвестно
}
```

### TranscriptionHistoryStore.swift

```swift
// SayVoice/History/TranscriptionHistoryStore.swift
import Foundation
import Observation

@Observable
final class TranscriptionHistoryStore {
    private(set) var entries: [TranscriptionEntry] = []
    private let maxEntries = 500

    private static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SayVoice/history.json")
    }

    init() {
        load()
    }

    func append(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)   // новые сверху
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func recent(_ count: Int = 10) -> [TranscriptionEntry] {
        Array(entries.prefix(count))
    }

    private func save() {
        do {
            let dir = Self.storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("⚠️ History save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.storageURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            print("⚠️ History load failed: \(error)")
            entries = []
        }
    }
}
```

### MenuBarPopoverView.swift

```swift
// SayVoice/UI/MenuBarPopoverView.swift
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(TranscriptionHistoryStore.self) private var history
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Заголовок
            HStack {
                Label("SayVoice", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // История транскрипций
            if history.entries.isEmpty {
                VStack {
                    Text("Нет записей")
                        .foregroundStyle(.secondary)
                    Text("Зажмите ⌥ Right Option для записи")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.recent(10)) { entry in
                            HistoryRowView(entry: entry)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Нижняя панель
            HStack {
                if !history.entries.isEmpty {
                    Button("Очистить историю") {
                        history.clear()
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                Spacer()
                Button("Настройки...") {
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }
}

struct HistoryRowView: View {
    let entry: TranscriptionEntry
    @State private var copied = false

    var body: some View {
        Button(action: copyToClipboard) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    Text(entry.date, style: .relative) +
                    Text(" · \(entry.durationSeconds, format: .number.precision(.fractionLength(1)))с")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
```

---

## 5c — Звуковая обратная связь

```swift
// Добавить в AppCoordinator:
import AppKit

private func playStartSound() {
    guard settingsStore.soundFeedback else { return }
    NSSound(named: NSSound.Name("Tink"))?.play()
}

private func playStopSound() {
    guard settingsStore.soundFeedback else { return }
    NSSound(named: NSSound.Name("Pop"))?.play()
}

// Вызывать в handleStateChange:
case .recording:
    playStartSound()
    // ...

case .idle where oldState == .injecting:
    playStopSound()
    // ...
```

**Стандартные системные звуки macOS:**
- `Tink` — тихий клик (старт записи)
- `Pop` — мягкий хлопок (завершение)
- `Purr` — мурчание (успех)
- `Basso` — низкий звук (ошибка)

---

## 5d — Обработка ошибок

### Таймаут транскрипции

Уже реализован в `TranscriptionEngine` через `withThrowingTaskGroup` — 15 сек timeout.

### Запись слишком короткая (< 0.3 сек)

```swift
// В TranscriptionEngine:
guard samples.count >= 4800 else {  // 0.3 сек × 16000 Hz
    throw TranscriptionError.recordingTooShort(samples.count)
}
// AppCoordinator: при .recordingTooShort → state = .idle (тихо)
```

### Пустой результат whisper

```swift
// В TranscriptionEngine:
if result.isEmpty {
    throw TranscriptionError.emptyResult
}
// AppCoordinator: overlay "Не услышал ничего" 2 сек → idle
```

### Модель не скачана

```swift
// AppCoordinator:
} catch TranscriptionError.modelNotLoaded {
    menuBarController?.showPopoverWithDownload()
    state = .idle
}
```

### Таблица всех ошибок и UX-реакций

| Ошибка | Overlay текст | Время | Действие |
|---|---|---|---|
| `recordingTooShort` | — (тихо) | — | Сразу IDLE |
| `emptyResult` | "Не услышал ничего" | 2 сек | IDLE |
| `timeout` | "Слишком долго..." | 3 сек | IDLE |
| `modelNotLoaded` | "Скачайте модель в настройках" | 3 сек | Открыть popover |
| `microphonePermissionDenied` | "Нет доступа к микрофону" | 3 сек | Кнопка открыть настройки |
| `accessibilityPermissionDenied` | "Нет доступа Accessibility" | 3 сек | Кнопка открыть настройки |

---

## 5e — Автозапуск при входе в систему

```swift
// SayVoice/Settings/SettingsStore.swift
import ServiceManagement

private func updateLaunchAtLogin(enabled: Bool) {
    do {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    } catch {
        print("⚠️ Launch at login failed: \(error)")
    }
}
```

**Требования:**
- macOS 13.0+ (SMAppService — новый API, замена LaunchAgents plist)
- Приложение должно быть подписано (Developer ID)
- Пользователь может управлять через System Settings > General > Login Items

---

## 5f — Онбординг при первом запуске

Последовательность экранов показывается в `MenuBarPopoverView` как `NavigationStack` или серия `sheet`.

### OnboardingView.swift

```swift
// SayVoice/UI/OnboardingView.swift
import SwiftUI

enum OnboardingStep {
    case microphone
    case accessibility
    case modelDownload
    case complete
}

struct OnboardingView: View {
    @Environment(PermissionManager.self) private var permissions
    @Environment(ModelManager.self) private var modelManager
    @Environment(SettingsStore.self) private var settings
    @State private var step: OnboardingStep = .microphone
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .microphone:
                MicrophonePermissionStep(onNext: handleMicrophoneStep)

            case .accessibility:
                AccessibilityPermissionStep(onNext: handleAccessibilityStep)

            case .modelDownload:
                ModelDownloadStep(progress: downloadProgress, onDownload: startDownload)

            case .complete:
                CompleteStep(onDismiss: {
                    settings.hasCompletedOnboarding = true
                })
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear { checkInitialStep() }
    }

    private func checkInitialStep() {
        if !permissions.isMicrophoneGranted {
            step = .microphone
        } else if !permissions.isAccessibilityGranted {
            step = .accessibility
        } else if !modelManager.isModelAvailable(.small) {
            step = .modelDownload
        } else {
            step = .complete
        }
    }

    private func handleMicrophoneStep() {
        Task {
            await permissions.requestMicrophone()
            if permissions.isMicrophoneGranted {
                step = permissions.isAccessibilityGranted ? .modelDownload : .accessibility
            }
        }
    }

    private func handleAccessibilityStep() {
        permissions.requestAccessibilityPrompt()
        // Нет callback — пользователь должен вернуться после ручного включения
        // Показываем кнопку "Проверить" → повторная проверка
    }

    private func startDownload() {
        Task {
            for try await progress in modelManager.downloadModel(.small) {
                downloadProgress = progress
            }
            step = .complete
        }
    }
}
```

**Шаги онбординга:**

```
┌─────────────────────────────────────┐
│  🎙  Доступ к микрофону             │
│  SayVoice нужен доступ к микрофону  │
│  для записи голоса.                 │
│                                     │
│         [Разрешить]                 │
└─────────────────────────────────────┘
            ↓ (после разрешения)
┌─────────────────────────────────────┐
│  ♿  Специальные возможности        │
│  Нужен для глобального хоткея       │
│  и вставки текста.                  │
│                                     │
│  [Открыть настройки]  [Проверить]   │
└─────────────────────────────────────┘
            ↓ (после включения)
┌─────────────────────────────────────┐
│  ⬇  Модель Whisper Small            │
│  465 MB · хорошее качество RU/EN    │
│                                     │
│  ████████░░░░  52%                  │
│                                     │
│         [Скачать]                   │
└─────────────────────────────────────┘
            ↓ (после скачивания)
┌─────────────────────────────────────┐
│  ✅  Готово!                        │
│                                     │
│  Зажмите ⌥ Right Option             │
│  чтобы начать запись.               │
│                                     │
│         [Начать]                    │
└─────────────────────────────────────┘
```

---

## Критерии готовности M5

### Настройки
- [ ] SettingsView открывается из popover и через NSApp Settings
- [ ] Смена хоткея применяется без перезапуска
- [ ] Смена модели применяется при следующей транскрипции
- [ ] Toggle "звук" работает: записываем с включённым и выключенным
- [ ] Toggle "overlay" работает: overlay исчезает когда выключен

### История
- [ ] Popover показывает последние 10 записей
- [ ] Клик на запись → текст скопирован, иконка меняется на ✓
- [ ] "Очистить историю" → список пустеет
- [ ] История сохраняется между запусками

### Звуки
- [ ] Старт записи → Tink
- [ ] Конец транскрипции → Pop
- [ ] Тихо при `recordingTooShort`

### Ошибки
- [ ] Все ошибки показывают понятное сообщение в overlay
- [ ] После ошибки приложение возвращается в IDLE без перезапуска
- [ ] Таймаут 15 сек работает (проверить: скормить очень длинную тишину)

### Онбординг
- [ ] Первый запуск → открывается онбординг
- [ ] Второй запуск (после onboarding = done) → онбординг не показывается
- [ ] Каждый шаг онбординга работает корректно
- [ ] После всех шагов → приложение готово к работе

### Автозапуск
- [ ] Toggle "Запускать при входе" → появляется в System Settings > Login Items
- [ ] После включения: выйти из системы и войти → приложение запущено

---

## Итоговая проверка (end-to-end)

1. Свежая установка → онбординг → mic + accessibility + скачивание модели
2. Открыть TextEdit → зажать Right Option → сказать "Привет, это тест"
3. Отпустить → overlay "Привет, это тест" → текст в TextEdit
4. Открыть Chrome → повторить → текст вставляется через pasteboard
5. Кликнуть на menu bar иконку → видна запись в истории → клик копирует
6. Открыть настройки → сменить язык на "en" → проверить транскрипцию
7. Перезапустить приложение → история сохранена
8. Выключить звук в настройках → записать → тихо
9. Проверить автозапуск при входе в систему
