import AppKit
import SwiftUI

/// Единая высота строки: чип, поле ввода и плейсхолдер одного роста, иначе строка
/// выглядит рваной, а курсор — короче стоящих рядом чипов.
private let tagRowHeight: CGFloat = 26

/// Поле ввода списка терминов чипами.
///
/// Системный `NSTokenField` выглядит инородно и живёт в поле фиксированной высоты —
/// длинный словарь в нём обрезается. Здесь своя раскладка: чипы переносятся по строкам,
/// а поле растёт по содержимому, поэтому видны все термины сразу.
///
/// Наружу отдаётся та же строка через запятую, что лежала в настройках раньше: формат
/// хранения не меняется, миграция не нужна, и сборка initial_prompt получает привычное
/// значение.
struct TagField: View {
    @Binding var text: String
    var placeholder: String = ""

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var tags: [String] { Self.tokens(from: text) }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6, minTrailingWidth: 60) {
            ForEach(tags, id: \.self) { tag in
                TagChip(title: tag) { remove(tag) }
            }

            // Поле занимает остаток строки: текст и курсор рисуются у его левого края,
            // то есть сразу за последним чипом, а вылезти за границу поле не может —
            // его ширина ограничена строкой. Ширина по тексту (пробовал) даёт обратное:
            // поле липнет к правому краю и текст выходит за рамку.
            // .labelsHidden() обязателен: внутри Form со стилем .grouped SwiftUI иначе
            // трактует TextField как строку «подпись + контрол» — плейсхолдер уезжает в
            // колонку подписи, а сам редактор текста Form кладёт по-своему, игнорируя
            // нашу раскладку (курсор оказывался у правого края строки).
            TextField(placeholder, text: $draft)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(height: tagRowHeight)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, new in
                    // Запятая — тот же разделитель, что и Enter: работает и при вставке
                    // готового списка из буфера.
                    guard new.contains(",") else { return }
                    let parts = new.split(separator: ",", omittingEmptySubsequences: false)
                    for part in parts.dropLast() { append(String(part)) }
                    draft = String(parts.last ?? "")
                }
                .onKeyPress(.delete) {
                    // Backspace в пустом поле снимает последний чип.
                    guard draft.isEmpty, !tags.isEmpty else { return .ignored }
                    remove(tags[tags.count - 1])
                    return .handled
                }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        // Клик по любому месту поля ставит курсор в ввод — как в нативных полях с токенами.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    // MARK: - Правки списка

    private func commitDraft() {
        append(draft)
        draft = ""
    }

    private func append(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        // Дубликаты (без учёта регистра) не добавляем — модели они ничего не дают.
        guard !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        text = Self.string(from: tags + [value])
    }

    private func remove(_ tag: String) {
        text = Self.string(from: tags.filter { $0 != tag })
    }

    // MARK: - Строка настроек <-> термины

    /// Разбирает строку настроек в термины. Разделители — запятая и перевод строки.
    static func tokens(from string: String) -> [String] {
        string
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Собирает строку настроек обратно из терминов.
    static func string(from tokens: [String]) -> String {
        tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Чип

private struct TagChip: View {
    let title: String
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help("Удалить «\(title)»")
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: tagRowHeight)
        // Нейтральные тона: чип должен читаться как элемент этого же окна настроек,
        // а не как акцентная плашка.
        .background {
            Capsule().fill(Color.primary.opacity(isHovering ? 0.14 : 0.08))
        }
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(isHovering ? 0.24 : 0.15), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Раскладка с переносом по строкам

/// Складывает элементы в строку, перенося не поместившиеся на следующую.
/// Высота считается по факту — поэтому поле растёт под количество чипов,
/// а не обрезает их фиксированной высотой.
///
/// Раскладка считается одной функцией и для измерения, и для постановки: когда эти два
/// расчёта расходятся, элементы уезжают мимо своих мест (курсора не видно, текст
/// печатается за краем поля).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// Минимальная ширина поля ввода: если остатка строки меньше, поле переносится
    /// на новую строку целиком, а не сплющивается у правого края. Порог небольшой —
    /// чтобы курсор чаще оставался сразу за последним чипом, а не уезжал на свою строку.
    var minTrailingWidth: CGFloat = 60

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let width = maxWidth.isFinite ? maxWidth : .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var lineOfFrame: [Int] = []
        var lineTops: [CGFloat] = [0]
        var lineHeights: [CGFloat] = [0]
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        func breakLine() {
            lineHeights[line] = lineHeight
            y += lineHeight + lineSpacing
            line += 1
            lineTops.append(y)
            lineHeights.append(0)
            x = 0
            lineHeight = 0
        }

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)

            if index == subviews.count - 1 {
                // Поле ввода: занимает весь остаток строки.
                var remaining = width - x
                if x > 0 && remaining < minTrailingWidth {
                    breakLine()
                    remaining = width
                }
                size.width = max(minTrailingWidth, remaining)
            } else if x > 0 && x + size.width > width {
                breakLine()
            }

            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            lineOfFrame.append(line)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            lineHeights[line] = lineHeight
            widest = max(widest, x - spacing)
        }

        // Выравниваем элементы по центру своей строки: у чипа, поля ввода и
        // плейсхолдера разная высота, и без этого низкие элементы липнут к верху.
        for index in frames.indices {
            let line = lineOfFrame[index]
            frames[index].origin.y = lineTops[line] + (lineHeights[line] - frames[index].height) / 2
        }

        return (frames, CGSize(width: min(width, widest), height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}
