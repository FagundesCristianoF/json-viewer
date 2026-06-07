import SwiftUI
import UniformTypeIdentifiers

struct ScannerSidebarView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var showCurlImporter = false
    @State private var showOptionsImporter = false
    @State private var curlExpanded = true
    @State private var optionsExpanded = true

    var body: some View {
        VStack(spacing: 0) {

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
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear")
                        Button { showOptionsImporter = true } label: {
                            Image(systemName: "doc.badge.arrow.up").font(.system(size: 11))
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Import from file")
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
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(vm.mergedForDisplay) { result in
                                    OptionRow(result: result, isSelected: vm.selectedResultID == result.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { vm.selectedResultID = result.id }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .frame(maxHeight: 320)
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
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            configuration.label
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { configuration.isExpanded.toggle() } }
            if configuration.isExpanded { configuration.content }
        }
    }
}
