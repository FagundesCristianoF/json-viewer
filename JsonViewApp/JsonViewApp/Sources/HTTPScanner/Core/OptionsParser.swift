import Foundation

enum OptionsParser {

    static func parse(_ raw: String, idPath: String = "id", namePath: String = "displayName") -> [OptionEntry] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

            // JSONPath mode when either path starts with $
            if idPath.hasPrefix("$") || namePath.hasPrefix("$") {
                return extractWithJSONPath(from: json, idPath: idPath, namePath: namePath)
            }

            return extractEntries(from: json, idPath: idPath, namePath: namePath)
        }

        // Plain comma-separated IDs
        return trimmed.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { OptionEntry(id: $0, displayName: nil) }
    }

    // MARK: - JSONPath mode

    private static func extractWithJSONPath(from json: Any, idPath: String, namePath: String) -> [OptionEntry] {
        let ids: [String]
        if idPath.hasPrefix("$") {
            ids = (try? JSONPathEvaluator.evaluate(path: idPath, in: json))?
                .compactMap { $0 is NSNull ? nil : "\($0)" } ?? []
        } else {
            ids = []
        }

        let names: [String?]
        if namePath.hasPrefix("$") {
            names = (try? JSONPathEvaluator.evaluate(path: namePath, in: json))?
                .map { $0 is NSNull ? nil : "\($0)" } ?? []
        } else {
            names = Array(repeating: nil, count: ids.count)
        }

        var seen: Set<String> = []
        return ids.enumerated().compactMap { (i, id) in
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name: String? = i < names.count ? names[i] : nil
            return OptionEntry(id: id, displayName: name)
        }
    }

    // MARK: - Simple dot-notation mode

    private static func extractEntries(from json: Any, idPath: String, namePath: String) -> [OptionEntry] {
        var entries: [OptionEntry] = []
        var seen: Set<String> = []

        func addDict(_ dict: [String: Any]) {
            guard let id = extractValue(dict, path: idPath), !id.isEmpty else { return }
            if seen.insert(id).inserted {
                let name = extractValue(dict, path: namePath)
                entries.append(OptionEntry(id: id, displayName: name))
            }
        }

        if let arr = json as? [Any] {
            for item in arr {
                if let d = item as? [String: Any] { addDict(d) }
                else if let s = item as? String, seen.insert(s).inserted {
                    entries.append(OptionEntry(id: s, displayName: nil))
                }
            }
        } else if let dict = json as? [String: Any] {
            addDict(dict)
        }

        return entries
    }

    static func extractValue(_ dict: [String: Any], path: String) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = dict
        for part in parts {
            guard let d = current as? [String: Any], let next = d[part] else { return nil }
            current = next
        }
        if current is NSNull { return nil }
        return "\(current)"
    }
}
