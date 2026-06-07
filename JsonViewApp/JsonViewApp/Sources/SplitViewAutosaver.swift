import SwiftUI
import AppKit

/// Invisible background view that finds the nearest enclosing NSSplitView
/// and sets its autosaveName, enabling AppKit to persist divider positions.
struct SplitViewAutosaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up the NSView hierarchy to find the NSSplitView.
        DispatchQueue.main.async {
            var current: NSView? = nsView.superview
            while let v = current {
                if let split = v as? NSSplitView, split.autosaveName == nil {
                    split.autosaveName = NSSplitView.AutosaveName(name)
                    return
                }
                current = v.superview
            }
        }
    }
}
