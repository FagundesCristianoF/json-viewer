import Foundation

struct HistoryEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var label: String          // auto-derived from URL host + param
    var curlText: String
    var optionsText: String
    var config: ScanConfig

    init(label: String, curlText: String, optionsText: String, config: ScanConfig) {
        self.id = UUID()
        self.timestamp = Date()
        self.label = label
        self.curlText = curlText
        self.optionsText = optionsText
        self.config = config
    }
}

