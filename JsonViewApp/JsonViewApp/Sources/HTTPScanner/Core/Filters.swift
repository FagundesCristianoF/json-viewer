import Foundation

enum Filters {

    struct FilterArgs {
        var jsonpath: String?
        var requireGroups: [[String]]   // outer = AND, inner = OR
    }

    static func matches(response: OptionResult, data: Any?, args: FilterArgs) -> Bool {
        let hasFilters = args.jsonpath != nil || !args.requireGroups.isEmpty
        guard hasFilters else { return true }

        // Groups: AND — all groups must match; rules within a group: OR — any rule suffices
        for group in args.requireGroups {
            guard response.statusCode == 200, let data else { return false }
            let groupMatched = group.contains { path in
                (try? JSONPathEvaluator.hasMatches(path: path, in: data)) ?? false
            }
            if !groupMatched { return false }
        }

        if let path = args.jsonpath {
            guard let data else { return false }
            let matched = (try? JSONPathEvaluator.hasMatches(path: path, in: data)) ?? false
            if !matched { return false }
        }

        return true
    }
}
