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
        VStack(spacing: 0) {
            if model.showFind {
                FindBarView()
                    .environmentObject(model)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack(alignment: .bottom) {
                CodeEditorRepresentable()
                    .environmentObject(model)

                if model.resolvedCompose != nil {
                    RawResultToggle()
                        .environmentObject(model)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .editorActivateFind)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { model.showFind.toggle() }
        }
    }
}

// MARK: - JSONEditorTextView

final class JSONEditorTextView: NSTextView {
    var onGenerateJSONPath: ((String) -> Void)?
    var onDidPaste: (() -> Void)?

    // Set by updateNSView so copy: can expand folded blocks
    var originalText: String?
    var foldedLines: Set<Int> = []
    var foldRanges: [FoldRange] = []

    // Workspace JSON filenames for {{ compose completion
    var composeFileNames: [String] = []

    override func paste(_ sender: Any?) {
        super.paste(sender)
        onDidPaste?()
    }

    var onSave: (() -> Void)?

    // Without an NSDocument, Cmd+S reaches NSTextView unhandled and AppKit beeps.
    // Intercept at the performKeyEquivalent level and forward to the model.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard !composeFileNames.isEmpty else { return nil }
        let text = string as NSString
        let loc = charRange.location
        guard loc >= 2,
              text.substring(with: NSRange(location: loc - 2, length: 2)) == "{{" else { return nil }
        let partial = text.substring(with: charRange).lowercased()
        let matches = composeFileNames.filter { partial.isEmpty || $0.lowercased().contains(partial) }
        index.pointee = 0
        return matches.isEmpty ? nil : matches
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal: Bool) {
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: isFinal)
        guard isFinal else { return }
        let loc = selectedRange().location
        let text = string as NSString
        let alreadyClosed = loc + 2 <= text.length &&
            text.substring(with: NSRange(location: loc, length: 2)) == "}}"
        if !alreadyClosed {
            insertText("}}", replacementRange: NSRange(location: loc, length: 0))
        }
    }

    override func copy(_ sender: Any?) {
        guard let origText = originalText, !foldedLines.isEmpty else {
            super.copy(sender)
            return
        }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        // Full-document selection: copy unfolded original directly
        if sel.location == 0 && sel.length >= (string as NSString).length {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(origText, forType: .string)
            return
        }
        guard let expanded = expandedCopy(sel: sel, display: string, original: origText) else {
            super.copy(sender)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(expanded, forType: .string)
    }

    /// Map a selection range in the collapsed display text to the corresponding
    /// substring in the original text, expanding any folded blocks within.
    private func expandedCopy(sel: NSRange, display: String, original: String) -> String? {
        struct LineInfo {
            let dStart: Int; let dEnd: Int   // char offsets in display text
            let oStart: Int; let oEnd: Int   // char offsets in original text
            let isFold: Bool
        }

        let dLines = display.components(separatedBy: "\n")
        let oLines = original.components(separatedBy: "\n")
        var infos: [LineInfo] = []
        var dOff = 0, oOff = 0, oIdx = 0

        for dLine in dLines {
            guard oIdx < oLines.count else { break }
            let oNum = oIdx + 1
            let fr = foldedLines.contains(oNum)
                ? foldRanges.first(where: { $0.start == oNum && $0.end > oNum + 1 })
                : nil

            if let fr = fr {
                // Fold opener: origEnd spans opener + hidden + closer content
                var oEnd = oOff + oLines[oIdx].count
                for h in (oIdx + 1)..<(fr.end - 1) {
                    if h < oLines.count { oEnd += 1 + oLines[h].count }
                }
                let ci = fr.end - 1
                if ci < oLines.count { oEnd += 1 + oLines[ci].count }
                infos.append(LineInfo(dStart: dOff, dEnd: dOff + dLine.count,
                                      oStart: oOff, oEnd: oEnd, isFold: true))
                // Advance oOff past opener + hidden (NOT past closer — it renders as next display line)
                oOff += oLines[oIdx].count + 1
                for h in (oIdx + 1)..<(fr.end - 1) {
                    if h < oLines.count { oOff += oLines[h].count + 1 }
                }
                oIdx = fr.end - 1  // closer is next display line
            } else {
                infos.append(LineInfo(dStart: dOff, dEnd: dOff + dLine.count,
                                      oStart: oOff, oEnd: oOff + oLines[oIdx].count, isFold: false))
                oOff += oLines[oIdx].count + 1
                oIdx += 1
            }
            dOff += dLine.count + 1
        }

        let sStart = sel.location, sEnd = sel.location + sel.length
        guard let first = infos.first(where: { $0.dEnd >= sStart }),
              let last  = infos.last(where:  { $0.dStart < sEnd }) else { return nil }

        let oStart = first.oStart + min(max(0, sStart - first.dStart),
                                        max(0, first.oEnd - first.oStart))
        let oEnd: Int
        if last.isFold {
            oEnd = last.oEnd
        } else {
            oEnd = last.oStart + min(max(0, sEnd - last.dStart),
                                     max(0, last.oEnd - last.oStart))
        }

        guard oStart <= oEnd, oEnd <= (original as NSString).length else { return nil }
        return (original as NSString).substring(with: NSRange(location: oStart, length: oEnd - oStart))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let raw = (string as NSString).substring(with: selectedRange())
        let key = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        guard !key.isEmpty else { return menu }
        let title = "Generate JSONPath for \"\(key)\""
        if menu.item(withTitle: title) == nil {
            let item = NSMenuItem(title: title, action: #selector(doGenerateJSONPath), keyEquivalent: "")
            item.target = self
            menu.insertItem(NSMenuItem.separator(), at: 0)
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    @objc private func doGenerateJSONPath() {
        let raw = (string as NSString).substring(with: selectedRange())
        let key = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        guard !key.isEmpty else { return }
        onGenerateJSONPath?(key)
    }
}

// MARK: - CodeEditorRepresentable

struct CodeEditorRepresentable: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Build a TextKit 1 stack explicitly — macOS 15+ NSTextView.scrollableTextView()
        // returns a TextKit 2 view; the glyph-based NSLayoutManager APIs used by
        // LineNumberRulerView crash under the compatibility shim on macOS 27+.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let scrollView = NSTextView.scrollableTextView()
        guard let origTV = scrollView.documentView as? NSTextView else { return scrollView }
        let textView = JSONEditorTextView(frame: origTV.frame, textContainer: textContainer)
        textView.minSize = origTV.minSize
        textView.maxSize = origTV.maxSize
        textView.isVerticallyResizable = origTV.isVerticallyResizable
        textView.isHorizontallyResizable = origTV.isHorizontallyResizable
        textView.autoresizingMask = origTV.autoresizingMask
        scrollView.documentView = textView

        let coordinator = context.coordinator
        textView.onGenerateJSONPath = { key in
            Task { @MainActor in
                let model = coordinator.model
                if let node = model.treeNodes.first(where: { $0.key == key }) {
                    model.jsonPathQuery = node.path
                } else {
                    model.jsonPathQuery = "$..\(key)"
                }
                model.runJsonPath()
            }
        }

        textView.onDidPaste = {
            Task { @MainActor in
                let model = coordinator.model
                guard model.formatOnPaste else { return }
                model.formatInPlace()
            }
        }

        textView.onSave = {
            Task { @MainActor in coordinator.model.save() }
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
        // Font
        let fontSize = CGFloat(model.editorFontSize)
        let font = NSFont(name: "SF Mono", size: fontSize)
            ?? NSFont(name: "Menlo", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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

        // Breathing room at top so line 1 isn't flush against the action bar
        textView.textContainerInset = NSSize(width: 0, height: 12)

        // Delegate
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.rulerView = rulerView
        context.coordinator.setupScrollObserver()

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
        let isReadOnly = hasFolds  // result mode is now editable (writes back to source files)

        let needsTextUpdate = !coordinator.isEditing && textView.string != displayText
        let needsModeUpdate = textView.isEditable == isReadOnly
        let currentFontSize = textView.font?.pointSize ?? 0
        let targetFontSize = CGFloat(model.editorFontSize)
        let needsFontUpdate = abs(currentFontSize - targetFontSize) > 0.1

        if needsFontUpdate {
            let newFont = NSFont(name: "SF Mono", size: targetFontSize)
                ?? NSFont(name: "Menlo", size: targetFontSize)
                ?? NSFont.monospacedSystemFont(ofSize: targetFontSize, weight: .regular)
            textView.font = newFont
            textView.typingAttributes[.font] = newFont
        }

        if needsTextUpdate || needsModeUpdate || needsFontUpdate {
            coordinator.isUpdatingText = true
            if model.pendingUndoableTransform && needsTextUpdate {
                model.pendingUndoableTransform = false
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                if textView.shouldChangeText(in: fullRange, replacementString: displayText) {
                    textView.textStorage?.replaceCharacters(in: fullRange, with: displayText)
                    textView.didChangeText()
                }
            } else {
                model.pendingUndoableTransform = false
                textView.string = displayText
            }
            coordinator.isUpdatingText = false
            textView.isEditable = !isReadOnly
            coordinator.applyHighlighting(to: textView)
            (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }

        // Keep fold state in sync for copy: override
        if let jv = textView as? JSONEditorTextView {
            jv.originalText = hasFolds ? baseText : nil
            jv.foldedLines = model.foldedLines
            jv.foldRanges = model.foldRanges
            jv.composeFileNames = flattenJSONPaths(model.workspaceFiles)
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

    private func flattenJSONPaths(_ files: [WorkspaceFile], prefix: String = "") -> [String] {
        files.flatMap { f -> [String] in
            let name = prefix.isEmpty ? f.name : "\(prefix)/\(f.name)"
            if f.isDirectory { return flattenJSONPaths(f.children, prefix: name) }
            return f.url.pathExtension.lowercased() == "json" ? [name] : []
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: NSTextView?
        weak var rulerView: LineNumberRulerView?
        var isEditing = false
        var isUpdatingText = false
        private var scrollObserver: NSObjectProtocol?
        private var findObserver: NSObjectProtocol?

        init(model: AppModel) {
            self.model = model
        }

        func setupScrollObserver() {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: .jsonViewScrollToLine,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let line = note.userInfo?["line"] as? Int else { return }
                let col = note.userInfo?["col"] as? Int ?? 1
                self.scrollToLine(line, col: col)
            }
            findObserver = NotificationCenter.default.addObserver(
                forName: .jsonViewFind,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self,
                      let query = note.userInfo?["query"] as? String,
                      !query.isEmpty else { return }
                let direction = note.userInfo?["direction"] as? String ?? "next"
                self.findInEditor(query: query, direction: direction)
            }
        }

        func scrollToLine(_ targetLine: Int, col: Int = 1) {
            guard let tv = textView else { return }
            let text = tv.string as NSString
            var currentLine = 1
            var lineStart = 0
            while lineStart < text.length && currentLine < targetLine {
                let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
                lineStart = lineRange.upperBound
                currentLine += 1
            }
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineLen = lineRange.length > 0 ? lineRange.length - 1 : 0
            // col == -1 → end of line; col >= 1 → 1-based column offset
            let colOffset = col < 0 ? lineLen : max(0, col - 1)
            let position = min(lineStart + colOffset, lineStart + lineLen)
            let range = NSRange(location: position, length: 0)
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
            tv.window?.makeFirstResponder(tv)
        }

        func findInEditor(query: String, direction: String) {
            guard let tv = textView else { return }
            let nsText = tv.string as NSString
            let cur = tv.selectedRange()
            let opts: NSString.CompareOptions = .caseInsensitive
            var found = NSRange(location: NSNotFound, length: 0)

            if direction == "next" {
                let start = cur.upperBound
                let tail = NSRange(location: start, length: nsText.length - start)
                found = nsText.range(of: query, options: opts, range: tail)
                if found.location == NSNotFound {
                    found = nsText.range(of: query, options: opts)
                }
            } else {
                let head = NSRange(location: 0, length: max(0, cur.location))
                found = nsText.range(of: query, options: [opts, .backwards], range: head)
                if found.location == NSNotFound {
                    found = nsText.range(of: query, options: [opts, .backwards])
                }
            }

            if found.location != NSNotFound {
                tv.scrollRangeToVisible(found)
                tv.setSelectedRange(found)
            }
        }

        deinit {
            if let obs = scrollObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = findObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingText else { return }
            guard let tv = notification.object as? NSTextView else { return }
            let text = tv.string

            // Result mode: write changes back to source files, then recompose
            if !model.isRawMode, let oldResult = model.resolvedCompose,
               let workspaceRoot = model.workspaceRoot {
                applyHighlighting(to: tv)
                rulerView?.needsDisplay = true
                let template = model.editorText
                let indent = model.indentSize
                DispatchQueue.global(qos: .userInitiated).async {
                    let modified = applyComposeWriteBack(
                        oldResult: oldResult,
                        newResult: text,
                        template: template,
                        workspaceRoot: workspaceRoot,
                        indent: indent
                    )
                    guard !modified.isEmpty else { return }
                    DispatchQueue.main.async {
                        if let sel = self.model.selectedFile, modified.contains(sel) {
                            self.model.reloadCurrentFile()
                        }
                        self.model.reparse()
                    }
                }
            } else {
                // Raw mode: normal edit
                isEditing = true
                model.editorText = text
                model.isDirty = true
                applyHighlighting(to: tv)
                rulerView?.needsDisplay = true
                if model.autoSave { model.save(explicit: false) }
                model.reparse()
                isEditing = false
            }

            // Trigger {{ compose path completion (raw mode only — meaningful in template files)
            if model.isRawMode || model.resolvedCompose == nil {
                let loc = tv.selectedRange().location
                if loc >= 2 {
                    let ns = text as NSString
                    let last2 = ns.substring(with: NSRange(location: loc - 2, length: 2))
                    if last2 == "{{" { tv.complete(nil) }
                }
            }
        }

        // MARK: Syntax highlighting

        func applyHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let text = storage.string
            let fullRange = NSRange(text.startIndex..., in: text)

            // Attribute changes must not register with the undo manager —
            // otherwise every re-highlight pollutes the undo stack.
            textView.undoManager?.disableUndoRegistration()
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
            textView.undoManager?.enableUndoRegistration()
        }

        // Bracket depth → color: yellow → cyan → mint → teal → indigo (cycles)
        private static let bracketColors: [NSColor] = [
            NSColor.systemYellow,
            NSColor.systemCyan,
            NSColor.systemMint,
            NSColor.systemTeal,
            NSColor.systemIndigo,
        ]

        private func tokenize(text: String, storage: NSTextStorage, font: NSFont) {
            let nsText = text as NSString
            let length = nsText.length

            var i = 0
            var depth = 0
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
                        if nc == 0x3A { // colon — it's a key
                            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
                        } else {
                            storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
                        }
                        break
                    }
                    if j >= length {
                        storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: range)
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
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: i, length: 4))
                    i += 4; continue
                }
                if char == "f" && nsText.length > i + 4 && nsText.substring(with: NSRange(location: i, length: 5)) == "false" {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: i, length: 5))
                    i += 5; continue
                }
                if char == "n" && nsText.length > i + 3 && nsText.substring(with: NSRange(location: i, length: 4)) == "null" {
                    storage.addAttribute(.foregroundColor, value: NSColor.systemGray, range: NSRange(location: i, length: 4))
                    i += 4; continue
                }

                // Opening brackets — color by current depth, then increment
                if char == "{" || char == "[" {
                    let color = Self.bracketColors[depth % Self.bracketColors.count]
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                    depth += 1
                    i += 1; continue
                }

                // Closing brackets — decrement depth, then color
                if char == "}" || char == "]" {
                    depth = max(0, depth - 1)
                    let color = Self.bracketColors[depth % Self.bracketColors.count]
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: i, length: 1))
                    i += 1; continue
                }

                // Colon / comma
                if char == ":" || char == "," {
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
        let totalLen = text.length
        let visibleRect = tv.visibleRect

        // Empty document: draw "1" at top and bail — no glyphs to query.
        if totalLen == 0 {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let numStr = "1" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            numStr.draw(in: NSRect(x: rulerWidth - strSize.width - 16, y: tv.textContainerInset.height,
                                   width: strSize.width, height: strSize.height), withAttributes: attrs)
            return
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Build line start offsets
        var lineStarts: [(line: Int, charIdx: Int)] = []
        var lineNum = 1
        var charIdx = 0

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
        guard totalLen > 0 else { return }
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
    static let jsonViewScrollToLine = Notification.Name("jsonViewScrollToLine")
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
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
