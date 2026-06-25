import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var vm: ScanViewModel

    var body: some View {
        VStack(spacing: 0) {
            if vm.isRunning || !vm.results.isEmpty {
                // Progress bar
                if vm.isRunning || vm.progress.total > 0 {
                    ProgressHeader()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    Divider()
                }

                if let selected = vm.selectedResult {
                    ResponseDetailView(result: selected)
                } else if vm.config.isFilterMode && !vm.isRunning && vm.progress.total > 0 && vm.matchingEntries.isEmpty {
                    NoMatchesView()
                } else if vm.config.isFilterMode && !vm.isRunning && !vm.matchingEntries.isEmpty {
                    FilteredResultsView()
                } else if !vm.config.isFilterMode {
                    UnfilteredResultsHint()
                } else {
                    EmptySelectionView()
                }
            } else {
                ScannerEmptyStateView()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Progress header

struct ProgressHeader: View {
    @EnvironmentObject var vm: ScanViewModel

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: vm.progress.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .tint(.accentColor)

            Text("\(vm.progress.current)/\(vm.progress.total)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            if vm.isRunning {
                Button("Stop") { vm.stop() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            } else {
                statsView
            }
        }
    }

    var statsView: some View {
        let matched = vm.results.filter { if case .matched = $0.status { return true }; return false }.count
        let errors = vm.results.filter { if case .error = $0.status { return true }; return false }.count
        return HStack(spacing: 8) {
            if matched > 0 {
                Label("\(matched)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
            }
            if errors > 0 {
                Label("\(errors)", systemImage: "xmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Response detail

struct ResponseDetailView: View {
    let result: OptionResult
    @EnvironmentObject var vm: ScanViewModel
    @State private var showRaw = false
    @State private var copied = false

    private enum JSONPathResult {
        case noFilter
        case extracted(String)
        case empty        // valid path, zero matches
        case invalid      // bad path or parse error → fall through to full JSON
    }

    private var jsonPathResult: JSONPathResult {
        guard !showRaw else { return .noFilter }
        let displayPath = vm.config.effectiveJsonpath
        let requirePaths = vm.config.effectiveRequireGroups.flatMap { $0 }
        guard displayPath != nil || !requirePaths.isEmpty else { return .noFilter }

        guard let body = result.responseBody,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return .invalid }

        var merged: [Any] = []
        if let path = displayPath {
            guard let m = try? JSONPathEvaluator.evaluate(path: path, in: json) else { return .invalid }
            merged.append(contentsOf: m)
        }
        for path in requirePaths {
            if let m = try? JSONPathEvaluator.evaluate(path: path, in: json) {
                merged.append(contentsOf: m)
            }
        }

        if merged.isEmpty { return .empty }
        guard let pretty = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else { return .invalid }
        return .extracted(str)
    }

    var copyText: String {
        if showRaw { return result.responseBody ?? "" }
        if case .extracted(let str) = jsonPathResult { return str }
        return result.prettyBody ?? result.responseBody ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                StatusDot(status: result.status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.displayName ?? result.id)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if result.displayName != nil {
                        Text(result.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if case .extracted = jsonPathResult {
                    Text(String(localized: "results.chip.jsonpath"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                } else if case .empty = jsonPathResult {
                    Text(String(localized: "results.chip.no_matches"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                if let code = result.statusCode {
                    let tint = statusColor(code)
                    Text("\(code)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.15))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                }
                Toggle("Raw", isOn: $showRaw)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy response")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Body
            if case .error(let msg) = result.status, result.responseBody == nil {
                ErrorDetailView(message: msg)
            } else if showRaw, let body = result.responseBody {
                MonoTextView(text: body)
            } else if case .extracted(let str) = jsonPathResult {
                JSONColorView(text: str)
                    .id("extracted-\(result.id)-\(vm.config.jsonpath)-\(vm.config.requireGroups.hashValue)")
            } else if case .empty = jsonPathResult {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text(String(localized: "results.chip.no_matches"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Text(vm.config.jsonpath)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let body = result.responseBody, result.prettyBody != nil {
                JSONColorView(text: body)
                    .id("body-\(result.id)")
            } else if let body = result.responseBody {
                MonoTextView(text: body)
            } else {
                Text(String(localized: "results.no_response_body"))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// HTTP status class → color: 2xx green, 3xx blue, 4xx orange, 5xx red.
func statusColor(_ code: Int) -> Color {
    switch code {
    case 200..<300: return .green
    case 300..<400: return .blue
    case 400..<500: return .orange
    case 500..<600: return .red
    default:        return .secondary
    }
}

// MARK: - Error detail

struct ErrorDetailView: View {
    let message: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(.horizontal, 24)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy error", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Filtered results JSON output

struct FilteredResultsView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("\(vm.matchingEntries.count) matched", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.filteredMatchJSON, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                Text(vm.filteredMatchJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }
}

// MARK: - Hints & empty states

struct UnfilteredResultsHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click").font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("Select an option from the sidebar to view its response")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("Filter mode — matching options will appear here")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct NoMatchesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No matches found")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            Text("No options matched the active filters.\nTry adjusting the JSONPath or filter criteria.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ScannerEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("HTTP Scanner")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            Text("Paste a curl command in the sidebar,\nadd option IDs, configure filters, then run.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
