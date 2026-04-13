import SwiftUI

@main
struct DenonControllerApp: App {
    // アプリ全体で共有する ViewModel（メインウィンドウ・設定画面が同一インスタンスを使用）
    @State private var vm = MainViewModel()

    var body: some Scene {
        // ── Main Window ────────────────────────────────────────────────
        WindowGroup {
            ContentView()
                .environment(vm)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .help) {
                Link("Denon AVR プロトコルリファレンス",
                     destination: URL(string: "https://www.denon.com")!)
            }
        }

        // ── Menu Bar Extra ─────────────────────────────────────────────
        MenuBarExtra("Denon Controller", systemImage: "hifispeaker.fill") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.window)

        // ── Settings ───────────────────────────────────────────────────
        Settings {
            SettingsView()
                .environment(vm)
        }
    }
}

/// メニューバーポップオーバー（メインウィンドウとは別の接続インスタンスを持つ）
private struct MenuBarContent: View {
    @State private var vm = MainViewModel()

    var body: some View {
        MenuBarPopoverView()
            .environment(vm)
            .onAppear {
                let host = UserDefaults.standard.string(forKey: "defaultHost") ?? ""
                let auto = UserDefaults.standard.bool(forKey: "autoConnect")
                if auto && !host.isEmpty && !vm.connectionStatus.isConnected {
                    Task { await vm.connect(host: host) }
                }
            }
    }
}
