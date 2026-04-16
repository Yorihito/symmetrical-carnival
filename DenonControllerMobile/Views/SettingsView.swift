import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultHost")  private var defaultHost  = ""
    @AppStorage("autoConnect")  private var autoConnect  = false
    @AppStorage("appLanguage")  private var appLanguage  = "system"
    @AppStorage("debugMode")    private var debugMode    = false
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale
    @Binding var showConnection: Bool

    var body: some View {
        Form {
            connectionSection
            appSection
            inputSourcesSection
            developerSection
            aboutSection
        }
        .navigationTitle(localizedNavTitle("設定", locale: locale))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            // 現在の接続状態
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(vm.connectionStatus.label)
                    .font(.callout)
                if case .error(let msg) = vm.connectionStatus {
                    Spacer()
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            // IP 入力
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                TextField("AVR の IP アドレス", text: $defaultHost)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { triggerConnect() }
            }

            Toggle("起動時に自動接続", isOn: $autoConnect)

            // 接続ボタン
            Button {
                if vm.connectionStatus.isConnected {
                    vm.disconnect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        triggerConnect()
                    }
                } else {
                    triggerConnect()
                }
            } label: {
                HStack {
                    Spacer()
                    Text(vm.connectionStatus.isConnected
                         ? LocalizedStringKey("再接続")
                         : LocalizedStringKey("今すぐ接続"))
                    Spacer()
                }
            }
            .disabled(defaultHost.isEmpty || vm.connectionStatus == .connecting)

            // mDNS 検索
            Button {
                showConnection = true
            } label: {
                Label("デバイスを検索", systemImage: "magnifyingglass")
            }
        } header: {
            Text("接続設定")
        }
    }

    private func triggerConnect() {
        guard !defaultHost.isEmpty else { return }
        UserDefaults.standard.set(defaultHost, forKey: "defaultHost")
        Task { await vm.connect(host: defaultHost) }
    }

    private var statusColor: Color {
        switch vm.connectionStatus {
        case .connected:            .green
        case .connecting:           .orange
        case .disconnected, .error: .red
        }
    }

    // MARK: - App

    private var appSection: some View {
        Section("アプリ") {
            Picker("表示言語", selection: $appLanguage) {
                Text("システム設定に従う").tag("system")
                Text("日本語").tag("ja")
                Text("English").tag("en")
            }
        }
    }

    // MARK: - Input Sources

    private var inputSourcesSection: some View {
        Section("入力ソース") {
            ForEach(InputSource.allCases) { source in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { !vm.inputNames.isHidden(source) },
                        set: { vm.inputNames.setHidden(!$0, for: source) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()

                    Label(source.displayName, systemImage: source.systemImage)
                        .foregroundStyle(vm.inputNames.isHidden(source) ? .secondary : .primary)

                    Spacer()

                    TextField("カスタム名",
                              text: Binding(
                                get: { vm.inputNames.customName(for: source) ?? "" },
                                set: { vm.inputNames.setName($0, for: source) }
                              ))
                    .font(.callout)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 120)
                    .disabled(vm.inputNames.isHidden(source))
                }
            }
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        Section("開発者") {
            Toggle("デバッグモード", isOn: $debugMode)
            if debugMode {
                Text("チューナー画面に Raw Data 確認パネルが表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("バージョン情報") {
            LabeledContent("アプリ", value: "Denon / Marantz Controller")
            LabeledContent("バージョン", value: "1.0.0")
            if !vm.avr.deviceInfo.modelName.isEmpty {
                LabeledContent("接続中の機種", value: vm.avr.deviceInfo.modelName)
                LabeledContent("ブランド", value: vm.avr.deviceInfo.brandName)
            }
        }
    }
}
