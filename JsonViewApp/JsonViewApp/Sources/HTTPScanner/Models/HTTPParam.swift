import Foundation

struct HTTPParam: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var key: String
    var value: String
    var isEnabled: Bool = true

    init(key: String, value: String, isEnabled: Bool = true) {
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
    }
}
