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
    @Environment(\.localizedBundle) private var bundle
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section(header: Text("接続設定", bundle: bundle)) {
                TextField(LS("AVR の IP アドレス", bundle), text: $defaultHost)
                    .onSubmit { connectIfNeeded() }

                Toggle(isOn: $autoConnect) {
                    Text("起動時に自動接続", bundle: bundle)
                }

                if !defaultHost.isEmpty {
                    Button {
                        connectIfNeeded()
                    } label: {
                        Text(vm.connectionStatus.isConnected ? LS("再接続", bundle) : LS("今すぐ接続", bundle))
                    }
                    .disabled(vm.connectionStatus == .connecting)
                }

                if case .error(let msg) = vm.connectionStatus {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(header: Text("アプリ", bundle: bundle)) {
                Picker(selection: $appLanguage) {
                    Text("システム設定に従う", bundle: bundle).tag("system")
                    Text("日本語", bundle: bundle).tag("ja")
                    Text("English", bundle: bundle).tag("en")
                } label: {
                    Text("表示言語", bundle: bundle)
                }

                Toggle(isOn: $showInDock) {
                    Text("Dock にアイコンを表示", bundle: bundle)
                }
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }

                Toggle(isOn: $menuBarOnly) {
                    Text("起動時はメニューバーのみ（メインウィンドウを表示しない）", bundle: bundle)
                }

                if menuBarOnly {
                    Text("次回起動時から適用されます。メインウィンドウはメニューバーの「詳細を開く」から開けます。", bundle: bundle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("入力ソース", bundle: bundle)) {
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
                        TextField(LS("カスタム名", bundle),
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

            Section(header: Text("開発者", bundle: bundle)) {
                Toggle(isOn: $debugMode) {
                    Text("デバッグモード", bundle: bundle)
                }
                if debugMode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("チューナー画面に Raw Data 確認パネルが表示されます。", bundle: bundle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        Text("Localization Debug:", bundle: bundle)
                            .font(.caption.weight(.bold))
                        Text("Main: \(Bundle.main.localizations.joined(separator: ", "))")
                            .font(.system(size: 10, design: .monospaced))
                        Text("Pref: \(Bundle.main.preferredLocalizations.joined(separator: ", "))")
                            .font(.system(size: 10, design: .monospaced))
                        Text("en.lproj: \(Bundle.main.path(forResource: "en", ofType: "lproj") != nil ? "FOUND" : "NOT FOUND")")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
            }

            Section(header: Text("バージョン情報", bundle: bundle)) {
                LabeledContent {
                    Text("Denon / Marantz Controller")
                } label: {
                    Text("アプリ", bundle: bundle)
                }
                LabeledContent {
                    Text("1.0.0")
                } label: {
                    Text("バージョン", bundle: bundle)
                }
                if !vm.avr.deviceInfo.modelName.isEmpty {
                    LabeledContent {
                        Text(vm.avr.deviceInfo.modelName)
                    } label: {
                        Text("接続中の機種", bundle: bundle)
                    }
                    LabeledContent {
                        Text(vm.avr.deviceInfo.brandName)
                    } label: {
                        Text("ブランド", bundle: bundle)
                    }
                } else {
                    LabeledContent {
                        Text("Denon / Marantz AVR（HTTP API 対応機種）", bundle: bundle)
                    } label: {
                        Text("対応機種", bundle: bundle)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label(LS("すべての設定をリセット", bundle), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("リセット", bundle: bundle)
            } footer: {
                Text("接続先、入力ソース名、プリセット、アプリ設定などすべてを初期値に戻します。", bundle: bundle)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 680)
        .onAppear { fixWindowTitle() }
        .onChange(of: locale) { fixWindowTitle() }
        .alert(Text("すべての設定をリセット", bundle: bundle), isPresented: $showResetAlert) {
            Button(LS("リセット", bundle), role: .destructive) { Task { await resetToDefaults() } }
            Button(LS("キャンセル", bundle), role: .cancel) { }
        } message: {
            Text("すべての設定が初期値に戻ります。この操作は取り消せません。", bundle: bundle)
        }
    }

    private func fixWindowTitle() {
        DispatchQueue.main.async {
            let word = localizedNavTitle("設定", locale: locale)
            for window in NSApplication.shared.windows {
                let t = window.title
                if t.hasSuffix("設定") || t.hasSuffix("Settings") || t.hasSuffix("Preferences") || t == "設定" || t == "Settings" {
                    window.title = word
                }
            }
        }
    }

    private func connectIfNeeded() {
        guard !defaultHost.isEmpty else { return }
        Task { await vm.connect(host: defaultHost) }
    }

    private func resetToDefaults() async {
        // 先に切断を完了させる
        await vm.disconnect()

        // 接続・アプリ設定
        defaultHost  = ""
        autoConnect  = false
        showInDock   = true
        menuBarOnly  = false
        appLanguage  = "system"
        debugMode    = false

        // 入力ソース名・非表示設定
        UserDefaults.standard.removeObject(forKey: "customInputNames")
        UserDefaults.standard.removeObject(forKey: "hiddenInputSources")
        vm.inputNames.reset()

        // チューナープリセット・スキップ周波数
        UserDefaults.standard.removeObject(forKey: "savedTunerPresets")
        UserDefaults.standard.removeObject(forKey: "tunerSkipFrequencies")

        // コントロールプリセット
        vm.presetStore.reset()
    }
}
