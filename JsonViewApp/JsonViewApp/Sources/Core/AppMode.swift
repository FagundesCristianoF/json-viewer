import Foundation
import SwiftUI

enum AppMode: String, CaseIterable {
    case jsonEditor
    case httpScanner

    var label: String {
        switch self {
        case .jsonEditor:  return "JSON Editor"
        case .httpScanner: return "HTTP Scanner"
        }
    }

    var icon: String {
        switch self {
        case .jsonEditor:  return "curlybraces"
        case .httpScanner: return "network"
        }
    }
}

@MainActor
final class DevKitModel: ObservableObject {
    @Published var mode: AppMode = .jsonEditor {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "devKitMode") }
    }

    let editorModel = AppModel()
    let scannerModel = ScanViewModel()

    init() {
        if let raw = UserDefaults.standard.string(forKey: "devKitMode"),
           let saved = AppMode(rawValue: raw) {
            mode = saved
        }
    }
}
