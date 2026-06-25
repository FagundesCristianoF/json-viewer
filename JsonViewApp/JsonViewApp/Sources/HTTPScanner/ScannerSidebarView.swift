import SwiftUI
import UniformTypeIdentifiers

struct ScannerSidebarView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showCurlImporter = false
    @State private var showOptionsImporter = false
    @State private var savedExpanded = true
    @State private var renamingID: UUID? = nil
    @State private var renameText: String = ""
    @State private var curlExpanded = true
    @State private var optionsExpanded = true
    @State private var resultSearch: String = ""

    private var filteredResults: [OptionResult] {
        guard !resultSearch.isEmpty else { return vm.mergedForDisplay }
        return vm.mergedForDisplay.filter {
            $0.responseBody?.localizedCaseInsensitiveContains(resultSearch) == true ||
            ($0.displayName ?? $0.id).localizedCaseInsensitiveContains(resultSearch)
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        if !vm.savedRequests.isEmpty {
            DisclosureGroup(isExpanded: $savedExpanded) {
                VStack(spacing: 1) {
                    ForEach(vm.savedRequests) { entry in
                        savedRow(entry)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            } label: {
                SectionHeader(title: "Saved", systemImage: "bookmark.fill")
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(SidebarDisclosureStyle())

            Divider().padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func savedRow(_ entry: SavedRequest) -> some View {
        let isActive = vm.currentSavedRequestID == entry.id

        HStack(spacing: 8) {
            Image(systemName: isActive ? "bookmark.fill" : "bookmark")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            if renamingID == entry.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        vm.renameSavedRequest(id: entry.id, name: renameText.isEmpty ? entry.name : renameText)
                        renamingID = nil
                    }
                    .onExitCommand { renamingID = nil }
            } else {
                Text(entry.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.loadSavedRequest(entry)
        }
        .contextMenu {
            Button("Load") { vm.loadSavedRequest(entry) }
            Button("Rename") {
                renameText = entry.name
                renamingID = entry.id
            }
            Button("Overwrite with current") { vm.overwriteSavedRequest(id: entry.id) }
            Divider()
            Button("Delete", role: .destructive) { vm.deleteSavedRequest(id: entry.id) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            savedSection

            // MARK: Curl section
            DisclosureGroup(isExpanded: $curlExpanded) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if vm.curlText.isEmpty {
                            Text("curl -X POST 'https://…' \\\n  -H 'Authorization: Bearer …' \\\n  -d '{\"accountId\":\"…\"}'")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8).padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.curlText)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(4)
                            .frame(minHeight: 120, maxHeight: 200)
                            .onChange(of: vm.curlText) { _ in vm.validateCurl() }
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(.horizontal, 8).padding(.bottom, 6)

                    if let err = vm.parseError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                            Text(err).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 10).padding(.bottom, 6)
                    }

                    HStack {
                        Spacer()
                        Button { vm.curlText = ""; vm.parseError = nil } label: {
                            Image(systemName: "xmark.circle").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.clear"))
                        Button { showCurlImporter = true } label: {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.import_file"))
                    }
                    .padding(.horizontal, 10).padding(.bottom, 6)
                }
            } label: {
                SectionHeader(title: String(localized: "section.curl_command"), systemImage: "terminal")
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(SidebarDisclosureStyle())

            Divider().padding(.horizontal, 8)

            // MARK: Options section
            DisclosureGroup(isExpanded: $optionsExpanded) {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if vm.optionsText.isEmpty {
                            Text("[{\"id\":\"uuid-1\",\"displayName\":\"Account 1\"},…]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8).padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.optionsText)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(4)
                            .frame(minHeight: 60, maxHeight: 120)
                    }
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .padding(.horizontal, 8).padding(.bottom, 4)

                    HStack {
                        Text("\(vm.optionCount) option\(vm.optionCount == 1 ? "" : "s")")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button { vm.optionsText = "" } label: {
                            Image(systemName: "xmark.circle").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.clear"))
                        Button { showOptionsImporter = true } label: {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "action.import_file"))
                    }
                    .padding(.horizontal, 10).padding(.bottom, 4)

                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Text("ID path")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            SuggestionTextField(
                                placeholder: "id",
                                text: $vm.config.optionIdPath,
                                suggestions: vm.pathSuggestions
                            )
                        }
                        HStack(spacing: 6) {
                            Text("Name path")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            SuggestionTextField(
                                placeholder: "displayName",
                                text: $vm.config.optionNamePath,
                                suggestions: vm.pathSuggestions
                            )
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 4)

                    if !vm.mergedForDisplay.isEmpty {
                        Divider().padding(.horizontal, 8).padding(.vertical, 2)

                        if vm.config.isFilterMode && vm.selectedResultID != nil && !vm.matchingEntries.isEmpty {
                            Button {
                                vm.selectedResultID = nil
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.green)
                                    Text(String(format: String(localized: "scanner.show_matches"), vm.matchingEntries.count))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }

                        if !vm.results.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                TextField("Search responses…", text: $resultSearch)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                if !resultSearch.isEmpty {
                                    Button { resultSearch = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.6))

                            Divider().padding(.horizontal, 8)
                        }

                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredResults) { result in
                                    OptionRow(result: result, isSelected: vm.selectedResultID == result.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { vm.selectedResultID = result.id }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            } label: {
                SectionHeader(title: String(localized: "section.options"), systemImage: "list.bullet")
                    .contentShape(Rectangle())
            }
            .disclosureGroupStyle(SidebarDisclosureStyle())

            Spacer()

            if let err = vm.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(3)
                        .textSelection(.enabled)
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: vm.isRunning) { running in
            if running { resultSearch = "" }
        }
        .fileImporter(isPresented: $showCurlImporter, allowedContentTypes: [.text, .plainText]) { result in
            if case .success(let url) = result { vm.importCurlFile(url) }
        }
        .fileImporter(isPresented: $showOptionsImporter, allowedContentTypes: [.json, .text]) { result in
            if case .success(let url) = result { vm.importOptionsFile(url) }
        }
    }
}

// MARK: - Disclosure style

struct SidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                configuration.label
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: configuration.isExpanded)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { configuration.isExpanded.toggle() } }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            if configuration.isExpanded { configuration.content }
        }
    }
}
