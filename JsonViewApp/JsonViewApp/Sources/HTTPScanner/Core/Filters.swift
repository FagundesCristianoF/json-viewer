import Foundation

enum Filters {

    struct FilterArgs {
        var jsonpath: String?
        var requireResultsPath: String?
    }

    static func matches(response: OptionResult, data: Any?, args: FilterArgs) -> Bool {
        guard args.jsonpath != nil || args.requireResultsPath != nil else { return true }

        if let path = args.requireResultsPath {
            guard response.statusCode == 200, let data else { return false }
            let matched = (try? JSONPathEvaluator.hasMatches(path: path, in: data)) ?? false
            if !matched { return false }
        }

        if let path = args.jsonpath {
            guard let data else { return false }
            let matched = (try? JSONPathEvaluator.hasMatches(path: path, in: data)) ?? false
            if !matched { return false }
        }

        return true
    }
}
