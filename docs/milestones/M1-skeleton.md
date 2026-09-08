# M1 — Скелет приложения (DONE)

**Цель:** Рабочее macOS menu bar приложение без иконки в Dock, реагирующее на глобальный хоткей. Нет транскрипции — только скелет с визуальной обратной связью.

**Оценка:** 2 рабочих дня
**Зависимости:** Нет (первый майлстоун)
**Критерий готовности:** Зажать Right Option → красная иконка + overlay "Запись..." → отпустить → всё скрывается

---

## Задачи

### 1. Создание Xcode проекта

- [x] Проект через xcodegen (project.yml), Bundle ID: `com.sayvoice.app`
- [x] Deployment Target: macOS 14.0
- [x] Создана структура папок согласно [file-structure.md](../file-structure.md)

### 2. Info.plist

- [x] `LSUIElement = true` — нет иконки в Dock
- [x] `NSMicrophoneUsageDescription` — описание доступа к микрофону
- [x] `NSAppleEventsUsageDescription` — описание доступа Accessibility
- [x] `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion` и др. стандартные ключи

### 3. Entitlements — отключить sandbox

- [x] `com.apple.security.app-sandbox = false`

### 4. AppState.swift

- [x] `enum AppState: Equatable` — idle, recording, transcribing, injecting, error
- [x] `enum AppError: Error, Equatable` — все типы ошибок

### 5. SayVoiceApp.swift — точка входа

- [x] `@main struct SayVoiceApp: App` + `AppDelegate`
- [x] `NSApp.setActivationPolicy(.accessory)` — скрытие из Dock

### 6. MenuBarController.swift

- [x] `NSStatusItem` с SF Symbol "waveform"
- [x] Анимация пульса при записи (waveform ↔ waveform.badge.mic.fill)
- [x] Цвета: красный (recording), оранжевый (transcribing), зелёный (injecting)
- [x] Меню с пунктом "Quit SayVoice"

### 7. OverlayView.swift + OverlayWindowController.swift

- [x] `NSPanel` с `.borderless` + `.nonactivatingPanel` (не крадёт фокус)
- [x] SwiftUI overlay с пульсирующим красным кружком при записи
- [x] `.regularMaterial` фон, скруглённые углы, тень
- [x] Анимация fade-in/fade-out
- [x] Позиционирование внизу экрана

### 8. HotkeyListener.swift

- [x] `CGEvent.tapCreate()` для глобального перехвата клавиш (macOS 26 API)
- [x] Слушает `flagsChanged` (Right Option — модификатор, не обычная клавиша)
- [x] Извлечение keyCode и flags ДО перехода в `Task { @MainActor }` (Swift 6 Sendable)
- [x] Автоматическая реактивация tap при `tapDisabledByTimeout`
- [x] `promptAccessibility()` — показывает системный диалог при отсутствии разрешения

### 9. AppCoordinator.swift

- [x] State machine: idle → recording → idle (M1 скелет)
- [x] Координирует MenuBarController, OverlayWindowController, HotkeyListener
- [x] Видимая ошибка в overlay при отсутствии Accessibility

---

## Адаптация под macOS 26 (Tahoe)

Код адаптирован под macOS 26.2 SDK (Xcode 16+):

- `CGEvent.tapCreate()` вместо `CGEventTapCreate()` (устаревший)
- `CGEvent.tapEnable(tap:enable:)` вместо `CGEventTapEnable()` (устаревший)
- `NSStatusItem.variableLength` вместо `.variableStatusItemLength` (устаревший)
- Строковый литерал `"AXTrustedCheckOptionPrompt"` вместо глобальной переменной (Swift 6 concurrency)
- Timer closures обёрнуты в `Task { @MainActor in }` (@Sendable requirement)
- NSAnimationContext completionHandler использует `MainActor.assumeIsolated {}`

---

## Критерии готовности M1

- [x] Приложение запускается — нет иконки в Dock
- [x] В menu bar появляется иконка "waveform"
- [x] Без Accessibility: overlay показывает "Нет доступа Accessibility", системный диалог
- [x] С Accessibility: зажать Right Option → иконка краснеет, появляется overlay "Запись..."
- [x] Отпустить Right Option → иконка серая, overlay исчезает с анимацией
- [x] Меню → пункт "Quit" работает
- [x] 0 ошибок, 0 warnings при сборке на macOS 26.2 SDK
