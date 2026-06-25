import Foundation
import Combine

final class SavedRequestsStore: ObservableObject {

    static let shared = SavedRequestsStore()

    @Published private(set) var items: [SavedRequest] = []

    private var fileURL: URL {
        Preferences.shared.savedRequestsFileURL
    }

    private init() { load() }

    // MARK: - Public API

    @discardableResult
    func add(name: String, curlText: String, optionsText: String, config: ScanConfig) -> SavedRequest {
        let entry = SavedRequest(name: name, curlText: curlText, optionsText: optionsText, config: config)
        items.insert(entry, at: 0)
        save()
        return entry
    }

    func update(id: UUID, name: String, curlText: String, optionsText: String, config: ScanConfig) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].name = name
        items[idx].curlText = curlText
        items[idx].optionsText = optionsText
        items[idx].config = config
        save()
    }

    func rename(id: UUID, name: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].name = name
        save()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func item(id: UUID) -> SavedRequest? {
        items.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedRequest].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        Preferences.shared.ensureHistoryDirectoryExists()
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
