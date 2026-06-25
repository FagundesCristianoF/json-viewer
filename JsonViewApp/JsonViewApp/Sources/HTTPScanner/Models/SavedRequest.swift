import Foundation

struct SavedRequest: Codable, Identifiable {
    let id: UUID
    var name: String
    var curlText: String
    var optionsText: String
    var config: ScanConfig
    let createdAt: Date

    init(name: String, curlText: String, optionsText: String, config: ScanConfig) {
        self.id = UUID()
        self.name = name
        self.curlText = curlText
        self.optionsText = optionsText
        self.config = config
        self.createdAt = Date()
    }
}
