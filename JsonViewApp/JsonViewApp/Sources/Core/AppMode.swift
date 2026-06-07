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
    @Published var mode: AppMode = AppMode(
        rawValue: UserDefaults.standard.string(forKey: "devKitMode") ?? ""
    ) ?? .jsonEditor {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "devKitMode") }
    }

    let editorModel = AppModel()
    let scannerModel = ScanViewModel()
}
