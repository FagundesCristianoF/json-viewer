import AppKit
import SwiftUI

// MARK: - Folding helpers

struct CollapsedResult {
    let text: String
    let displayToOriginal: [Int: Int]   // display line (1-based) → original line (1-based)
    let foldableDisplayLines: Set<Int>  // display lines that have a fold arrow
}

func buildCollapsedText(text: String, foldedLines: Set<Int>, foldRanges: [FoldRange]) -> CollapsedResult {
    let lines = text.components(separatedBy: "\n")
    var result: [String] = []
    var displayToOriginal: [Int: Int] = [:]
    var foldableDisplayLines: Set<Int> = []

    var i = 0
    var displayLine = 1

    while i < lines.count {
        let origLine = i + 1  // 1-based

        if foldedLines.contains(origLine),
           let range = foldRanges.first(where: { $0.start == origLine }),
           range.end > origLine + 1 {
            // Show opening line with ellipsis; skip inner lines; closing brace shown next iteration
            result.append(lines[i] + " …")
            displayToOriginal[displayLine] = origLine
            foldableDisplayLines.insert(displayLine)
            displayLine += 1
            i = range.end - 1  // jump to closing line (0-based index)
        } else {
            result.append(lines[i])
            displayToOriginal[displayLine] = origLine
            if foldRanges.contains(where: { $0.start == origLine }) {
                foldableDisplayLines.insert(displayLine)
            }
            displayLine += 1
            i += 1
        }
    }

    return CollapsedResult(
        text: result.joined(separator: "\n"),
        displayToOriginal: displayToOriginal,
        foldableDisplayLines: foldableDisplayLines
    )
}

// MARK: - EditorView

struct EditorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            CodeEditorRepresentable()
                .environmentObject(model)

            if model.showFind {
                FindBarView()
                    .environmentObject(model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.resolvedCompose != nil {
                VStack {
                    Spacer()
                    RawResultToggle()
                        .environmentObject(model)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - CodeEditorRepresentable

struct CodeEditorRepresentable: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        // Basic setup
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Font
        let font = NSFont(name: "SF Mono", size: 12.5)
            ?? NSFont(name: "Menlo", size: 12.5)
            ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.font = font
        textView.typingAttributes[.font] = font

        // Colors
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor

        // Line wrap off for code
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Scroll view config
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        // Line number ruler
        let rulerView = LineNumberRulerView(textView: textView)
        rulerView.clientView = textView
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true

        // Delegate
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView

        // Cmd+F → toggle find bar
        let findResponder = FindKeyHandler(coordinator: context.coordinator)
        textView.addSubview(findResponder)

        // Initial content
        textView.string = model.editorText
        context.coordinator.applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator

        let isResultMode = !model.isRawMode && model.resolvedCompose != nil
        let baseText = isResultMode ? model.resolvedCompose! : model.editorText
        let hasFolds = !model.foldedLines.isEmpty

        // Build collapsed display text when folds are active
        let collapsed = hasFolds
            ? buildCollapsedText(text: baseText, foldedLines: model.foldedLines, foldRanges: model.foldRanges)
            : CollapsedResult(text: baseText, displayToOriginal: [:], foldableDisplayLines: Set(model.foldRanges.map { $0.start }))

        let displayText = collapsed.text
        let isReadOnly = isResultMode || hasFolds

        let needsTextUpdate = !coordinator.isEditing && textView.string != displayText
        let needsModeUpdate = textView.isEditable == isReadOnly

        if needsTextUpdate || needsModeUpdate {
            textView.string = displayText
            textView.isEditable = !isReadOnly
            coordinator.applyHighlighting(to: textView)
            (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }

        // Sync ruler with fold state
        if let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
            ruler.displayToOriginal = hasFolds ? collapsed.displayToOriginal : [:]
            ruler.foldableDisplayLines = collapsed.foldableDisplayLines
            ruler.foldedLines = model.foldedLines
            ruler.foldRanges = model.foldRanges
            ruler.needsDisplay = true
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var isEditing = false

        init(model: AppModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            let text = tv.string
            model.editorText = text
            model.isDirty = true
            applyHighlighting(to: tv)
            rulerView?.needsDisplay = true
            if model.autoSave {
                model.save()
            }
            model.reparse()
            isEditing = false
        }

        // MARK: Syntax highlighting

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let text = storage.string
            let fullRange = NSRange(text.startIndex..., in: text)

            storage.beginEditing()

            // Reset to base attributes
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            storage.setAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor
            ], range: fullRange)

            // Tokenize and colorize
            tokenize(text: text, storage: storage, font: font)

            storage.endEditing()
        }

        private func tokenize(text: String, storage: NSTextStorage, font: NSFont) {
            let nsText = text as NSString
            let length = nsText.length

            var i = 0
            while i < length {
                let ch = nsText.character(at: i)
                let scalar = Unicode.Scalar(ch)!
                let char = Character(scalar)

                // Skip whitespace
                if char.isWhitespace { i += 1; continue }

                // String
                if char == "\"" {
                    let start = i
                    i += 1
                    var escaped = false
                    while i < length {
                        let c = nsText.character(at: i)
                        if escaped {
                            escaped = false
                        } else if c == 0x5C { // backslash
                            escaped = true
                        } else if c == 0x22 { // "
                            i += 1
                            break
                        }
                        i += 1
                    }
                    let range = NSRange(location: start, length: i - start)
                    // Determine if this string is a key (followed by colon after optional whitespace)
                    var j = i
                    while j < length {
                        let nc = nsText.character(at: j)
                        if nc == 0x20 || nc == 0x09 || nc == 0x0A || nc == 0x0D { j += 1; continue }
                        if nc == 0x3A { // colon
                            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
                        } else {
                            storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
                        }
                        break
                    }
                    if j >= length {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: range)
                    }
                    continue
                }

                // Number
                if char.isNumber || (char == "-" && i + 1 < length && {
                    let nc = Unicode.Scalar(nsText.character(at: i + 1))!
                    return Character(nc).isNumber
                }()) {
                    let start = i
                    i += 1
                    while i < length {
                        let c = Unicode.Scalar(nsText.character(at: i))!
                        let cc = Character(c)
                        if cc.isNumber || cc == "." || cc == "e" || cc == "E" || cc == "+" || cc == "-" {
                            i += 1
                        } else {
                            break
                        }
                    }
                    let range = NSRange(location: start, length: i - start)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
                    continue
                }

                // true / false / null
                if char == "t" && nsText.length > i + 3 && nsText.substring(with: NSRange(location: i, length: 4)) == "true" {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: NSRange(location: i, length: 4))
                    i += 4; continue
                }
                if char == "f" && nsText.length > i + 4 && nsText.substring(with: NSRange(location: i, length: 5)) == "false" {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: NSRange(location: i, length: 5))
                    i += 5; continue
                }
                if char == "n" && nsText.length > i + 3 && nsText.substring(with: NSRange(location: i, length: 4)) == "null" {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: NSRange(location: i, length: 4))
                    i += 4; continue
                }

                // Brackets / braces / colon / comma
                if char == "{" || char == "}" || char == "[" || char == "]" || char == ":" || char == "," {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: i, length: 1))
                    i += 1; continue
                }

                i += 1
            }
        }
    }
}

// MARK: - FindKeyHandler

/// Invisible view that intercepts Cmd+F to toggle the find bar.
private final class FindKeyHandler: NSView {
    weak var coordinator: CodeEditorRepresentable.Coordinator?

    init(coordinator: CodeEditorRepresentable.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
}

// MARK: - LineNumberRulerView

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var foldRanges: [FoldRange] = []
    var foldedLines: Set<Int> = []
    var displayToOriginal: [Int: Int] = [:]        // populated when folds active
    var foldableDisplayLines: Set<Int> = []        // display lines that show a fold arrow

    private let rulerWidth: CGFloat = 48
    private let font: NSFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private let textColor = NSColor.tertiaryLabelColor
    private let bgColor = NSColor(white: 0.0, alpha: 0.03)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = rulerWidth
        self.clientView = textView
    }

    required init(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView,
              let layoutManager = tv.layoutManager,
              let textContainer = tv.textContainer else { return }

        let context = NSGraphicsContext.current!.cgContext

        // Background
        bgColor.setFill()
        dirtyRect.fill()

        // Separator line on right edge
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        let text = tv.string as NSString
        let visibleRect = tv.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Build line start offsets
        var lineStarts: [(line: Int, charIdx: Int)] = []
        var lineNum = 1
        var charIdx = 0
        let totalLen = text.length

        while charIdx <= totalLen {
            lineStarts.append((line: lineNum, charIdx: charIdx))
            if charIdx == totalLen { break }
            let lineRange = text.lineRange(for: NSRange(location: charIdx, length: 0))
            charIdx = lineRange.upperBound
            lineNum += 1
        }

        // Draw line numbers and fold arrows
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        for (displayLine, lineCharIdx) in lineStarts {
            guard lineCharIdx <= charRange.upperBound && lineCharIdx >= charRange.location || lineCharIdx == 0 else {
                if lineCharIdx > charRange.upperBound { break }
                continue
            }
            guard lineCharIdx < totalLen || totalLen == 0 else { break }

            let glyphIdx = layoutManager.glyphIndexForCharacter(at: min(lineCharIdx, max(0, totalLen - 1)))
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)

            let yOffset = lineFragmentRect.minY - visibleRect.minY + tv.textContainerInset.height

            // Show original line number when folding is active, else display line
            let labelLine = displayToOriginal.isEmpty ? displayLine : (displayToOriginal[displayLine] ?? displayLine)
            let numStr = "\(labelLine)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let numRect = NSRect(
                x: rulerWidth - strSize.width - 16,
                y: yOffset + (lineFragmentRect.height - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            numStr.draw(in: numRect, withAttributes: attrs)

            // Fold arrow: use foldableDisplayLines when mapping is active
            let isFoldable = foldableDisplayLines.isEmpty
                ? foldRanges.contains(where: { $0.start == displayLine })
                : foldableDisplayLines.contains(displayLine)

            if isFoldable {
                let origLine = displayToOriginal.isEmpty ? displayLine : (displayToOriginal[displayLine] ?? displayLine)
                let isFolded = foldedLines.contains(origLine)
                drawFoldArrow(
                    context: context,
                    x: rulerWidth - 12,
                    y: yOffset + lineFragmentRect.height / 2,
                    folded: isFolded
                )
            }
        }
    }

    private func drawFoldArrow(context: CGContext, x: CGFloat, y: CGFloat, folded: Bool) {
        context.saveGState()
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)

        let size: CGFloat = 6
        context.translateBy(x: x, y: y)

        if folded {
            // Right-pointing triangle
            context.move(to: CGPoint(x: -size / 2, y: -size / 2))
            context.addLine(to: CGPoint(x: size / 2, y: 0))
            context.addLine(to: CGPoint(x: -size / 2, y: size / 2))
        } else {
            // Down-pointing triangle
            context.move(to: CGPoint(x: -size / 2, y: -size / 4))
            context.addLine(to: CGPoint(x: size / 2, y: -size / 4))
            context.addLine(to: CGPoint(x: 0, y: size / 2))
        }

        context.closePath()
        context.fillPath()
        context.restoreGState()
    }

    // MARK: Mouse handling for fold toggle

    override func mouseDown(with event: NSEvent) {
        guard let tv = textView,
              let layoutManager = tv.layoutManager else { return }

        let locationInRuler = convert(event.locationInWindow, from: nil)
        // Only handle clicks in arrow zone (right 16pt of ruler)
        guard locationInRuler.x >= rulerWidth - 16 else { return }

        let visibleRect = tv.visibleRect
        let clickY = locationInRuler.y + visibleRect.minY - tv.textContainerInset.height

        let text = tv.string as NSString
        let totalLen = text.length
        var lineNum = 1
        var charIdx = 0

        while charIdx <= totalLen {
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: min(charIdx, max(0, totalLen - 1)))
            let lineFragRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)

            if clickY >= lineFragRect.minY && clickY < lineFragRect.maxY {
                // Resolve display line → original line when folds active
                let origLine = displayToOriginal.isEmpty ? lineNum : (displayToOriginal[lineNum] ?? lineNum)
                let isFoldable = foldableDisplayLines.isEmpty
                    ? foldRanges.contains(where: { $0.start == origLine })
                    : foldableDisplayLines.contains(lineNum)
                if isFoldable {
                    toggleFold(line: origLine)
                }
                break
            }

            if charIdx == totalLen { break }
            let lineRange = text.lineRange(for: NSRange(location: charIdx, length: 0))
            charIdx = lineRange.upperBound
            lineNum += 1
        }
    }

    private func toggleFold(line: Int) {
        // Delegate fold state back to AppModel via a notification-style approach
        // We post a notification the model can observe, or use a direct callback.
        // For now: toggle via AppModel directly on main actor.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // We can't easily reach AppModel here without a reference.
            // Use a static notification approach.
            NotificationCenter.default.post(
                name: .jsonViewToggleFold,
                object: nil,
                userInfo: ["line": line]
            )
        }
    }
}

extension Notification.Name {
    static let jsonViewToggleFold = Notification.Name("jsonViewToggleFold")
}

// MARK: - FindBarView

struct FindBarView: View {
    @EnvironmentObject var model: AppModel
    @State private var query: String = ""
    @State private var matchCount: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: 260)
                .onSubmit { findNext() }
                .onChange(of: query) { _ in updateMatches() }

            if matchCount > 0 {
                Text("\(matchCount) match\(matchCount == 1 ? "" : "es")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: findPrev) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: findNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("g", modifiers: .command)

            Button(action: { model.showFind = false }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func updateMatches() {
        guard !query.isEmpty else { matchCount = 0; return }
        let text = model.editorText
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        matchCount = count
    }

    private func findNext() {
        NotificationCenter.default.post(name: .jsonViewFind, object: nil, userInfo: ["query": query, "direction": "next"])
    }

    private func findPrev() {
        NotificationCenter.default.post(name: .jsonViewFind, object: nil, userInfo: ["query": query, "direction": "prev"])
    }
}

extension Notification.Name {
    static let jsonViewFind = Notification.Name("jsonViewFind")
}

// MARK: - RawResultToggle

struct RawResultToggle: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            toggleButton(label: "Raw", active: model.isRawMode) {
                model.isRawMode = true
            }
            toggleButton(label: "Result", active: !model.isRawMode) {
                model.isRawMode = false
                model.resolveCompose()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(active ? Color(NSColor.controlAccentColor).opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
