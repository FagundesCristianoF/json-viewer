import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {

    // MARK: - Inputs
    @Published var curlText: String = ""
    @Published var optionsText: String = ""
    @Published var config = ScanConfig()

    // MARK: - State
    @Published var results: [OptionResult] = []
    @Published var matchingEntries: [OptionEntry] = []
    @Published var progress = ScanProgress()
    @Published var isRunning = false
    @Published var errorMessage: String? = nil
    @Published var parseError: String? = nil
    @Published var logs: [String] = []

    // MARK: - History
    @Published var history: [HistoryEntry] = HistoryStore.shared.entries

    func restore(_ entry: HistoryEntry) {
        curlText = entry.curlText
        optionsText = entry.optionsText
        config = entry.config
        validateCurl()
    }

    func deleteHistory(id: UUID) {
        HistoryStore.shared.delete(id: id)
        history = HistoryStore.shared.entries
    }

    func clearHistory() {
        HistoryStore.shared.clear()
        history = HistoryStore.shared.entries
    }

    private func saveToHistory() {
        let label = HistoryStore.makeLabel(curlText: curlText, param: config.param)
        let entry = HistoryEntry(label: label, curlText: curlText, optionsText: optionsText, config: config)
        HistoryStore.shared.add(entry)
        history = HistoryStore.shared.entries
    }

    // MARK: - Selected result for detail view
    @Published var selectedResultID: String? = nil

    var selectedResult: OptionResult? {
        guard let id = selectedResultID else { return nil }
        return results.first { $0.id == id }
    }

    var filteredMatchJSON: String {
        let items = matchingEntries.map { $0.toOutputJSON() }
        return "[\n  \(items.joined(separator: ",\n  "))\n]"
    }

    // MARK: - Response cache (smart re-run)

    private struct CacheKey: Equatable {
        var curlText: String
        var optionsText: String
        var param: String
    }

    private var cachedResponses: [String: HTTPExecutor.Response] = [:]
    private var cacheKey: CacheKey? = nil

    // MARK: - Parsed state
    private var parsedCurl: ParsedCurl? = nil

    var optionCount: Int { parsedOptions.count }

    /// Top-level keys detected in the curl body — used to populate the param picker.
    var detectedBodyKeys: [String] {
        guard let body = (try? CurlParser.parse(curlText))?.data,
              let data = body.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        return dict.keys.sorted()
    }

    /// Options parsed from the options text using the configured id/name paths.
    var parsedOptions: [OptionEntry] {
        let idPath = config.optionIdPath.isEmpty ? "id" : config.optionIdPath
        let namePath = config.optionNamePath.isEmpty ? "displayName" : config.optionNamePath
        return OptionsParser.parse(optionsText, idPath: idPath, namePath: namePath)
    }

    /// Drives the sidebar list. Shows live results after a run; pending options before.
    var mergedForDisplay: [OptionResult] {
        results.isEmpty
            ? parsedOptions.map { OptionResult(id: $0.id, displayName: $0.displayName) }
            : results
    }

    /// JSONPath suggestions generated from the structure of the options JSON.
    var pathSuggestions: [String] {
        guard let data = optionsText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var suggestions: [String] = []
        func scan(_ obj: [String: Any], prefix: String) {
            for key in obj.keys.sorted() {
                let path = prefix.isEmpty ? "$.\(key)" : "\(prefix).\(key)"
                if let arr = obj[key] as? [Any], let first = arr.first as? [String: Any] {
                    for prop in first.keys.sorted() {
                        suggestions.append("\(path)[*].\(prop)")
                    }
                } else if let nested = obj[key] as? [String: Any] {
                    scan(nested, prefix: path)
                } else {
                    suggestions.append(path)
                }
            }
        }
        if let dict = json as? [String: Any] { scan(dict, prefix: "") }
        else if let arr = json as? [Any], let first = arr.first as? [String: Any] {
            for prop in first.keys.sorted() { suggestions.append("$[*].\(prop)") }
        }
        return suggestions
    }

    func validateCurl() {
        do {
            parsedCurl = try CurlParser.parse(curlText)
            parseError = nil
        } catch {
            parsedCurl = nil
            parseError = error.localizedDescription
        }
    }

    // MARK: - Run

    private var scanTask: Task<Void, Never>? = nil

    func run(force: Bool = false) {
        guard !isRunning else { return }
        parseError = nil
        errorMessage = nil

        let curl: ParsedCurl
        do {
            curl = try CurlParser.parse(curlText)
        } catch {
            parseError = error.localizedDescription
            return
        }

        let options = parsedOptions
        guard !options.isEmpty else {
            errorMessage = "No options provided"
            return
        }

        let cfg = config
        let newKey = CacheKey(curlText: curlText, optionsText: optionsText, param: cfg.param)

        // Smart re-run: same curl+options+param, only filters changed
        if !force, let existing = cacheKey, existing == newKey, !cachedResponses.isEmpty {
            saveToHistory()
            let total = options.count
            isRunning = true
            progress = ScanProgress(current: total, total: total)
            results = options.map { OptionResult(id: $0.id, displayName: $0.displayName) }
            matchingEntries = []
            logs = []
            selectedResultID = nil

            for (i, opt) in options.enumerated() {
                if let resp = cachedResponses[opt.id] {
                    applyResponse(resp, at: i, optionId: opt.id, displayName: opt.displayName, pageScanned: nil, config: cfg)
                } else {
                    results[i].status = .skipped("not in cache")
                }
            }
            buildMatchingEntries(options: options, config: cfg)
            isRunning = false
            return
        }

        saveToHistory()

        let total = options.count
        let workers = min(max(cfg.workers, 1), 64)

        isRunning = true
        progress = ScanProgress(current: 0, total: total)
        results = options.map { OptionResult(id: $0.id, displayName: $0.displayName) }
        matchingEntries = []
        logs = []
        selectedResultID = nil
        var freshCache: [String: HTTPExecutor.Response] = [:]

        scanTask = Task {
            let session = HTTPExecutor.makeSession(insecure: curl.insecure)

            await withTaskGroup(of: (Int, HTTPExecutor.FetchResult).self) { group in
                var submitted = 0
                var completed = 0

                func submit(_ idx: Int) {
                    let opt = options[idx]
                    group.addTask {
                        await MainActor.run {
                            if idx < self.results.count { self.results[idx].status = .running }
                        }
                        let result = await HTTPExecutor.fetch(
                            curl: curl,
                            param: cfg.param,
                            option: opt,
                            config: cfg,
                            session: session
                        )
                        return (idx, result)
                    }
                }

                let initial = min(workers, total)
                for i in 0..<initial {
                    submit(i)
                    submitted += 1
                }

                var pending: [(Int, HTTPExecutor.FetchResult)] = []

                for await (idx, fetchResult) in group {
                    completed += 1
                    pending.append((idx, fetchResult))

                    if submitted < total {
                        submit(submitted)
                        submitted += 1
                    }

                    // Flush in batches to reduce UI churn
                    if pending.count >= 8 || completed == total {
                        let batch = pending
                        pending = []
                        await MainActor.run {
                            for (i, fr) in batch {
                                if let resp = fr.response { freshCache[fr.optionId] = resp }
                                applyFetchResult(fr, at: i, config: cfg)
                            }
                            progress = ScanProgress(current: completed, total: total)
                        }
                    }

                    if Task.isCancelled { break }
                }

                if !pending.isEmpty {
                    let batch = pending
                    await MainActor.run {
                        for (i, fr) in batch {
                            if let resp = fr.response { freshCache[fr.optionId] = resp }
                            applyFetchResult(fr, at: i, config: cfg)
                        }
                        progress = ScanProgress(current: completed, total: total)
                    }
                }
            }

            cachedResponses = freshCache
            cacheKey = newKey

            buildMatchingEntries(options: options, config: cfg)
            isRunning = false
        }
    }

    func forceRun() {
        run(force: true)
    }

    private func buildMatchingEntries(options: [OptionEntry], config: ScanConfig) {
        if config.isFilterMode {
            var matching: [OptionEntry] = []
            for (i, result) in results.enumerated() {
                if case .matched = result.status {
                    matching.append(options[i])
                }
            }
            matchingEntries = matching
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        isRunning = false
    }

    // MARK: - Apply result

    private func applyFetchResult(_ fr: HTTPExecutor.FetchResult, at idx: Int, config: ScanConfig) {
        guard idx < results.count else { return }

        if let error = fr.error {
            let msg = error.localizedDescription
            results[idx].status = .error(msg)
            log("[\(fr.displayName ?? fr.optionId)] ERROR: \(msg)")
            return
        }

        guard let resp = fr.response else {
            results[idx].status = .error("No response")
            return
        }

        applyResponse(resp, at: idx, optionId: fr.optionId, displayName: fr.displayName, pageScanned: fr.pageScanned, config: config)
    }

    private func applyResponse(_ resp: HTTPExecutor.Response, at idx: Int, optionId: String, displayName: String?, pageScanned: Int?, config: ScanConfig) {
        guard idx < results.count else { return }

        results[idx].statusCode = resp.statusCode
        results[idx].responseBody = resp.body
        results[idx].responseHeaders = resp.headers
        results[idx].pageScanned = pageScanned
        results[idx].prettyBody = Self.prettify(resp.body)

        if config.isFilterMode {
            let parsedData: Any?
            if let data = resp.body.data(using: .utf8) {
                parsedData = try? JSONSerialization.jsonObject(with: data)
            } else {
                parsedData = nil
            }

            if parsedData == nil {
                results[idx].status = .skipped("non-JSON (status \(resp.statusCode))")
                log("[\(optionId)] skip: non-JSON response (status \(resp.statusCode))")
                return
            }

            let filterArgs = Filters.FilterArgs(
                jsonpath: config.effectiveJsonpath,
                requireResultsPath: config.effectiveRequireResultsPath
            )

            if Filters.matches(response: results[idx], data: parsedData, args: filterArgs) {
                results[idx].status = .matched
            } else {
                results[idx].status = .notMatched
            }
        } else {
            results[idx].status = .matched
        }
    }

    private func log(_ msg: String) {
        logs.append(msg)
    }

    private static func prettify(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return str
    }

    // MARK: - Import helpers

    func importCurlFile(_ url: URL) {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            curlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func importOptionsFile(_ url: URL) {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            optionsText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
