import SwiftUI

struct CurlBreakdownView: View {
    @EnvironmentObject var vm: ScanViewModel
    @State private var urlExpanded = true
    @State private var queryExpanded = true
    @State private var headersExpanded = true
    @State private var bodyExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                urlSection
                Divider().padding(.horizontal, 8)
                querySection
                Divider().padding(.horizontal, 8)
                headersSection
                Divider().padding(.horizontal, 8)
                bodySection
            }
        }
    }

    // MARK: - URL Section

    @ViewBuilder
    private var urlSection: some View {
        HStack {
            Text("URL")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            Spacer()
        }
        if let bd = vm.curlBreakdown {
            TextField("https://…", text: Binding(
                get: { bd.baseURL },
                set: { vm.curlBreakdown?.baseURL = $0 }
            ))
            .font(.system(size: 11, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .textSelection(.enabled)
        }
    }

    // MARK: - Query Params

    @ViewBuilder
    private var querySection: some View {
        let count = vm.curlBreakdown?.queryParams.filter(\.isEnabled).count ?? 0
        paramSection(
            title: "Query",
            badge: count > 0 ? "\(count)" : nil,
            isExpanded: $queryExpanded,
            params: Binding(
                get: { vm.curlBreakdown?.queryParams ?? [] },
                set: { vm.curlBreakdown?.queryParams = $0 }
            )
        )
    }

    // MARK: - Headers

    @ViewBuilder
    private var headersSection: some View {
        let count = vm.curlBreakdown?.headers.filter(\.isEnabled).count ?? 0
        paramSection(
            title: "Headers",
            badge: count > 0 ? "\(count)" : nil,
            isExpanded: $headersExpanded,
            params: Binding(
                get: { vm.curlBreakdown?.headers ?? [] },
                set: { vm.curlBreakdown?.headers = $0 }
            )
        )
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySection: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { bodyExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(bodyExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: bodyExpanded)
                        Text("Body")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if vm.curlBreakdown != nil {
                    Toggle("Raw", isOn: Binding(
                        get: { vm.curlBreakdown?.bodyIsRaw ?? true },
                        set: { vm.curlBreakdown?.bodyIsRaw = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            if bodyExpanded, let bd = vm.curlBreakdown {
                if bd.bodyIsRaw {
                    TextEditor(text: Binding(
                        get: { bd.rawBody },
                        set: { vm.updateBreakdownRawBody($0) }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                } else {
                    paramRows(
                        params: Binding(
                            get: { vm.curlBreakdown?.bodyParams ?? [] },
                            set: { vm.curlBreakdown?.bodyParams = $0 }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Reusable param section

    @ViewBuilder
    private func paramSection(
        title: String,
        badge: String?,
        isExpanded: Binding<Bool>,
        params: Binding<[HTTPParam]>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                            .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)
                        Text(title)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    params.wrappedValue.append(HTTPParam(key: "", value: ""))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            if isExpanded.wrappedValue {
                paramRows(params: params)
            }
        }
    }

    // MARK: - Param rows

    @ViewBuilder
    private func paramRows(params: Binding<[HTTPParam]>) -> some View {
        VStack(spacing: 2) {
            ForEach(params.wrappedValue.indices, id: \.self) { i in
                paramRow(
                    param: params[i],
                    onDelete: { params.wrappedValue.remove(at: i) }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func paramRow(param: Binding<HTTPParam>, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Toggle("", isOn: param.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            TextField("key", text: param.key)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .textSelection(.enabled)

            Text("=")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("value", text: param.value)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                .textSelection(.enabled)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
