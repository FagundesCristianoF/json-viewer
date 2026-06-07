import Foundation

final class HistoryStore {

    static let shared = HistoryStore()
    private let maxEntries = 50

    private var fileURL: URL {
        Preferences.shared.historyFileURL
    }

    private(set) var entries: [HistoryEntry] = []

    private init() { load() }

    // MARK: - Public API

    func add(_ entry: HistoryEntry) {
        // Deduplicate by curl+options+param (keep most recent)
        entries.removeAll {
            $0.curlText == entry.curlText &&
            $0.optionsText == entry.optionsText &&
            $0.config.param == entry.config.param
        }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Label helper

    static func makeLabel(curlText: String, param: String) -> String {
        guard let curl = try? CurlParser.parse(curlText),
              let host = URLComponents(string: curl.url)?.host else {
            return param
        }
        let path = URLComponents(string: curl.url)?.path ?? ""
        let short = path.split(separator: "/").last.map(String.init) ?? ""
        return short.isEmpty ? "\(host) · \(param)" : "\(short) · \(param)"
    }
}
