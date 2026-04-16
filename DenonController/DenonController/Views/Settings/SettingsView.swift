import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultHost")  private var defaultHost = ""
    @AppStorage("autoConnect")  private var autoConnect = false
    @AppStorage("showInDock")   private var showInDock = true
    @AppStorage("menuBarOnly")  private var menuBarOnly = false
    @AppStorage("appLanguage")  private var appLanguage = "system"
    @AppStorage("debugMode")    private var debugMode = false
    @Environment(MainViewModel.self) private var vm
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section("接続設定") {
                TextField("AVR の IP アドレス", text: $defaultHost)
                    .onSubmit { connectIfNeeded() }

                Toggle("起動時に自動接続", isOn: $autoConnect)

                if !defaultHost.isEmpty {
                    Button(vm.connectionStatus.isConnected ? LocalizedStringKey("再接続") : LocalizedStringKey("今すぐ接続")) {
                        connectIfNeeded()
                    }
                    .disabled(vm.connectionStatus == .connecting)
                }

                if case .error(let msg) = vm.connectionStatus {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("アプリ") {
                Picker("表示言語", selection: $appLanguage) {
                    Text("システム設定に従う").tag("system")
                    Text("日本語").tag("ja")
                    Text("English").tag("en")
                }

                Toggle("Dock にアイコンを表示", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }

                Toggle("起動時はメニューバーのみ（メインウィンドウを表示しない）", isOn: $menuBarOnly)

                if menuBarOnly {
                    Text("次回起動時から適用されます。メインウィンドウはメニューバーの「詳細を開く」から開けます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("入力ソース") {
                ForEach(InputSource.allCases) { source in
                    HStack(spacing: 12) {
                        // 使用/非表示トグル
                        Toggle("", isOn: Binding(
                            get: { !vm.inputNames.isHidden(source) },
                            set: { vm.inputNames.setHidden(!$0, for: source) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)

                        // デフォルト名（変更不可ラベル）
                        Text(source.displayName)
                            .frame(width: 110, alignment: .leading)
                            .foregroundStyle(vm.inputNames.isHidden(source) ? .secondary : .primary)

                        // カスタム名テキストフィールド
                        TextField("カスタム名（省略可）",
                                  text: Binding(
                                    get: { vm.inputNames.customName(for: source) ?? "" },
                                    set: { vm.inputNames.setName($0, for: source) }
                                  ))
                        .textFieldStyle(.roundedBorder)
                        .disabled(vm.inputNames.isHidden(source))
                        .foregroundStyle(vm.inputNames.isHidden(source) ? .secondary : .primary)
                    }
                }
            }

            Section("開発者") {
                Toggle("デバッグモード", isOn: $debugMode)
                if debugMode {
                    Text("チューナー画面に Raw Data 確認パネルが表示されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("バージョン情報") {
                LabeledContent("アプリ", value: "Denon / Marantz Controller")
                LabeledContent("バージョン", value: "1.0.0")
                if !vm.avr.deviceInfo.modelName.isEmpty {
                    LabeledContent("接続中の機種", value: vm.avr.deviceInfo.modelName)
                    LabeledContent("ブランド", value: vm.avr.deviceInfo.brandName)
                } else {
                    LabeledContent("対応機種", value: "Denon / Marantz AVR（HTTP API 対応機種）")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear { fixWindowTitle() }
        .onChange(of: locale) { fixWindowTitle() }
    }

    private func fixWindowTitle() {
        DispatchQueue.main.async {
            let word = localizedNavTitle("設定", locale: locale)
            let newTitle = "Denon Controller \(word)"
            for window in NSApplication.shared.windows {
                guard window.title.hasPrefix("Denon Controller"),
                      window.title.hasSuffix("設定") || window.title.hasSuffix("Settings") || window.title.hasSuffix("Preferences")
                else { continue }
                window.title = newTitle
            }
        }
    }

    private func connectIfNeeded() {
        guard !defaultHost.isEmpty else { return }
        Task { await vm.connect(host: defaultHost) }
    }
}
