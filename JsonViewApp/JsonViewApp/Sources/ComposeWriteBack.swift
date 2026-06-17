import Foundation

// MARK: - Source Map

/// Maps JSON path strings (e.g. "0", "items/0") to the source file URL
/// whose content was inlined at that position in the composed result.
typealias ComposeSourceMap = [String: URL]

/// Build a source map by replacing `{{file}}` tokens with sentinel strings,
/// parsing the sentinel-ized template as JSON, then recording each sentinel's path.
func buildComposeSourceMap(template: String, workspaceRoot: URL) -> ComposeSourceMap {
    var sentinelToFile: [String: String] = [:]
    var counter = 0
    var modified = template

    guard let pattern = try? NSRegularExpression(pattern: "\\{\\{([^}]+)\\}\\}") else { return [:] }
    let full = NSRange(modified.startIndex..., in: modified)
    let matches = pattern.matches(in: modified, range: full)

    for match in matches.reversed() {
        guard let wholeRange = Range(match.range(at: 0), in: modified),
              let nameRange  = Range(match.range(at: 1), in: modified) else { continue }
        let filename = String(modified[nameRange]).trimmingCharacters(in: .whitespaces)
        let sentinel = "__BRACE_\(counter)__"
        sentinelToFile[sentinel] = filename
        counter += 1
        modified = modified.replacingCharacters(in: wholeRange, with: "\"\(sentinel)\"")
    }

    guard let data = modified.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) else { return [:] }

    var result: ComposeSourceMap = [:]
    findSentinels(in: json, path: [], map: sentinelToFile, root: workspaceRoot, out: &result)
    return result
}

private func findSentinels(in json: Any, path: [String], map: [String: String], root: URL, out: inout ComposeSourceMap) {
    if let str = json as? String, let filename = map[str] {
        out[path.joined(separator: "/")] = root.appendingPathComponent(filename)
    } else if let dict = json as? [String: Any] {
        for (key, val) in dict { findSentinels(in: val, path: path + [key], map: map, root: root, out: &out) }
    } else if let arr = json as? [Any] {
        for (i, val) in arr.enumerated() { findSentinels(in: val, path: path + ["\(i)"], map: map, root: root, out: &out) }
    }
}

// MARK: - JSON Diff

struct JSONChange {
    let path: [String]
    let newValue: Any
}

func diffJSON(old: Any, new: Any, path: [String] = []) -> [JSONChange] {
    if let oldDict = old as? [String: Any], let newDict = new as? [String: Any] {
        return Set(oldDict.keys).union(newDict.keys).flatMap { key -> [JSONChange] in
            let sub = path + [key]
            switch (oldDict[key], newDict[key]) {
            case (let o?, let n?): return diffJSON(old: o, new: n, path: sub)
            case (nil, let n?):    return [JSONChange(path: sub, newValue: n)]
            default:               return []
            }
        }
    }
    if let oldArr = old as? [Any], let newArr = new as? [Any] {
        return (0..<max(oldArr.count, newArr.count)).flatMap { i -> [JSONChange] in
            let sub = path + ["\(i)"]
            switch (i < oldArr.count ? oldArr[i] : nil, i < newArr.count ? newArr[i] : nil) {
            case (let o?, let n?): return diffJSON(old: o, new: n, path: sub)
            case (nil, let n?):    return [JSONChange(path: sub, newValue: n)]
            default:               return []
            }
        }
    }
    return jsonEqual(old, new) ? [] : [JSONChange(path: path, newValue: new)]
}

private func jsonEqual(_ a: Any, _ b: Any) -> Bool {
    switch (a, b) {
    case (let a as String,   let b as String):   return a == b
    case (let a as NSNumber, let b as NSNumber): return a == b
    case (is NSNull,         is NSNull):         return true
    default:                                     return false
    }
}

// MARK: - Write-back

/// Apply edits made in result mode back to source files.
/// Returns the set of URLs that were modified.
@discardableResult
func applyComposeWriteBack(
    oldResult: String,
    newResult: String,
    template: String,
    workspaceRoot: URL,
    indent: Int
) -> Set<URL> {
    guard let oldData = oldResult.data(using: .utf8),
          let newData = newResult.data(using: .utf8),
          let oldJSON = try? JSONSerialization.jsonObject(with: oldData),
          let newJSON = try? JSONSerialization.jsonObject(with: newData) else { return [] }

    let changes = diffJSON(old: oldJSON, new: newJSON)
    guard !changes.isEmpty else { return [] }

    let sourceMap = buildComposeSourceMap(template: template, workspaceRoot: workspaceRoot)
    var modified = Set<URL>()

    for change in changes {
        // Find longest prefix of change.path that's in the source map
        var ownerURL: URL? = nil
        var subPath: [String] = change.path

        for len in stride(from: change.path.count, through: 1, by: -1) {
            let prefix = change.path.prefix(len).joined(separator: "/")
            if let url = sourceMap[prefix] {
                ownerURL = url
                subPath = Array(change.path.dropFirst(len))
                break
            }
        }

        // Also check exact match (whole value replaced)
        if ownerURL == nil {
            let exact = change.path.joined(separator: "/")
            ownerURL = sourceMap[exact]
            if ownerURL != nil { subPath = [] }
        }

        guard let fileURL = ownerURL else { continue }
        if patchJSONFile(at: fileURL, path: subPath, newValue: change.newValue, indent: indent) {
            modified.insert(fileURL)
        }
    }

    return modified
}

// MARK: - File patch (text-level, preserves key order and formatting)

private func patchJSONFile(at url: URL, path: [String], newValue: Any, indent: Int) -> Bool {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
    guard let updated = replaceValueInJSON(text: content, path: path, newValue: newValue) else { return false }
    do {
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return true
    } catch { return false }
}

/// Navigate JSON text and replace the scalar value at `path` in-place.
/// Preserves all whitespace, key order, and formatting.
private func replaceValueInJSON(text: String, path: [String], newValue: Any) -> String? {
    var scanner = JSONTextScanner(text: text)
    guard let range = scanner.findValueRange(path: path) else { return nil }
    let encoded = encodeScalar(newValue)
    return text.replacingCharacters(in: range, with: encoded)
}

private func encodeScalar(_ value: Any) -> String {
    switch value {
    case let s as String:
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        return n.stringValue
    case is NSNull: return "null"
    default:
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let s = String(data: data, encoding: .utf8) { return s }
        return "null"
    }
}

// MARK: - JSON Text Scanner

private struct JSONTextScanner {
    let text: String
    var idx: String.Index

    init(text: String) { self.text = text; self.idx = text.startIndex }

    mutating func findValueRange(path: [String]) -> Range<String.Index>? {
        skipWhitespace()
        guard !path.isEmpty else { return valueRange() }
        let component = path[0]; let rest = Array(path.dropFirst())
        guard let ch = current() else { return nil }

        if ch == "{" {
            advance()
            while true {
                skipWhitespace()
                guard let c = current(), c != "}" else { return nil }
                guard let key = scanString() else { return nil }
                skipWhitespace(); guard consume(":") else { return nil }; skipWhitespace()
                if key == component {
                    return rest.isEmpty ? valueRange() : findValueRange(path: rest)
                } else {
                    guard skipValue() else { return nil }
                    skipWhitespace(); _ = consume(",")
                }
            }
        } else if ch == "[", let i = Int(component) {
            advance()
            for idx in 0... {
                skipWhitespace()
                guard let c = current(), c != "]" else { return nil }
                if idx == i {
                    return rest.isEmpty ? valueRange() : findValueRange(path: rest)
                } else {
                    guard skipValue() else { return nil }
                    skipWhitespace(); _ = consume(",")
                }
            }
        }
        return nil
    }

    mutating func valueRange() -> Range<String.Index>? {
        let start = idx
        guard skipValue() else { return nil }
        return start..<idx
    }

    @discardableResult
    mutating func skipValue() -> Bool {
        skipWhitespace()
        guard let ch = current() else { return false }
        switch ch {
        case "\"": return scanString() != nil
        case "{":
            advance()
            while true {
                skipWhitespace()
                guard let c = current() else { return false }
                if c == "}" { advance(); return true }
                guard scanString() != nil else { return false }
                skipWhitespace(); guard consume(":") else { return false }; skipWhitespace()
                guard skipValue() else { return false }
                skipWhitespace(); _ = consume(",")
            }
        case "[":
            advance()
            while true {
                skipWhitespace()
                guard let c = current() else { return false }
                if c == "]" { advance(); return true }
                guard skipValue() else { return false }
                skipWhitespace(); _ = consume(",")
            }
        default:
            // number, bool, null
            while let c = current(), !",}] \t\n\r".contains(c) { advance() }
            return true
        }
    }

    mutating func scanString() -> String? {
        guard consume("\"") else { return nil }
        var result = ""
        while let ch = current() {
            if ch == "\"" { advance(); return result }
            if ch == "\\" {
                advance()
                guard let esc = current() else { return nil }
                switch esc {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n":  result.append("\n")
                case "r":  result.append("\r")
                case "t":  result.append("\t")
                default:   result.append(esc)
                }
                advance()
            } else {
                result.append(ch); advance()
            }
        }
        return nil
    }

    mutating func skipWhitespace() {
        while let ch = current(), ch.isWhitespace { advance() }
    }

    @discardableResult
    mutating func consume(_ char: Character) -> Bool {
        guard current() == char else { return false }
        advance(); return true
    }

    func current() -> Character? {
        guard idx < text.endIndex else { return nil }
        return text[idx]
    }

    mutating func advance() {
        guard idx < text.endIndex else { return }
        text.formIndex(after: &idx)
    }
}

