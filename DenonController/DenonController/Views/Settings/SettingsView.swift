import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultHost") private var defaultHost = ""
    @AppStorage("autoConnect")  private var autoConnect = false
    @AppStorage("showInDock")   private var showInDock = true
    @Environment(MainViewModel.self) private var vm

    var body: some View {
        Form {
            Section("接続") {
                TextField("AVR の IP アドレス", text: $defaultHost)
                    .onSubmit { connectIfNeeded() }

                LabeledContent("ポート") {
                    Text("8080（固定）")
                        .foregroundStyle(.secondary)
                }

                Toggle("起動時に自動接続", isOn: $autoConnect)

                if !defaultHost.isEmpty {
                    Button(vm.connectionStatus.isConnected ? "再接続" : "今すぐ接続") {
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
                Toggle("Dock にアイコンを表示", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            }

            Section("バージョン情報") {
                LabeledContent("アプリ", value: "Denon Controller")
                LabeledContent("バージョン", value: "1.0.0")
                LabeledContent("対応機種", value: "AVR-X3800H")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 340)
    }

    private func connectIfNeeded() {
        guard !defaultHost.isEmpty else { return }
        Task { await vm.connect(host: defaultHost) }
    }
}
