import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultHost") private var defaultHost = ""
    @AppStorage("defaultPort") private var defaultPort = 23
    @AppStorage("autoConnect")  private var autoConnect = false
    @AppStorage("showInDock")   private var showInDock = true

    var body: some View {
        Form {
            Section("接続") {
                TextField("デフォルト IP アドレス", text: $defaultHost)
                Stepper("ポート: \(defaultPort)", value: $defaultPort, in: 1...65535)
                Toggle("起動時に自動接続", isOn: $autoConnect)
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
        .frame(width: 400, height: 320)
    }
}
