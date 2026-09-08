import SwiftUI

/// Окно настроек приложения.
/// Использует `@Bindable` (macOS 14+) для двустороннего binding к `@Observable` SettingsStore.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    /// Нужен, чтобы показать, какие модели уже загружены.
    var modelManager: ModelManager?
    /// Применение нового хоткея на лету — без перезапуска приложения.
    var onHotkeyChanged: ((Hotkey) -> Void)?
    /// Смена режима срабатывания хоткея.
    var onHotkeyModeChanged: ((Bool) -> Void)?

    var body: some View {
        Form {
            Section("Хоткей") {
                HotkeyRecorderField(hotkey: $settings.hotkey, onChange: onHotkeyChanged)

                Picker("Режим", selection: $settings.hotkeyMode) {
                    Text("Удержание").tag("hold")
                    Text("Переключатель").tag("toggle")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: settings.hotkeyMode) { _, new in
                    onHotkeyModeChanged?(new == "toggle")
                }

                Text(hotkeyModeNote).caption()
            }

            Section("Модель распознавания") {
                ForEach(ModelManager.ModelSize.allCases, id: \.self) { model in
                    ModelRow(
                        model: model,
                        isSelected: model == selectedModel,
                        isDownloaded: modelManager?.isModelAvailable(model) ?? false
                    ) {
                        settings.modelSize = model.settingsString
                    }
                }
                Text(selectedModel.note).caption()
            }

            Section("Язык распознавания") {
                Picker("Язык", selection: $settings.language) {
                    // «Авто» — не RU/EN, как было написано раньше: whisper определяет
                    // любой из поддерживаемых языков по самой речи.
                    Text("Авто").tag("auto")
                    Divider()
                    // English — отдельной группой, остальные по алфавиту.
                    Text("English").tag("en")
                    Divider()
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Italiano").tag("it")
                    Text("Nederlands").tag("nl")
                    Text("Polski").tag("pl")
                    Text("Português").tag("pt")
                    Text("Türkçe").tag("tr")
                    Text("Русский").tag("ru")
                    Text("Українська").tag("uk")
                }
                .pickerStyle(.menu)
                Text("Явный язык помогает, когда автоопределение ошибается — например, русская речь с английскими терминами.")
                    .caption()
            }

            Section("Словарь / контекст") {
                TagField(
                    text: $settings.vocabularyPrompt,
                    placeholder: "Добавить термин"
                )
                Text("Подсказка для распознавания: перечислите частые термины и имена — модель будет писать их правильно (английские — латиницей). Enter или запятая добавляет термин, Backspace удаляет. Пусто = отключено.")
                    .caption()
            }

            Section("Интерфейс") {
                Toggle("Показывать overlay при записи", isOn: $settings.overlayEnabled)
                Toggle("Звуковая обратная связь", isOn: $settings.soundFeedback)
            }

            Section("Метод вставки текста") {
                Picker("Метод", selection: $settings.pasteMethod) {
                    Text("Буфер обмена (Cmd+V)").tag("pasteboard")
                    Text("Accessibility API").tag("ax")
                }
                .pickerStyle(.radioGroup)
                Text(methodNote).caption()

                Toggle("Восстанавливать буфер обмена", isOn: $settings.restorePasteboard)
                Text(restoreNote).caption()
            }

            Section("Система") {
                Toggle("Запускать при входе в систему", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 14))
        .frame(width: 580, height: 760)
    }

    /// Пояснение под режимом хоткея — меняется вместе с выбором.
    private var hotkeyModeNote: String {
        settings.hotkeyIsToggle
        ? "Нажатие начинает запись, следующее — останавливает. Нужен для кнопок, которые не передают удержание: утилиты вроде Logi Options+ шлют короткий тап независимо от того, сколько кнопку держат."
        : "Запись идёт, пока клавиша или кнопка зажата. Модификатор-одиночка (как правый ⌥) работает без перехвата событий; обычную клавишу и кнопку мыши приложение перехватывает, чтобы они не срабатывали по прямому назначению — поэтому обычной клавише нужен хотя бы один модификатор."
    }

    /// Выбранная модель; неизвестное значение из настроек считаем за Turbo Q5.
    private var selectedModel: ModelManager.ModelSize {
        ModelManager.ModelSize(settingsString: settings.modelSize) ?? .turboQ5
    }

    /// Пояснение под выбором метода вставки — меняется вместе с выбором.
    private var methodNote: String {
        settings.pasteMethod == "ax"
        ? "Текст пишется прямо в поле через систему доступности, буфер обмена не участвует. Работает в нативных приложениях (TextEdit, Notes, Xcode, Safari); Chrome, Electron и Терминал доступ не отдают — там вставка автоматически идёт через буфер обмена."
        : "Текст кладётся в буфер обмена, после чего отправляется Cmd+V. Работает везде, где есть вставка."
    }

    /// Пояснение под галкой возврата буфера — тоже зависит от её состояния.
    private var restoreNote: String {
        settings.restorePasteboard
        ? "После вставки прежнее содержимое буфера возвращается на место — включая изображения и файлы. Cmd+V вставит именно его, а не диктовку: последнюю диктовку можно скопировать из истории в менюбаре."
        : "В буфере остаётся продиктованный текст, и Cmd+V повторяет его сколько угодно раз. Прежнее содержимое буфера при этом теряется — включая изображения и файлы."
    }
}

// MARK: - Строка модели

/// Строка списка моделей: выбор, название, бейджи и отметка о загрузке.
private struct ModelRow: View {
    let model: ModelManager.ModelSize
    let isSelected: Bool
    let isDownloaded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))

                Text(model.displayName)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Badge(text: model.badge, accented: model == .turboQ5)

                Spacer(minLength: 8)

                if isDownloaded {
                    Label("скачана", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }

                Badge(text: model.fileSize, monospacedDigits: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Небольшой бейдж в том же нейтральном стиле, что чипы словаря.
private struct Badge: View {
    let text: String
    var accented: Bool = false
    var monospacedDigits: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit(monospacedDigits)
            .foregroundStyle(accented ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(accented ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07))
            }
            .overlay {
                Capsule().strokeBorder(accented ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
}

private extension Text {
    @ViewBuilder
    func monospacedDigit(_ enabled: Bool) -> some View {
        if enabled { self.monospacedDigit() } else { self }
    }
}

// MARK: - Стиль пояснений

private extension View {
    /// Общий стиль подписей-пояснений под контролами.
    /// `.tertiary` читался тяжело, поэтому `.secondary`; размер на пункт крупнее
    /// системного `.caption` (11) — как и остальной текст окна.
    func caption() -> some View {
        self.font(.system(size: 12)).foregroundStyle(.secondary)
    }
}
