import SwiftUI

/// Row height shared by chips, the input and the placeholder so the line
/// reads as one, and the caret sits level with the chips.
private let tagRowHeight: CGFloat = 26

/// Term editor rendered as chips.
///
/// Stores and exposes a comma-separated string — the same format the app has
/// always kept in settings — so no migration is needed and the transcription
/// prompt receives what it always did. Enter or comma adds a term, Backspace
/// in an empty input removes the last one, duplicates (case-insensitive) are
/// ignored.
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

            // The input takes the rest of its line, so text and caret are drawn
            // right after the last chip and cannot escape the field: its width is
            // bounded by the line. Sizing it to its text (tried) does the opposite —
            // the input sticks to the right edge and the text runs past the border.
            // Inside a grouped Form, SwiftUI treats a TextField as a
            // "label + control" row and repositions the editor itself;
            // labelsHidden keeps the editor where the layout puts it.
            TextField(placeholder, text: $draft)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(DS.font(.body))
                .foregroundStyle(DS.Colors.text.color)
                .frame(height: tagRowHeight)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onChange(of: draft) { _, new in
                    // A comma is the same separator as Enter: this also works when a
                    // ready-made list is pasted in.
                    guard new.contains(",") else { return }
                    let parts = new.split(separator: ",", omittingEmptySubsequences: false)
                    for part in parts.dropLast() { append(String(part)) }
                    draft = String(parts.last ?? "")
                }
                .onKeyPress(.delete) {
                    // Backspace in an empty input removes the last chip.
                    guard draft.isEmpty, !tags.isEmpty else { return .ignored }
                    remove(tags[tags.count - 1])
                    return .handled
                }
        }
        .padding(DS.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous).fill(DS.Colors.surface2.color))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .strokeBorder(isFocused ? DS.Colors.accent.color : DS.Colors.line.color, lineWidth: 1)
        )
        .animation(DS.Motion.stateChange, value: isFocused)
        // A click anywhere in the field puts the caret in the input — as in native
        // token fields.
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }

    // MARK: - Editing

    private func commitDraft() {
        append(draft)
        draft = ""
    }

    private func append(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        // Duplicates (case-insensitive) add nothing for the model.
        guard !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        text = Self.string(from: tags + [value])
    }

    private func remove(_ tag: String) {
        text = Self.string(from: tags.filter { $0 != tag })
    }

    // MARK: - Settings string <-> terms

    /// Splits the stored string into terms on commas and newlines.
    static func tokens(from string: String) -> [String] {
        string
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Joins terms back into the stored string.
    static func string(from tokens: [String]) -> String {
        tokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

// MARK: - Chip

/// A removable chip. Not `Chip`, which is a static capsule label without a
/// remove button or a hover state.
private struct TagChip: View {
    let title: String
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(DS.font(.bodyMedium))
                .foregroundStyle(DS.Colors.text.color)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHovering ? DS.Colors.text.color : DS.Colors.muted.color)
            }
            .buttonStyle(.plain)
            .help("Remove “\(title)”")
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .frame(height: tagRowHeight)
        .background(Capsule().fill(DS.Colors.surface.color.opacity(isHovering ? 1 : 0.85)))
        // The border steps up as well as the fill: in dark the fill change
        // alone is almost invisible.
        .overlay(Capsule().strokeBorder(isHovering ? DS.Colors.muted.color : DS.Colors.line.color, lineWidth: 1))
        .onHover { isHovering = $0 }
        .animation(DS.Motion.stateChange, value: isHovering)
    }
}

// MARK: - Flow layout

/// Wraps items onto new lines; the last item (the input) takes the rest of
/// its line or moves to a new one if less than `minTrailingWidth` is left.
/// Measurement and placement share one function so they cannot disagree.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var minTrailingWidth: CGFloat = 60

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let width = maxWidth.isFinite ? maxWidth : .greatestFiniteMagnitude
        var frames: [CGRect] = []
        var lineOfFrame: [Int] = []
        var lineTops: [CGFloat] = [0]
        var lineHeights: [CGFloat] = [0]
        var x: CGFloat = 0, y: CGFloat = 0, line = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0

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
        // Centre every item in its line: chips, the input and the placeholder have
        // different heights, and without this the short ones stick to the top.
        for index in frames.indices {
            let l = lineOfFrame[index]
            frames[index].origin.y = lineTops[l] + (lineHeights[l] - frames[index].height) / 2
        }
        return (frames, CGSize(width: min(width, widest), height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews).frames
        for index in subviews.indices {
            let f = frames[index]
            subviews[index].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                                  proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
