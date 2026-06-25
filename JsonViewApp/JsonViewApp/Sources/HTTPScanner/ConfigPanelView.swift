import SwiftUI

struct ConfigPanelView: View {
    @EnvironmentObject var vm: ScanViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // MARK: Parameter
                groupBox {
                    SectionHeader(title: String(localized: "section.parameter"), systemImage: "key")
                    fieldRow(String(localized: "field.replace_param")) {
                        HStack(spacing: 4) {
                            TextField("accountId", text: $vm.config.param)
                                .monoTextField()
                            if !vm.detectedBodyKeys.isEmpty {
                                Menu {
                                    ForEach(vm.detectedBodyKeys, id: \.self) { key in
                                        Button(key) { vm.config.param = key }
                                    }
                                } label: {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Pick from curl body keys")
                            }
                        }
                    }
                }

                Divider()

                // MARK: Filters
                groupBox {
                    SectionHeader(title: String(localized: "section.filters"), systemImage: "line.3.horizontal.decrease.circle")

                    fieldRow(String(localized: "field.jsonpath")) {
                        TextField("$.products[?(@.active == true)]", text: $vm.config.jsonpath)
                            .monoTextField()
                    }

                    requireGroupsSection

                    fieldRow(String(localized: "field.body_query")) {
                        TextField("search term", text: $vm.config.query)
                            .monoTextField()
                    }
                }

                Divider()

                // MARK: Execution
                groupBox {
                    SectionHeader(title: String(localized: "section.execution"), systemImage: "bolt.circle")

                    fieldRow(String(localized: "field.workers")) {
                        Stepper(value: $vm.config.workers, in: 1...64) {
                            Text("\(vm.config.workers)")
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 28, alignment: .trailing)
                        }
                    }

                    fieldRow(String(localized: "field.timeout")) {
                        HStack(spacing: 4) {
                            TextField("30", value: $vm.config.timeout, format: .number)
                                .monoTextField()
                                .frame(maxWidth: 70)
                            Text("s")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // MARK: Mode badge
                if vm.config.isFilterMode {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(String(localized: "status.filter_mode_active"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text(String(localized: "status.dump_mode"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 20)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    var requireGroupsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "field.require_results"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                ForEach(vm.config.requireGroups.indices, id: \.self) { gi in
                    VStack(spacing: 0) {
                        // AND separator between groups
                        if gi > 0 {
                            HStack {
                                Rectangle().frame(height: 0.5).foregroundStyle(Color(nsColor: .separatorColor))
                                Text(String(localized: "config.require.and"))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                                Rectangle().frame(height: 0.5).foregroundStyle(Color(nsColor: .separatorColor))
                            }
                            .padding(.vertical, 4)
                        }

                        // Group box
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(vm.config.requireGroups[gi].rules.indices, id: \.self) { ri in
                                VStack(spacing: 0) {
                                    if ri > 0 {
                                        HStack {
                                            Text(String(localized: "config.require.or"))
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .padding(.leading, 8)
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    HStack(spacing: 4) {
                                        TextField("$.path[*]", text: $vm.config.requireGroups[gi].rules[ri].path)
                                            .monoTextField()
                                        Button {
                                            if vm.config.requireGroups[gi].rules.count == 1 {
                                                vm.config.requireGroups.remove(at: gi)
                                            } else {
                                                vm.config.requireGroups[gi].rules.remove(at: ri)
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 16, height: 16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Button {
                                vm.config.requireGroups[gi].rules.append(FilterRule(path: ""))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text(String(localized: "config.require.add_or_rule"))
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 5)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    }
                }

                Button {
                    vm.config.requireGroups.append(FilterGroup())
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(vm.config.requireGroups.isEmpty
                             ? String(localized: "config.require.add_first_group")
                             : String(localized: "config.require.add_and_group"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    func groupBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) { content() }
            .padding(.vertical, 8)
    }

    @ViewBuilder
    func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

private extension View {
    func monoTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            .frame(maxWidth: .infinity)
    }
}
