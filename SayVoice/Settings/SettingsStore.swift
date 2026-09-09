import CoreGraphics
import Foundation
import Observation
import ServiceManagement

/// Централизованное хранилище настроек приложения.
/// Использует `@Observable` (macOS 14+) для реактивного обновления SwiftUI.
/// Каждое свойство автоматически сохраняется в UserDefaults через `didSet`.
@MainActor @Observable
final class SettingsStore {

    /// Хранилище, в которое пишутся настройки. По умолчанию — `.standard`;
    /// тесты передают отдельный suite, чтобы не трогать настройки пользователя.
    private let defaults: UserDefaults

    // MARK: - Properties

    /// Virtual key code для hotkey записи. По умолчанию 61 (Right Option).
    var hotkeyCode: Int {
        didSet { defaults.set(hotkeyCode, forKey: SettingsKeys.hotkeyCode) }
    }

    /// Модификаторы хоткея — сырая маска CGEventFlags. Для хоткея-модификатора
    /// здесь маска его самого (см. Hotkey).
    var hotkeyFlags: Int {
        didSet { defaults.set(hotkeyFlags, forKey: SettingsKeys.hotkeyFlags) }
    }

    /// Кнопка мыши, назначенная на запись; -1 — хоткей клавиатурный.
    var hotkeyMouseButton: Int {
        didSet { defaults.set(hotkeyMouseButton, forKey: SettingsKeys.hotkeyMouseButton) }
    }

    /// Как работает хоткей: "hold" — запись идёт, пока клавиша зажата;
    /// "toggle" — нажал начал, нажал ещё раз остановил.
    ///
    /// Переключатель нужен не для удобства, а потому что некоторые кнопки удержание
    /// не передают: утилиты вроде Logi Options+ отправляют короткий тап (замерено —
    /// 12 мс) независимо от того, сколько кнопку держат.
    var hotkeyMode: String {
        didSet { defaults.set(hotkeyMode, forKey: SettingsKeys.hotkeyMode) }
    }

    var hotkeyIsToggle: Bool { hotkeyMode == "toggle" }

    /// Хоткей целиком. Раскладывается на три хранимых поля — UI и слушатель
    /// работают с одним значением, а не с их комбинацией.
    var hotkey: Hotkey {
        get {
            Hotkey(
                keyCode: CGKeyCode(hotkeyCode),
                flags: UInt64(hotkeyFlags),
                mouseButton: hotkeyMouseButton >= 0 ? hotkeyMouseButton : nil
            )
        }
        set {
            hotkeyCode = Int(newValue.keyCode)
            hotkeyFlags = Int(newValue.flags)
            hotkeyMouseButton = newValue.mouseButton ?? -1
        }
    }

    /// Размер модели Whisper: "tiny", "base", "small".
    var modelSize: String {
        didSet { defaults.set(modelSize, forKey: SettingsKeys.modelSize) }
    }

    /// Язык распознавания: "auto" или код языка whisper ("ru", "en", "de", …).
    var language: String {
        didSet { defaults.set(language, forKey: SettingsKeys.language) }
    }

    /// Показывать overlay при записи и транскрипции.
    var overlayEnabled: Bool {
        didSet { defaults.set(overlayEnabled, forKey: SettingsKeys.overlayEnabled) }
    }

    /// Возвращать прежнее содержимое буфера обмена после вставки диктовки.
    /// true — буфер не страдает, но Cmd+V вставит то, что было скопировано раньше.
    /// false — в буфере остаётся продиктованный текст, прежнее содержимое теряется.
    var restorePasteboard: Bool {
        didSet { defaults.set(restorePasteboard, forKey: SettingsKeys.restorePasteboard) }
    }

    /// Воспроизводить звуки при начале/конце записи.
    var soundFeedback: Bool {
        didSet { defaults.set(soundFeedback, forKey: SettingsKeys.soundFeedback) }
    }

    /// Метод вставки текста: "pasteboard" (Cmd+V) или "ax" (Accessibility API).
    var pasteMethod: String {
        didSet { defaults.set(pasteMethod, forKey: SettingsKeys.pasteMethod) }
    }

    /// Запускать приложение при входе в систему.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: SettingsKeys.launchAtLogin)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    /// Прошёл ли пользователь onboarding.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: SettingsKeys.hasCompletedOnboarding) }
    }

    /// Словарь/контекст для Whisper (initial_prompt): помогает точнее распознавать
    /// смешанную RU/EN речь и специфичные термины. Пустая строка = без промпта.
    var vocabularyPrompt: String {
        didSet { defaults.set(vocabularyPrompt, forKey: SettingsKeys.vocabularyPrompt) }
    }

    /// Дефолтный промпт: голый список IT-терминов латиницей. `initial_prompt` в whisper —
    /// это пример лексики/стиля, которым кондиционируется декодер. Список терминов
    /// подсказывает их написание, НЕ навязывая язык всей диктовке.
    ///
    /// Раньше здесь была русская фраза-предложение ("Диктовка на русском языке..."),
    /// которая смещала декодер к русским токенам и в auto-режиме "переводила"
    /// английскую речь в русский (баг EN→RU). См. legacyRussianVocabularyPrompt.
    static let defaultVocabularyPrompt =
        "API, deployment, frontend, backend, commit, pull request, feature, bug, SwiftUI, Xcode, TypeScript, React, endpoint, refactor, staging, production."

    /// Старый дефолт: русская фраза-предложение. Смещала whisper к русскому и ломала
    /// английскую диктовку. Хранится только для миграции сохранённого значения — если
    /// в UserDefaults лежит ровно эта строка, её нужно заменить новым дефолтом.
    static let legacyRussianVocabularyPrompt =
        "Диктовка на русском языке с английскими словами и IT-терминами: API, deployment, frontend, backend, commit, pull request, feature, bug, SwiftUI, Xcode."

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults

        // Int: object(forKey:) as? Int ?? default — иначе integer(forKey:) вернёт 0 при отсутствии ключа
        self.hotkeyCode  = d.object(forKey: SettingsKeys.hotkeyCode) as? Int ?? Int(Hotkey.default.keyCode)
        self.hotkeyFlags = d.object(forKey: SettingsKeys.hotkeyFlags) as? Int ?? Int(Hotkey.default.flags)
        self.hotkeyMouseButton = d.object(forKey: SettingsKeys.hotkeyMouseButton) as? Int ?? -1
        self.hotkeyMode = d.string(forKey: SettingsKeys.hotkeyMode) ?? "hold"

        // String: string(forKey:) ?? default
        self.modelSize   = d.string(forKey: SettingsKeys.modelSize) ?? ModelManager.ModelSize.recommended.settingsString
        self.language    = d.string(forKey: SettingsKeys.language) ?? "auto"
        self.pasteMethod = d.string(forKey: SettingsKeys.pasteMethod) ?? "pasteboard"

        // Bool с дефолтом true: object(forKey:) as? Bool ?? true
        // (bool(forKey:) вернёт false при отсутствии ключа!)
        self.overlayEnabled = d.object(forKey: SettingsKeys.overlayEnabled) as? Bool ?? true
        self.soundFeedback  = d.object(forKey: SettingsKeys.soundFeedback) as? Bool ?? true
        self.restorePasteboard = d.object(forKey: SettingsKeys.restorePasteboard) as? Bool ?? true

        // Bool с дефолтом false: bool(forKey:) безопасен
        self.launchAtLogin          = d.bool(forKey: SettingsKeys.launchAtLogin)
        self.hasCompletedOnboarding = d.bool(forKey: SettingsKeys.hasCompletedOnboarding)

        // Миграция: пусто или ровно старый русский промпт → новый нейтральный дефолт.
        // Кастомный промпт пользователя не трогаем.
        let storedPrompt = d.string(forKey: SettingsKeys.vocabularyPrompt)
        if storedPrompt == nil || storedPrompt == Self.legacyRussianVocabularyPrompt {
            self.vocabularyPrompt = Self.defaultVocabularyPrompt
            d.set(Self.defaultVocabularyPrompt, forKey: SettingsKeys.vocabularyPrompt)
        } else {
            self.vocabularyPrompt = storedPrompt!
        }
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("[SayVoice] Launch at login: registered")
            } else {
                try SMAppService.mainApp.unregister()
                print("[SayVoice] Launch at login: unregistered")
            }
        } catch {
            print("[SayVoice] Launch at login failed: \(error)")
        }
    }
}
