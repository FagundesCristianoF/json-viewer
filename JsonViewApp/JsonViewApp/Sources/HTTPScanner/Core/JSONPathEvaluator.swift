import Foundation

enum JSONPathError: Error {
    case invalidPath(String)
}

// Supports the subset used by curl_param_scan:
//   $.field
//   $.field.nested
//   $.array[*]
//   $.array[?(@.field == true|false|"str"|number)]
//   $.array[?(@.nested.field == value)]
//   Combined: $.array[?(@.x == true)].field
enum JSONPathEvaluator {

    static func hasMatches(path: String, in data: Any) throws -> Bool {
        !(try evaluate(path: path, in: data)).isEmpty
    }

    static func evaluate(path: String, in data: Any) throws -> [Any] {
        guard path.hasPrefix("$") else { throw JSONPathError.invalidPath("must start with $") }
        let segments = try parse(String(path.dropFirst()))
        return apply(segments: segments, to: [data])
    }

    // MARK: - Segment types

    private enum Segment {
        case key(String)
        case wildcard              // [*]
        case filter(FilterExpr)   // [?(@.path op value)]
    }

    private struct FilterExpr {
        let keyPath: [String]   // e.g. ["info","multipleConditionItems"]
        let op: Op
        let rhs: RHSValue
    }

    private enum Op { case eq, neq }

    private enum RHSValue {
        case bool(Bool)
        case string(String)
        case number(Double)
        case null
    }

    // MARK: - Parser

    private static func parse(_ path: String) throws -> [Segment] {
        var segments: [Segment] = []
        var rest = path

        while !rest.isEmpty {
            if rest.hasPrefix(".") {
                rest = String(rest.dropFirst())
                // read key until next '.' or '['
                let end = rest.firstIndex(where: { $0 == "." || $0 == "[" }) ?? rest.endIndex
                let key = String(rest[..<end])
                if !key.isEmpty { segments.append(.key(key)) }
                rest = String(rest[end...])
            } else if rest.hasPrefix("[") {
                // find matching ]
                guard let close = rest.firstIndex(of: "]") else {
                    throw JSONPathError.invalidPath("unmatched [")
                }
                let inner = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = String(rest[rest.index(after: close)...])

                if inner == "*" {
                    segments.append(.wildcard)
                } else if inner.hasPrefix("?(") && inner.hasSuffix(")") {
                    let expr = String(inner.dropFirst(2).dropLast())
                    segments.append(.filter(try parseFilter(expr)))
                }
                // numeric index: skip (not needed by spec)
            } else {
                // bare key segment without leading dot
                let end = rest.firstIndex(where: { $0 == "." || $0 == "[" }) ?? rest.endIndex
                let key = String(rest[..<end])
                if !key.isEmpty { segments.append(.key(key)) }
                rest = String(rest[end...])
            }
        }
        return segments
    }

    private static func parseFilter(_ expr: String) throws -> FilterExpr {
        // e.g. @.multiplePromotions == true
        //       @.info.multipleConditionItems == true
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@.") else {
            throw JSONPathError.invalidPath("filter must start with @.")
        }
        // Detect operator
        let opStr: String
        let opEnum: Op
        if let r = trimmed.range(of: " != ") {
            opStr = " != "
            opEnum = .neq
            _ = r
        } else if let _ = trimmed.range(of: " == ") {
            opStr = " == "
            opEnum = .eq
        } else {
            throw JSONPathError.invalidPath("unsupported filter op in: \(trimmed)")
        }

        guard let opRange = trimmed.range(of: opStr) else {
            throw JSONPathError.invalidPath("filter parse error")
        }

        let lhsPart = String(trimmed[trimmed.startIndex..<opRange.lowerBound])  // @.a.b
        let rhsPart = String(trimmed[opRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        let keyPath = lhsPart.dropFirst(2).split(separator: ".").map(String.init)  // drop "@."
        let rhs = parseRHS(rhsPart)

        return FilterExpr(keyPath: keyPath, op: opEnum, rhs: rhs)
    }

    private static func parseRHS(_ s: String) -> RHSValue {
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if s == "null" { return .null }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return .string(String(s.dropFirst().dropLast()))
        }
        if let n = Double(s) { return .number(n) }
        return .string(s)
    }

    // MARK: - Evaluator

    private static func apply(segments: [Segment], to nodes: [Any]) -> [Any] {
        var current = nodes
        for seg in segments {
            current = step(seg, on: current)
        }
        return current
    }

    private static func step(_ seg: Segment, on nodes: [Any]) -> [Any] {
        var out: [Any] = []
        for node in nodes {
            switch seg {
            case .key(let k):
                if let dict = node as? [String: Any], let val = dict[k] {
                    out.append(val)
                }
            case .wildcard:
                if let arr = node as? [Any] {
                    out.append(contentsOf: arr)
                }
            case .filter(let f):
                if let arr = node as? [Any] {
                    out.append(contentsOf: arr.filter { matches($0, filter: f) })
                }
            }
        }
        return out
    }

    private static func matches(_ node: Any, filter: FilterExpr) -> Bool {
        guard let dict = node as? [String: Any] else { return false }
        // walk key path
        var current: Any = dict
        for key in filter.keyPath {
            guard let d = current as? [String: Any], let v = d[key] else { return false }
            current = v
        }
        return compare(current, op: filter.op, rhs: filter.rhs)
    }

    private static func compare(_ lhs: Any, op: Op, rhs: RHSValue) -> Bool {
        let result: Bool
        switch rhs {
        case .bool(let b):
            if let lb = lhs as? Bool { result = lb == b }
            else { result = false }
        case .string(let s):
            if let ls = lhs as? String { result = ls == s }
            else { result = false }
        case .number(let n):
            if let ln = lhs as? Double { result = ln == n }
            else if let li = lhs as? Int { result = Double(li) == n }
            else { result = false }
        case .null:
            result = lhs is NSNull
        }
        return op == .eq ? result : !result
    }
}
