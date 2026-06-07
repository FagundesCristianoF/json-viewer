import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var vm: ScanViewModel
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var hoveredID: UUID? = nil

    private var filtered: [HistoryEntry] {
        guard !searchText.isEmpty else { return vm.history }
        return vm.history.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.config.param.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !vm.history.isEmpty {
                    Button {
                        vm.clearHistory()
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search history…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(vm.history.isEmpty ? "No history yet" : "No results")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { entry in
                            HistoryRow(entry: entry, isHovered: hoveredID == entry.id)
                                .contentShape(Rectangle())
                                .onHover { hoveredID = $0 ? entry.id : nil }
                                .onTapGesture {
                                    vm.restore(entry)
                                    isPresented = false
                                }
                                .contextMenu {
                                    Button("Restore") {
                                        vm.restore(entry)
                                        isPresented = false
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        vm.deleteHistory(id: entry.id)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 360, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var isHovered: Bool

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(entry.config.param, systemImage: "key")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(optionCountLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if !entry.config.jsonpath.isEmpty {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer()

            Text(Self.dateFormatter.localizedString(for: entry.timestamp, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .padding(.horizontal, 4)
    }

    private var optionCountLabel: String {
        let count = OptionsParser.parse(entry.optionsText).count
        return count == 1 ? "1 option" : "\(count) options"
    }
}
